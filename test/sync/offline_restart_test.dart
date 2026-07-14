import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/events/event_emitter.dart';
import 'package:sidekick/core/events/events_repository.dart';
import 'package:sidekick/core/sync/connectivity_service.dart';
import 'package:sidekick/core/sync/sync_engine.dart';
import 'package:sidekick/features/tasks/data/tasks_repository_impl.dart';
import 'package:sidekick/features/tasks/domain/task.dart';

import '../support/fakes.dart';

/// Connectivity whose state can be flipped, so a test can go offline → online.
class _ToggleConnectivity implements ConnectivityService {
  _ToggleConnectivity({required this.connected});
  bool connected;
  final StreamController<bool> controller = StreamController<bool>.broadcast();
  @override
  Future<bool> isConnected() async => connected;
  @override
  Stream<bool> get onConnectedChanged => controller.stream;
}

/// The full crash-recovery arc the P2 review asked to prove end-to-end, against
/// a real FILE-BACKED drift database (not the in-memory DB the other sync tests
/// use). The persisted Supabase session is stood in for by re-supplying the
/// same `userId` after reopen — session restore is Supabase's own tested path;
/// what this exercises is that the LOCAL dirty state survives on disk across a
/// process kill and flushes on reconnect.
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sidekick_restart_');
    dbFile = File('${tempDir.path}/sidekick.sqlite');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  AppDatabase openDb() =>
      AppDatabase.forTesting(NativeDatabase(dbFile));

  TasksRepositoryImpl tasksRepo(AppDatabase db) => TasksRepositoryImpl(
    db: db,
    emitter: EventEmitter(DriftEventsRepository(db), IdGenerator()),
    idGenerator: IdGenerator(),
    userId: 'u1',
  );

  DriftSyncEngine engine(
    AppDatabase db,
    FakeSyncGateway gateway,
    ConnectivityService connectivity,
  ) => DriftSyncEngine(
    db: db,
    gateway: gateway,
    connectivity: connectivity,
    userId: 'u1',
  );

  test(
    'an offline dirty write survives a cold restart and flushes on reconnect',
    () async {
      final FakeSyncGateway gateway = FakeSyncGateway();

      // --- Session 1: create a task while OFFLINE. -----------------------
      final AppDatabase db1 = openDb();
      final Task task = await tasksRepo(db1).create(title: 'Written offline');

      // A flush attempt while offline must fail silently and leave the row
      // dirty — never mark an unsent payload clean.
      gateway.failPush = true;
      await engine(db1, gateway, _ToggleConnectivity(connected: false)).flush();

      final TaskRow beforeKill = await (db1.select(db1.tasks)
            ..where((Tasks t) => t.id.equals(task.id)))
          .getSingle();
      expect(beforeKill.dirty, isTrue, reason: 'offline flush kept it dirty');
      expect(gateway.pushes, isEmpty, reason: 'nothing reached the server');

      // Simulate the process being KILLED (not gracefully closed).
      await db1.close();

      // --- Session 2: cold reopen of the SAME file. ----------------------
      final AppDatabase db2 = openDb();
      final TaskRow afterReopen = await (db2.select(db2.tasks)
            ..where((Tasks t) => t.id.equals(task.id)))
          .getSingle();
      expect(
        afterReopen.title,
        'Written offline',
        reason: 'the row persisted on disk across the restart',
      );
      expect(
        afterReopen.dirty,
        isTrue,
        reason: 'still queued for sync after the restart',
      );

      // --- Reconnect: the queued row now flushes cleanly. ----------------
      gateway.failPush = false;
      await engine(db2, gateway, _ToggleConnectivity(connected: true)).flush();

      final PushCall pushed =
          gateway.pushes.firstWhere((PushCall p) => p.table == 'tasks');
      expect(pushed.rows.single['id'], task.id);

      final TaskRow synced = await (db2.select(db2.tasks)
            ..where((Tasks t) => t.id.equals(task.id)))
          .getSingle();
      expect(synced.dirty, isFalse, reason: 'flushed on reconnect');
      expect(synced.syncedAt, isNotNull);

      await db2.close();
    },
  );
}

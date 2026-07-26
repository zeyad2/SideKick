import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/core/events/event_emitter.dart';
import 'package:sidekick/core/events/events_repository.dart';
import 'package:sidekick/core/sync/connectivity_service.dart';
import 'package:sidekick/core/sync/sync_engine.dart';
import 'package:sidekick/features/inbox/data/captures_repository_impl.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/inbox/domain/proposed_item.dart';
import 'package:sidekick/features/tasks/data/tasks_repository_impl.dart';
import 'package:sidekick/features/tasks/domain/task.dart';

import '../support/fakes.dart';

class _StubConnectivity implements ConnectivityService {
  final StreamController<bool> controller = StreamController<bool>.broadcast();
  @override
  Future<bool> isConnected() async => true;
  @override
  Stream<bool> get onConnectedChanged => controller.stream;
}

DateTime _fixed(String iso) => DateTime.parse(iso);

Map<String, Object?> _remoteTaskRow({
  required String id,
  required String title,
  required String updatedAt,
}) => <String, Object?>{
  'id': id,
  'user_id': 'u1',
  'title': title,
  'status': 'todo',
  'created_at': updatedAt,
  'updated_at': updatedAt,
  'last_activity_at': updatedAt,
  'deleted_at': null,
};

void main() {
  late AppDatabase db;
  late FakeSyncGateway gateway;
  late _StubConnectivity connectivity;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    gateway = FakeSyncGateway();
    connectivity = _StubConnectivity();
  });

  tearDown(() => db.close());

  DriftSyncEngine engine() => DriftSyncEngine(
    db: db,
    gateway: gateway,
    connectivity: connectivity,
    userId: 'u1',
  );

  TasksRepositoryImpl tasksRepo({DateTime Function()? clock}) =>
      TasksRepositoryImpl(
        db: db,
        emitter: EventEmitter(DriftEventsRepository(db), IdGenerator()),
        idGenerator: IdGenerator(),
        userId: 'u1',
        clock: clock,
      );

  test('flush pushes dirty rows then clears dirty + sets synced_at', () async {
    final Task task = await tasksRepo().create(title: 'Sync me');

    await engine().flush();

    expect(gateway.pushes, isNotEmpty);
    final PushCall taskPush = gateway.pushes.firstWhere(
      (PushCall p) => p.table == 'tasks',
    );
    expect(taskPush.rows.single['id'], task.id);
    // Local-only columns are never pushed (R0).
    expect(taskPush.rows.single.containsKey('dirty'), isFalse);
    expect(taskPush.rows.single.containsKey('synced_at'), isFalse);

    final TaskRow row = await (db.select(
      db.tasks,
    )..where((Tasks t) => t.id.equals(task.id))).getSingle();
    expect(row.dirty, isFalse);
    expect(row.syncedAt, isNotNull);
  });

  test('events push is INSERT-ONLY (D9)', () async {
    final DriftEventsRepository events = DriftEventsRepository(db);
    await events.append(
      DomainEvent(
        id: IdGenerator().v4(),
        userId: 'u1',
        eventType: 'capture_created',
        occurredAt: DateTime.now().toUtc(),
      ),
    );

    await engine().flush();

    final PushCall eventsPush = gateway.pushes.firstWhere(
      (PushCall p) => p.table == 'events',
    );
    expect(eventsPush.insertOnly, isTrue);
  });

  test(
    'capture decomposition JSON pushes decoded and pulls as sqlite text',
    () async {
      final CapturesRepositoryImpl captures = CapturesRepositoryImpl(
        db: db,
        emitter: EventEmitter(DriftEventsRepository(db), IdGenerator()),
        idGenerator: IdGenerator(),
        userId: 'u1',
        clock: () => _fixed('2026-07-12T10:00:00.000Z'),
      );
      final Capture created = await captures.create(source: 'fab');
      const ProposedItem draft = ProposedItem(
        id: 'json-draft',
        kind: ResultingType.task,
        title: 'Round trip',
        confidence: DraftConfidence.high,
      );
      await captures.update(
        created.copyWith(
          proposedItems: const <ProposedItem>[draft],
          dispositionedItemIds: const <String>['json-draft'],
          status: CaptureStatus.triaged,
        ),
      );

      await engine().flush();

      final PushCall pushed = gateway.pushes.firstWhere(
        (call) => call.table == 'captures',
      );
      expect(pushed.rows.single['proposed_items'], isA<List<Object?>>());
      expect(pushed.rows.single['dispositioned_item_ids'], <Object?>[
        'json-draft',
      ]);

      final Map<String, Object?> remote = Map<String, Object?>.of(
        pushed.rows.single,
      )..['updated_at'] = '2026-07-12T11:00:00.000Z';
      gateway.seedRemote('captures', remote);
      await engine().pull();

      final CaptureRow row = await (db.select(
        db.captures,
      )..where((table) => table.id.equals(created.id))).getSingle();
      expect(row.proposedItems, contains('json-draft'));
      expect(row.dispositionedItemIds, '["json-draft"]');
    },
  );

  test('pull upserts remote rows and advances last_pull', () async {
    gateway.seedRemote(
      'tasks',
      _remoteTaskRow(
        id: 'remote-1',
        title: 'From another device',
        updatedAt: '2026-07-12T10:00:00.000Z',
      ),
    );

    await engine().pull();

    final TaskRow row = await (db.select(
      db.tasks,
    )..where((Tasks t) => t.id.equals('remote-1'))).getSingle();
    expect(row.title, 'From another device');
    expect(row.dirty, isFalse, reason: 'a pulled row is clean');

    final SyncMetaData cursor = await (db.select(
      db.syncMeta,
    )..where((SyncMeta m) => m.syncTable.equals('tasks'))).getSingle();
    expect(cursor.lastPull, _fixed('2026-07-12T10:00:00.000Z'));
  });

  test('LWW keeps a newer un-pushed local edit over an older remote', () async {
    // Local edit at t2, still dirty.
    final Task local = await tasksRepo(
      clock: () => _fixed('2026-07-12T12:00:00.000Z'),
    ).create(title: 'Local newer');

    // Older remote row for the same id.
    gateway.seedRemote(
      'tasks',
      _remoteTaskRow(
        id: local.id,
        title: 'Remote older',
        updatedAt: '2026-07-12T09:00:00.000Z',
      ),
    );

    await engine().pull();

    final TaskRow row = await (db.select(
      db.tasks,
    )..where((Tasks t) => t.id.equals(local.id))).getSingle();
    expect(row.title, 'Local newer', reason: 'local dirty + newer wins');
  });

  test('LWW applies a newer remote over the local row', () async {
    final Task local = await tasksRepo(
      clock: () => _fixed('2026-07-12T12:00:00.000Z'),
    ).create(title: 'Local older');

    gateway.seedRemote(
      'tasks',
      _remoteTaskRow(
        id: local.id,
        title: 'Remote newer',
        updatedAt: '2026-07-12T15:00:00.000Z',
      ),
    );

    await engine().pull();

    final TaskRow row = await (db.select(
      db.tasks,
    )..where((Tasks t) => t.id.equals(local.id))).getSingle();
    expect(row.title, 'Remote newer');
    expect(row.dirty, isFalse);
  });

  test('a local edit during an in-flight push is not marked clean', () async {
    // Create at t1, push it. Mid-push, a newer local edit lands at t2.
    final Task task = await tasksRepo(
      clock: () => _fixed('2026-07-12T12:00:00.000Z'),
    ).create(title: 'Original');

    gateway.onPush = () async {
      await tasksRepo(
        clock: () => _fixed('2026-07-12T12:05:00.000Z'),
      ).update(task.copyWith(title: 'Edited mid-flush'));
    };

    await engine().flush();

    final TaskRow row = await (db.select(
      db.tasks,
    )..where((Tasks t) => t.id.equals(task.id))).getSingle();
    expect(
      row.dirty,
      isTrue,
      reason:
          'the version pushed (t1) no longer matches; the t2 edit stays '
          'dirty and will retry',
    );
    expect(row.title, 'Edited mid-flush');
  });

  test('flush is scoped to the signed-in user', () async {
    // User u2 has a dirty row; user u1 is signed in.
    await TasksRepositoryImpl(
      db: db,
      emitter: EventEmitter(DriftEventsRepository(db), IdGenerator()),
      idGenerator: IdGenerator(),
      userId: 'u2',
    ).create(title: 'Belongs to u2');

    // Engine is signed in as u1 (see engine()).
    await engine().flush();

    final bool pushedU2Row = gateway.pushes
        .where((PushCall p) => p.table == 'tasks')
        .expand((PushCall p) => p.rows)
        .any((Map<String, Object?> r) => r['user_id'] == 'u2');
    expect(pushedU2Row, isFalse, reason: "u1's flush must not push u2's rows");
  });

  test('start() triggers a sync when connectivity is regained', () async {
    await tasksRepo().create(title: 'Queued offline');
    final DriftSyncEngine e = engine();
    e.start();

    connectivity.controller.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(gateway.pushes, isNotEmpty);
    await e.dispose();
  });
}

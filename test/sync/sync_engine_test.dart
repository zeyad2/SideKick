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
import 'package:sidekick/features/reminders/data/reminder_events_repository_impl.dart';
import 'package:sidekick/features/reminders/data/task_reminders_repository_impl.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

import '../support/fakes.dart';

class _StubConnectivity implements ConnectivityService {
  final StreamController<bool> controller = StreamController<bool>.broadcast();
  @override
  Future<bool> isConnected() async => true;
  @override
  Stream<bool> get onConnectedChanged => controller.stream;
}

DateTime _fixed(String iso) => DateTime.parse(iso);

Map<String, Object?> _remoteReminderRow({
  required String id,
  required String title,
  required String updatedAt,
  String userId = 'u1',
}) => <String, Object?>{
  'id': id,
  'user_id': userId,
  'title': title,
  'details': null,
  'status': 'active',
  'source': 'typed',
  'confidence': 0.9,
  'trigger_type': 'time',
  'scheduled_at': '2026-08-18T12:00:00.000Z',
  'place_id': null,
  'geofence_transition': null,
  'dwell_seconds': null,
  'auto_commit_deadline_at': null,
  'capture_id': null,
  'draft_id': null,
  'ai_explanation': null,
  'ai_context': <String, Object?>{'remote': true},
  'created_at': updatedAt,
  'updated_at': updatedAt,
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

  TaskRemindersRepositoryImpl remindersRepo({DateTime Function()? clock}) =>
      TaskRemindersRepositoryImpl(
        db: db,
        emitter: EventEmitter(DriftEventsRepository(db), IdGenerator()),
        idGenerator: IdGenerator(),
        userId: 'u1',
        clock: clock,
      );

  test('dirty POC rows flush and strip local-only columns', () async {
    final TaskReminder reminder = await remindersRepo().create(
      TaskReminderDraft(
        title: 'Sync me',
        source: TaskReminderSource.typed,
        confidence: 0.91,
        triggerType: TaskReminderTriggerType.time,
        scheduledAt: DateTime.utc(2026, 8, 18, 12),
        aiContext: const <String, Object?>{'used': true},
      ),
    );

    await engine().flush();

    final PushCall push = gateway.pushes.firstWhere(
      (PushCall p) => p.table == 'task_reminders',
    );
    expect(push.rows.single['id'], reminder.id);
    expect(push.rows.single.containsKey('dirty'), isFalse);
    expect(push.rows.single.containsKey('synced_at'), isFalse);
    expect(push.rows.single['ai_context'], isA<Map<String, Object?>>());

    final TaskReminderRow row = await (db.select(
      db.taskReminders,
    )..where((t) => t.id.equals(reminder.id))).getSingle();
    expect(row.dirty, isFalse);
    expect(row.syncedAt, isNotNull);
  });

  test('pull applies remote rows and advances cursor', () async {
    gateway.seedRemote(
      'task_reminders',
      _remoteReminderRow(
        id: 'remote-1',
        title: 'From another device',
        updatedAt: '2026-08-18T10:00:00.000Z',
      ),
    );

    await engine().pull();

    final TaskReminderRow row = await (db.select(
      db.taskReminders,
    )..where((t) => t.id.equals('remote-1'))).getSingle();
    expect(row.title, 'From another device');
    expect(row.aiContext, '{"remote":true}');
    expect(row.dirty, isFalse);

    final SyncMetaData cursor = await (db.select(
      db.syncMeta,
    )..where((m) => m.syncTable.equals('task_reminders'))).getSingle();
    expect(cursor.lastPull, _fixed('2026-08-18T10:00:00.000Z'));
  });

  test(
    'stale push rejection does not mark divergent local row clean',
    () async {
      final TaskRemindersRepositoryImpl staleRepo = remindersRepo(
        clock: () => DateTime.utc(2026, 8, 18, 9),
      );
      final TaskReminder stale = await staleRepo.create(
        TaskReminderDraft(
          title: 'Stale local value',
          source: TaskReminderSource.typed,
          confidence: 0.91,
          triggerType: TaskReminderTriggerType.time,
          scheduledAt: DateTime.utc(2026, 8, 18, 12),
        ),
      );
      gateway.seedRemote(
        'task_reminders',
        _remoteReminderRow(
          id: stale.id,
          title: 'Newer server value',
          updatedAt: '2026-08-18T15:00:00.000Z',
        ),
      );

      await engine().syncNow();

      final TaskReminderRow row = await (db.select(
        db.taskReminders,
      )..where((t) => t.id.equals(stale.id))).getSingle();
      expect(row.title, 'Newer server value');
      expect(row.dirty, isFalse);
      expect(row.updatedAt, _fixed('2026-08-18T15:00:00.000Z'));
    },
  );

  test(
    'accepted push response does not overwrite newer in-flight local edit',
    () async {
      DateTime repoNow = DateTime.utc(2026, 8, 18, 10);
      final TaskRemindersRepositoryImpl repo = remindersRepo(
        clock: () => repoNow,
      );
      final TaskReminder reminder = await repo.create(
        TaskReminderDraft(
          title: 'Original local value',
          source: TaskReminderSource.typed,
          confidence: 0.91,
          triggerType: TaskReminderTriggerType.time,
          scheduledAt: DateTime.utc(2026, 8, 18, 12),
        ),
      );
      gateway.onPush = () async {
        repoNow = DateTime.utc(2026, 8, 18, 10, 6);
        await repo.update(reminder.copyWith(title: 'Concurrent local edit'));
      };

      await engine().flush();

      final TaskReminderRow row = await (db.select(
        db.taskReminders,
      )..where((t) => t.id.equals(reminder.id))).getSingle();
      expect(row.title, 'Concurrent local edit');
      expect(row.dirty, isTrue);
      expect(row.updatedAt, DateTime.utc(2026, 8, 18, 10, 6));
    },
  );

  test('server clock-skew clamp converges local pushed row', () async {
    final TaskReminder future =
        await remindersRepo(clock: () => DateTime.utc(2026, 8, 18, 11)).create(
          TaskReminderDraft(
            title: 'Future device clock',
            source: TaskReminderSource.typed,
            confidence: 0.91,
            triggerType: TaskReminderTriggerType.time,
            scheduledAt: DateTime.utc(2026, 8, 18, 12),
          ),
        );

    await engine().flush();

    final TaskReminderRow row = await (db.select(
      db.taskReminders,
    )..where((t) => t.id.equals(future.id))).getSingle();
    expect(row.title, 'Future device clock');
    expect(row.dirty, isFalse);
    expect(row.updatedAt, _fixed('2026-08-18T10:05:00.000Z'));
  });

  test(
    'overlap pull does not miss rows sharing previous cursor timestamp',
    () async {
      gateway.seedRemote(
        'task_reminders',
        _remoteReminderRow(
          id: 'remote-1',
          title: 'First remote',
          updatedAt: '2026-08-18T10:00:00.000Z',
        ),
      );
      await engine().pull();
      gateway.seedRemote(
        'task_reminders',
        _remoteReminderRow(
          id: 'remote-2',
          title: 'Same timestamp remote',
          updatedAt: '2026-08-18T10:00:00.000Z',
        ),
      );

      await engine().pull();

      final List<TaskReminderRow> rows = await db
          .select(db.taskReminders)
          .get();
      expect(rows.map((TaskReminderRow row) => row.id), contains('remote-2'));
    },
  );

  test('owner-scoped flush never pushes another user row', () async {
    await TaskRemindersRepositoryImpl(
      db: db,
      emitter: EventEmitter(DriftEventsRepository(db), IdGenerator()),
      idGenerator: IdGenerator(),
      userId: 'u2',
    ).create(
      TaskReminderDraft(
        title: 'u2 row',
        source: TaskReminderSource.manual,
        confidence: 1,
        triggerType: TaskReminderTriggerType.time,
        scheduledAt: DateTime.utc(2026, 8, 18, 12),
      ),
    );

    await engine().flush();

    final bool pushedU2 = gateway.pushes
        .where((PushCall p) => p.table == 'task_reminders')
        .expand((PushCall p) => p.rows)
        .any((Map<String, Object?> row) => row['user_id'] == 'u2');
    expect(pushedU2, isFalse);
  });

  test('event inserts remain idempotent and insert-only', () async {
    final reminder = await remindersRepo().create(
      TaskReminderDraft(
        title: 'Reminder',
        source: TaskReminderSource.manual,
        confidence: 1,
        triggerType: TaskReminderTriggerType.time,
        scheduledAt: DateTime.utc(2026, 8, 18, 12),
      ),
    );
    final events = ReminderEventsRepositoryImpl(
      db: db,
      emitter: EventEmitter(DriftEventsRepository(db), IdGenerator()),
      idGenerator: IdGenerator(),
      userId: 'u1',
    );
    await events.append(
      id: 'event-1',
      reminderId: reminder.id,
      eventType: ReminderEventType.fired,
    );
    await events.append(
      id: 'event-1',
      reminderId: reminder.id,
      eventType: ReminderEventType.fired,
    );

    await DriftEventsRepository(db).append(
      DomainEvent(
        id: 'domain-event-1',
        userId: 'u1',
        eventType: 'capture_created',
        occurredAt: DateTime.utc(2026, 8, 18),
      ),
    );

    await engine().flush();

    expect(await db.select(db.reminderEvents).get(), hasLength(1));
    expect(
      gateway.pushes
          .firstWhere((PushCall p) => p.table == 'reminder_events')
          .insertOnly,
      isTrue,
    );
    expect(
      gateway.pushes.firstWhere((PushCall p) => p.table == 'events').insertOnly,
      isTrue,
    );
  });
}

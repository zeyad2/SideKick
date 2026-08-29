import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/db/app_database.dart';

/// `wipeAllData` backs sign-out on a device shared across accounts: every local
/// table — synced rows AND the `sync_meta` pull cursor — must be cleared so the
/// next account starts blank and re-pulls, inheriting neither rows nor a stale
/// cursor.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('wipeAllData clears every table including the pull cursor', () async {
    // A synced row for the outgoing user.
    await db
        .into(db.taskReminders)
        .insert(
          TaskRemindersCompanion.insert(
            id: 'reminder-1',
            userId: 'u1',
            title: 'Leftover',
            source: 'typed',
            triggerType: 'time',
            scheduledAt: Value<DateTime>(DateTime.utc(2026, 8, 18, 12)),
          ),
        );
    // An event (insert-only table) and a pull cursor.
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            id: 'event-1',
            userId: 'u1',
            eventType: 'task_reminder_created',
          ),
        );
    await db
        .into(db.syncMeta)
        .insert(
          SyncMetaCompanion.insert(
            syncTable: 'task_reminders',
            lastPull: Value<DateTime>(DateTime.utc(2026, 8, 18, 10)),
          ),
        );

    await db.wipeAllData();

    expect(await db.select(db.taskReminders).get(), isEmpty);
    expect(await db.select(db.events).get(), isEmpty);
    expect(
      await db.select(db.syncMeta).get(),
      isEmpty,
      reason: 'the stale pull cursor must be cleared too',
    );
  });
}

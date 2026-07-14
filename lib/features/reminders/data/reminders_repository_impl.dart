import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/db/json_codec.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/features/reminders/domain/reminder.dart';

class RemindersRepositoryImpl extends LocalFirstRepository
    implements RemindersRepository {
  RemindersRepositoryImpl({
    required super.db,
    required super.emitter,
    required super.idGenerator,
    required super.userId,
    super.clock,
  });

  @override
  Stream<List<Reminder>> watchAll() =>
      (db.select(db.reminders)
            ..where(
              (Reminders r) => r.userId.equals(userId) & r.deletedAt.isNull(),
            )
            ..orderBy(<OrderClauseGenerator<Reminders>>[
              (Reminders r) => OrderingTerm.desc(r.createdAt),
            ]))
          .watch()
          .map(
            (List<ReminderRow> rows) =>
                rows.map(_toDomain).toList(growable: false),
          );

  @override
  Future<Reminder> createTimeReminder({
    required DateTime scheduledAt,
    String? taskId,
    String? habitId,
    Map<String, Object?>? recurrence,
    String? copy,
  }) => _create(
    reminderType: ReminderType.time,
    scheduledAt: scheduledAt,
    taskId: taskId,
    habitId: habitId,
    recurrence: recurrence,
    copy: copy,
  );

  @override
  Future<Reminder> createGeofenceReminder({
    required String placeId,
    required GeofenceTransition transition,
    String? taskId,
    String? habitId,
    int dwellSeconds = 60,
    String? copy,
  }) => _create(
    reminderType: ReminderType.geofence,
    placeId: placeId,
    geofenceTransition: transition,
    dwellSeconds: dwellSeconds,
    taskId: taskId,
    habitId: habitId,
    copy: copy,
  );

  Future<Reminder> _create({
    required ReminderType reminderType,
    DateTime? scheduledAt,
    Map<String, Object?>? recurrence,
    String? placeId,
    GeofenceTransition? geofenceTransition,
    int? dwellSeconds,
    String? taskId,
    String? habitId,
    String? copy,
  }) async {
    final DateTime timestamp = now();
    final String id = newId();
    await db
        .into(db.reminders)
        .insert(
          RemindersCompanion.insert(
            id: id,
            userId: userId,
            reminderType: reminderType.wire,
            scheduledAt: Value<DateTime?>(scheduledAt),
            recurrence: Value<String?>(
              recurrence == null ? null : JsonCodecs.encode(recurrence),
            ),
            placeId: Value<String?>(placeId),
            geofenceTransition: Value<String?>(geofenceTransition?.wire),
            dwellSeconds: Value<int?>(dwellSeconds),
            taskId: Value<String?>(taskId),
            habitId: Value<String?>(habitId),
            copy: Value<String?>(copy),
            status: Value<String>(ReminderStatus.scheduled.wire),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    emitter.emitCreated(
      userId: userId,
      entityType: EntityTypes.reminder,
      entityId: id,
      metadata: <String, Object?>{'reminder_type': reminderType.wire},
    );
    return (await _byId(id))!;
  }

  @override
  Future<void> update(Reminder reminder) async {
    final Reminder? existing = await _byId(reminder.id);
    if (existing == null) {
      return;
    }
    final DateTime timestamp = now();
    await (db.update(db.reminders)..where(
          (Reminders r) =>
              r.id.equals(reminder.id) & r.userId.equals(userId),
        ))
        .write(
          RemindersCompanion(
            scheduledAt: Value<DateTime?>(reminder.scheduledAt),
            recurrence: Value<String?>(
              reminder.recurrence == null
                  ? null
                  : JsonCodecs.encode(reminder.recurrence),
            ),
            snoozeUntil: Value<DateTime?>(reminder.snoozeUntil),
            geofenceTransition: Value<String?>(
              reminder.geofenceTransition?.wire,
            ),
            dwellSeconds: Value<int?>(reminder.dwellSeconds),
            copy: Value<String?>(reminder.copy),
            status: Value<String>(reminder.status.wire),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    if (existing.status != reminder.status) {
      emitter.emitStatusChanged(
        userId: userId,
        entityType: EntityTypes.reminder,
        entityId: reminder.id,
        from: existing.status.wire,
        to: reminder.status.wire,
      );
    }
  }

  @override
  Future<void> delete(String id) async {
    final DateTime timestamp = now();
    await (db.update(db.reminders)
          ..where((Reminders r) => r.id.equals(id) & r.userId.equals(userId)))
        .write(
          RemindersCompanion(
            deletedAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
  }

  Future<Reminder?> _byId(String id) async {
    final ReminderRow? row = await (db.select(db.reminders)
          ..where((Reminders r) => r.id.equals(id) & r.userId.equals(userId)))
        .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Reminder _toDomain(ReminderRow row) => Reminder(
    id: row.id,
    userId: row.userId,
    reminderType: ReminderType.fromWire(row.reminderType),
    taskId: row.taskId,
    habitId: row.habitId,
    scheduledAt: row.scheduledAt,
    recurrence: JsonCodecs.decodeNullableMap(row.recurrence),
    snoozeUntil: row.snoozeUntil,
    placeId: row.placeId,
    geofenceTransition: GeofenceTransition.fromWire(row.geofenceTransition),
    dwellSeconds: row.dwellSeconds,
    copy: row.copy,
    status: ReminderStatus.fromWire(row.status),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

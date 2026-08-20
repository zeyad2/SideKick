import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/db/json_codec.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

class TaskRemindersRepositoryImpl extends LocalFirstRepository
    implements TaskRemindersRepository {
  TaskRemindersRepositoryImpl({
    required super.db,
    required super.emitter,
    required super.idGenerator,
    required super.userId,
    super.clock,
  });

  @override
  Stream<List<TaskReminder>> watchAll() =>
      (db.select(db.taskReminders)
            ..where(
              (TaskReminders t) =>
                  t.userId.equals(userId) & t.deletedAt.isNull(),
            )
            ..orderBy(<OrderClauseGenerator<TaskReminders>>[
              (TaskReminders t) => OrderingTerm.desc(t.createdAt),
            ]))
          .watch()
          .map(_mapRows);

  @override
  Stream<List<TaskReminder>> watchByStatus(TaskReminderStatus status) =>
      (db.select(db.taskReminders)
            ..where(
              (TaskReminders t) =>
                  t.userId.equals(userId) &
                  t.deletedAt.isNull() &
                  t.status.equals(status.wire),
            )
            ..orderBy(<OrderClauseGenerator<TaskReminders>>[
              (TaskReminders t) => OrderingTerm.desc(t.createdAt),
            ]))
          .watch()
          .map(_mapRows);

  @override
  Future<TaskReminder> create(TaskReminderDraft draft) async {
    final DateTime timestamp = now();
    final String id = newId();
    await db
        .into(db.taskReminders)
        .insert(
          TaskRemindersCompanion.insert(
            id: id,
            userId: userId,
            title: draft.title,
            details: Value<String?>(draft.details),
            status: Value<String>(draft.status.wire),
            source: draft.source.wire,
            confidence: Value<double>(draft.confidence),
            triggerType: draft.triggerType.wire,
            scheduledAt: Value<DateTime?>(draft.scheduledAt),
            placeId: Value<String?>(draft.placeId),
            geofenceTransition: Value<String?>(
              draft.geofenceTransition?.wire,
            ),
            dwellSeconds: Value<int?>(draft.dwellSeconds),
            autoCommitDeadlineAt: Value<DateTime?>(
              draft.autoCommitDeadlineAt,
            ),
            captureId: Value<String?>(draft.captureId),
            aiExplanation: Value<String?>(draft.aiExplanation),
            aiContext: Value<String?>(
              draft.aiContext == null ? null : JsonCodecs.encode(draft.aiContext),
            ),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    emitter.emitCreated(
      userId: userId,
      entityType: EntityTypes.taskReminder,
      entityId: id,
      metadata: <String, Object?>{'source': draft.source.wire},
    );
    return (await _byId(id))!;
  }

  @override
  Future<void> update(TaskReminder reminder) async {
    final TaskReminder? existing = await _byId(reminder.id);
    if (existing == null) return;
    final DateTime timestamp = now();
    await (db.update(db.taskReminders)..where(
          (TaskReminders t) =>
              t.id.equals(reminder.id) & t.userId.equals(userId),
        ))
        .write(
          TaskRemindersCompanion(
            title: Value<String>(reminder.title),
            details: Value<String?>(reminder.details),
            status: Value<String>(reminder.status.wire),
            source: Value<String>(reminder.source.wire),
            confidence: Value<double>(reminder.confidence),
            triggerType: Value<String>(reminder.triggerType.wire),
            scheduledAt: Value<DateTime?>(reminder.scheduledAt),
            placeId: Value<String?>(reminder.placeId),
            geofenceTransition: Value<String?>(
              reminder.geofenceTransition?.wire,
            ),
            dwellSeconds: Value<int?>(reminder.dwellSeconds),
            autoCommitDeadlineAt: Value<DateTime?>(
              reminder.autoCommitDeadlineAt,
            ),
            captureId: Value<String?>(reminder.captureId),
            aiExplanation: Value<String?>(reminder.aiExplanation),
            aiContext: Value<String?>(
              reminder.aiContext == null
                  ? null
                  : JsonCodecs.encode(reminder.aiContext),
            ),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    if (existing.status != reminder.status) {
      emitter.emitStatusChanged(
        userId: userId,
        entityType: EntityTypes.taskReminder,
        entityId: reminder.id,
        from: existing.status.wire,
        to: reminder.status.wire,
      );
    }
  }

  @override
  Future<void> delete(String id) async {
    final DateTime timestamp = now();
    await (db.update(db.taskReminders)..where(
          (TaskReminders t) => t.id.equals(id) & t.userId.equals(userId),
        ))
        .write(
          TaskRemindersCompanion(
            deletedAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
  }

  Future<TaskReminder?> _byId(String id) async {
    final TaskReminderRow? row =
        await (db.select(db.taskReminders)..where(
              (TaskReminders t) => t.id.equals(id) & t.userId.equals(userId),
            ))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  List<TaskReminder> _mapRows(List<TaskReminderRow> rows) =>
      rows.map(_toDomain).toList(growable: false);

  TaskReminder _toDomain(TaskReminderRow row) => TaskReminder(
    id: row.id,
    userId: row.userId,
    title: row.title,
    details: row.details,
    status: TaskReminderStatus.fromWire(row.status),
    source: TaskReminderSource.fromWire(row.source),
    confidence: row.confidence,
    triggerType: TaskReminderTriggerType.fromWire(row.triggerType),
    scheduledAt: row.scheduledAt,
    placeId: row.placeId,
    geofenceTransition: GeofenceTransition.fromWire(row.geofenceTransition),
    dwellSeconds: row.dwellSeconds,
    autoCommitDeadlineAt: row.autoCommitDeadlineAt,
    captureId: row.captureId,
    aiExplanation: row.aiExplanation,
    aiContext: JsonCodecs.decodeNullableMap(row.aiContext),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

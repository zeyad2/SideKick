import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/features/tasks/domain/task.dart';

class TasksRepositoryImpl extends LocalFirstRepository
    implements TasksRepository {
  TasksRepositoryImpl({
    required super.db,
    required super.emitter,
    required super.idGenerator,
    required super.userId,
    super.clock,
  });

  @override
  Stream<List<Task>> watchAll() => _query(null).watch().map(_mapRows);

  @override
  Stream<List<Task>> watchByStatus(TaskStatus status) =>
      _query(status).watch().map(_mapRows);

  SimpleSelectStatement<$TasksTable, TaskRow> _query(TaskStatus? status) {
    final select = db.select(db.tasks)
      ..where((Tasks t) => t.userId.equals(userId) & t.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<Tasks>>[
        (Tasks t) => OrderingTerm.desc(t.createdAt),
      ]);
    if (status != null) {
      select.where((Tasks t) => t.status.equals(status.wire));
    }
    return select;
  }

  @override
  Future<Task> create({
    required String title,
    String? details,
    String? captureId,
    String? goalId,
    DateTime? scheduledAt,
  }) async {
    final DateTime timestamp = now();
    final String id = newId();
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            userId: userId,
            title: title,
            details: Value<String?>(details),
            captureId: Value<String?>(captureId),
            goalId: Value<String?>(goalId),
            scheduledAt: Value<DateTime?>(scheduledAt),
            status: Value<String>(TaskStatus.todo.wire),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            lastActivityAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    emitter.emitCreated(
      userId: userId,
      entityType: EntityTypes.task,
      entityId: id,
    );
    return (await _byId(id))!;
  }

  @override
  Future<void> update(Task task) async {
    final Task? existing = await _byId(task.id);
    if (existing == null) {
      return;
    }
    final DateTime timestamp = now();
    await (db.update(db.tasks)..where(
          (Tasks t) => t.id.equals(task.id) & t.userId.equals(userId),
        ))
        .write(
          TasksCompanion(
            goalId: Value<String?>(task.goalId),
            title: Value<String>(task.title),
            details: Value<String?>(task.details),
            status: Value<String>(task.status.wire),
            nextAction: Value<String?>(task.nextAction),
            scheduledAt: Value<DateTime?>(task.scheduledAt),
            completedAt: Value<DateTime?>(task.completedAt),
            lastActivityAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    if (existing.status != task.status) {
      emitter.emitStatusChanged(
        userId: userId,
        entityType: EntityTypes.task,
        entityId: task.id,
        from: existing.status.wire,
        to: task.status.wire,
      );
    }
  }

  @override
  Future<void> delete(String id) async {
    final DateTime timestamp = now();
    await (db.update(db.tasks)
          ..where((Tasks t) => t.id.equals(id) & t.userId.equals(userId)))
        .write(
          TasksCompanion(
            deletedAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
  }

  Future<Task?> _byId(String id) async {
    final TaskRow? row = await (db.select(db.tasks)
          ..where((Tasks t) => t.id.equals(id) & t.userId.equals(userId)))
        .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  List<Task> _mapRows(List<TaskRow> rows) =>
      rows.map(_toDomain).toList(growable: false);

  Task _toDomain(TaskRow row) => Task(
    id: row.id,
    userId: row.userId,
    captureId: row.captureId,
    goalId: row.goalId,
    title: row.title,
    details: row.details,
    status: TaskStatus.fromWire(row.status),
    nextAction: row.nextAction,
    scheduledAt: row.scheduledAt,
    completedAt: row.completedAt,
    lastActivityAt: row.lastActivityAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

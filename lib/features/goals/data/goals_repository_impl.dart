import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/features/goals/domain/goal.dart';

class GoalsRepositoryImpl extends LocalFirstRepository
    implements GoalsRepository {
  GoalsRepositoryImpl({
    required super.db,
    required super.emitter,
    required super.idGenerator,
    required super.userId,
    super.clock,
  });

  @override
  Stream<List<Goal>> watchAll() => _query(null).watch().map(_mapRows);

  @override
  Stream<List<Goal>> watchByStatus(GoalStatus status) =>
      _query(status).watch().map(_mapRows);

  SimpleSelectStatement<$GoalsTable, GoalRow> _query(GoalStatus? status) {
    final select = db.select(db.goals)
      ..where((Goals g) => g.userId.equals(userId) & g.deletedAt.isNull())
      ..orderBy(<OrderClauseGenerator<Goals>>[
        (Goals g) => OrderingTerm.desc(g.createdAt),
      ]);
    if (status != null) {
      select.where((Goals g) => g.status.equals(status.wire));
    }
    return select;
  }

  @override
  Future<Goal> create({
    required String title,
    String? why,
    DateTime? targetDate,
  }) async {
    final DateTime timestamp = now();
    final String id = newId();
    await db
        .into(db.goals)
        .insert(
          GoalsCompanion.insert(
            id: id,
            userId: userId,
            title: title,
            why: Value<String?>(why),
            status: Value<String>(GoalStatus.active.wire),
            targetDate: Value<DateTime?>(targetDate),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    emitter.emitCreated(
      userId: userId,
      entityType: EntityTypes.goal,
      entityId: id,
    );
    final GoalRow row = await (db.select(db.goals)
          ..where((Goals g) => g.id.equals(id)))
        .getSingle();
    return _toDomain(row);
  }

  @override
  Future<void> update(Goal goal) async {
    final GoalRow? existing = await (db.select(db.goals)
          ..where((Goals g) => g.id.equals(goal.id) & g.userId.equals(userId)))
        .getSingleOrNull();
    if (existing == null) {
      return;
    }
    final DateTime timestamp = now();
    await (db.update(db.goals)..where(
          (Goals g) => g.id.equals(goal.id) & g.userId.equals(userId),
        ))
        .write(
          GoalsCompanion(
            title: Value<String>(goal.title),
            why: Value<String?>(goal.why),
            status: Value<String>(goal.status.wire),
            targetDate: Value<DateTime?>(goal.targetDate),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    if (existing.status != goal.status.wire) {
      emitter.emitStatusChanged(
        userId: userId,
        entityType: EntityTypes.goal,
        entityId: goal.id,
        from: existing.status,
        to: goal.status.wire,
      );
    }
  }

  @override
  Future<void> delete(String id) async {
    final DateTime timestamp = now();
    await (db.update(db.goals)
          ..where((Goals g) => g.id.equals(id) & g.userId.equals(userId)))
        .write(
          GoalsCompanion(
            deletedAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
  }

  List<Goal> _mapRows(List<GoalRow> rows) =>
      rows.map(_toDomain).toList(growable: false);

  Goal _toDomain(GoalRow row) => Goal(
    id: row.id,
    userId: row.userId,
    title: row.title,
    why: row.why,
    status: GoalStatus.fromWire(row.status),
    targetDate: row.targetDate,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

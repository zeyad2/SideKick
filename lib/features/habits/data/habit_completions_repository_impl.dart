import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/features/habits/domain/habit_completion.dart';

class HabitCompletionsRepositoryImpl extends LocalFirstRepository
    implements HabitCompletionsRepository {
  HabitCompletionsRepositoryImpl({
    required super.db,
    required super.emitter,
    required super.idGenerator,
    required super.userId,
    super.clock,
  });

  @override
  Stream<List<HabitCompletion>> watchAll() => _query(null).watch().map(_mapRows);

  @override
  Stream<List<HabitCompletion>> watchByHabit(String habitId) =>
      _query(habitId).watch().map(_mapRows);

  SimpleSelectStatement<$HabitCompletionsTable, HabitCompletionRow> _query(
    String? habitId,
  ) {
    final select = db.select(db.habitCompletions)
      ..where(
        (HabitCompletions c) =>
            c.userId.equals(userId) & c.deletedAt.isNull(),
      )
      ..orderBy(<OrderClauseGenerator<HabitCompletions>>[
        (HabitCompletions c) => OrderingTerm.desc(c.completedAt),
      ]);
    if (habitId != null) {
      select.where((HabitCompletions c) => c.habitId.equals(habitId));
    }
    return select;
  }

  @override
  Future<HabitCompletion> create({
    required String habitId,
    required HabitLevel level,
    EnergyMode? energyMode,
    DateTime? completedAt,
  }) async {
    final DateTime timestamp = now();
    final String id = newId();
    await db
        .into(db.habitCompletions)
        .insert(
          HabitCompletionsCompanion.insert(
            id: id,
            userId: userId,
            habitId: habitId,
            level: level.wire,
            energyMode: Value<String?>(energyMode?.wire),
            completedAt: Value<DateTime>(completedAt ?? timestamp),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    emitter.emitCreated(
      userId: userId,
      entityType: EntityTypes.habitCompletion,
      entityId: id,
      metadata: <String, Object?>{
        'habit_id': habitId,
        'level': level.wire,
        if (energyMode != null) 'energy_mode': energyMode.wire,
      },
    );
    final HabitCompletionRow row = await (db.select(db.habitCompletions)
          ..where((HabitCompletions c) => c.id.equals(id)))
        .getSingle();
    return _toDomain(row);
  }

  @override
  Future<void> delete(String id) async {
    final DateTime timestamp = now();
    await (db.update(db.habitCompletions)..where(
          (HabitCompletions c) =>
              c.id.equals(id) & c.userId.equals(userId),
        ))
        .write(
          HabitCompletionsCompanion(
            deletedAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
  }

  List<HabitCompletion> _mapRows(List<HabitCompletionRow> rows) =>
      rows.map(_toDomain).toList(growable: false);

  HabitCompletion _toDomain(HabitCompletionRow row) => HabitCompletion(
    id: row.id,
    userId: row.userId,
    habitId: row.habitId,
    level: HabitLevel.fromWire(row.level),
    energyMode: EnergyMode.fromWire(row.energyMode),
    completedAt: row.completedAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

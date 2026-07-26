import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/db/json_codec.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/features/habits/domain/habit.dart';

class HabitsRepositoryImpl extends LocalFirstRepository
    implements HabitsRepository, CaptureLinkedHabitsRepository {
  HabitsRepositoryImpl({
    required super.db,
    required super.emitter,
    required super.idGenerator,
    required super.userId,
    super.clock,
  });

  @override
  Stream<List<Habit>> watchAll() =>
      (db.select(db.habits)
            ..where(
              (Habits h) => h.userId.equals(userId) & h.deletedAt.isNull(),
            )
            ..orderBy(<OrderClauseGenerator<Habits>>[
              (Habits h) => OrderingTerm.desc(h.createdAt),
            ]))
          .watch()
          .map(
            (List<HabitRow> rows) =>
                rows.map(_toDomain).toList(growable: false),
          );

  @override
  Future<Habit> create({
    required String title,
    Map<String, Object?>? frequencyConfig,
    Map<String, Object?>? levelConfig,
    String? anchorDescription,
    String? captureId,
    String? goalId,
  }) async {
    return _createWithId(
      id: newId(),
      title: title,
      frequencyConfig: frequencyConfig,
      levelConfig: levelConfig,
      anchorDescription: anchorDescription,
      captureId: captureId,
      goalId: goalId,
    );
  }

  @override
  Future<Habit> createForCapture({
    required String captureId,
    required String title,
    String? id,
    Map<String, Object?>? levelConfig,
    String? anchorDescription,
    Map<String, Object?>? frequencyConfig,
  }) => _createWithId(
    id: id ?? captureId,
    title: title,
    levelConfig: levelConfig,
    anchorDescription: anchorDescription,
    frequencyConfig: frequencyConfig,
    captureId: captureId,
  );

  Future<Habit> _createWithId({
    required String id,
    required String title,
    Map<String, Object?>? frequencyConfig,
    Map<String, Object?>? levelConfig,
    String? anchorDescription,
    String? captureId,
    String? goalId,
  }) async {
    final DateTime timestamp = now();
    final HabitRow? inserted = await db
        .into(db.habits)
        .insertReturningOrNull(
          HabitsCompanion.insert(
            id: id,
            userId: userId,
            title: title,
            frequencyConfig: Value<String?>(
              frequencyConfig == null
                  ? null
                  : JsonCodecs.encode(frequencyConfig),
            ),
            levelConfig: Value<String?>(
              levelConfig == null ? null : JsonCodecs.encode(levelConfig),
            ),
            anchorDescription: Value<String?>(anchorDescription),
            captureId: Value<String?>(captureId),
            goalId: Value<String?>(goalId),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    if (inserted != null) {
      emitter.emitCreated(
        userId: userId,
        entityType: EntityTypes.habit,
        entityId: id,
      );
    }
    final HabitRow row =
        await (db.select(db.habits)
              ..where((Habits h) => h.id.equals(id) & h.userId.equals(userId)))
            .getSingle();
    return _toDomain(row);
  }

  @override
  Future<void> update(Habit habit) async {
    final DateTime timestamp = now();
    await (db.update(
          db.habits,
        )..where((Habits h) => h.id.equals(habit.id) & h.userId.equals(userId)))
        .write(
          HabitsCompanion(
            goalId: Value<String?>(habit.goalId),
            title: Value<String>(habit.title),
            frequencyConfig: Value<String?>(
              habit.frequencyConfig == null
                  ? null
                  : JsonCodecs.encode(habit.frequencyConfig),
            ),
            levelConfig: Value<String?>(
              habit.levelConfig == null
                  ? null
                  : JsonCodecs.encode(habit.levelConfig),
            ),
            anchorDescription: Value<String?>(habit.anchorDescription),
            resetActive: Value<bool>(habit.resetActive),
            resetStartedAt: Value<DateTime?>(habit.resetStartedAt),
            archived: Value<bool>(habit.archived),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
  }

  @override
  Future<void> delete(String id) async {
    final DateTime timestamp = now();
    await (db.update(
      db.habits,
    )..where((Habits h) => h.id.equals(id) & h.userId.equals(userId))).write(
      HabitsCompanion(
        deletedAt: Value<DateTime>(timestamp),
        updatedAt: Value<DateTime>(timestamp),
        dirty: const Value<bool>(true),
      ),
    );
  }

  Habit _toDomain(HabitRow row) => Habit(
    id: row.id,
    userId: row.userId,
    captureId: row.captureId,
    goalId: row.goalId,
    title: row.title,
    frequencyConfig: JsonCodecs.decodeNullableMap(row.frequencyConfig),
    levelConfig: JsonCodecs.decodeNullableMap(row.levelConfig),
    anchorDescription: row.anchorDescription,
    resetActive: row.resetActive,
    resetStartedAt: row.resetStartedAt,
    archived: row.archived,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

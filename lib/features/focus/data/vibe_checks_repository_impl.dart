import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/features/focus/domain/vibe_check.dart';

class VibeChecksRepositoryImpl extends LocalFirstRepository
    implements VibeChecksRepository {
  VibeChecksRepositoryImpl({
    required super.db,
    required super.emitter,
    required super.idGenerator,
    required super.userId,
    super.clock,
  });

  @override
  Stream<List<VibeCheck>> watchAll() =>
      (db.select(db.vibeChecks)
            ..where(
              (VibeChecks v) => v.userId.equals(userId) & v.deletedAt.isNull(),
            )
            ..orderBy(<OrderClauseGenerator<VibeChecks>>[
              (VibeChecks v) => OrderingTerm.desc(v.createdAt),
            ]))
          .watch()
          .map(
            (List<VibeCheckRow> rows) =>
                rows.map(_toDomain).toList(growable: false),
          );

  @override
  Future<VibeCheck> create({required int value, String? focusSessionId}) async {
    final DateTime timestamp = now();
    final String id = newId();
    await db
        .into(db.vibeChecks)
        .insert(
          VibeChecksCompanion.insert(
            id: id,
            userId: userId,
            value: value,
            focusSessionId: Value<String?>(focusSessionId),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    emitter.emitCreated(
      userId: userId,
      entityType: EntityTypes.vibeCheck,
      entityId: id,
      metadata: <String, Object?>{'value': value},
    );
    final VibeCheckRow row = await (db.select(db.vibeChecks)
          ..where((VibeChecks v) => v.id.equals(id)))
        .getSingle();
    return _toDomain(row);
  }

  @override
  Future<void> delete(String id) async {
    final DateTime timestamp = now();
    await (db.update(db.vibeChecks)
          ..where((VibeChecks v) => v.id.equals(id) & v.userId.equals(userId)))
        .write(
          VibeChecksCompanion(
            deletedAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
  }

  VibeCheck _toDomain(VibeCheckRow row) => VibeCheck(
    id: row.id,
    userId: row.userId,
    focusSessionId: row.focusSessionId,
    value: row.value,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

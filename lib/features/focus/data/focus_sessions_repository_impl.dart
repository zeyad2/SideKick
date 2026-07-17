import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/db/json_codec.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/features/focus/domain/focus_session.dart';

class FocusSessionsRepositoryImpl extends LocalFirstRepository
    implements FocusSessionsRepository {
  FocusSessionsRepositoryImpl({
    required super.db,
    required super.emitter,
    required super.idGenerator,
    required super.userId,
    super.clock,
  });

  @override
  Stream<List<FocusSession>> watchAll() =>
      (db.select(db.focusSessions)
            ..where(
              (FocusSessions f) =>
                  f.userId.equals(userId) & f.deletedAt.isNull(),
            )
            ..orderBy(<OrderClauseGenerator<FocusSessions>>[
              (FocusSessions f) => OrderingTerm.desc(f.startedAt),
            ]))
          .watch()
          .map(
            (List<FocusSessionRow> rows) =>
                rows.map(_toDomain).toList(growable: false),
          );

  @override
  Stream<FocusSession?> watchById(String id) =>
      (db.select(db.focusSessions)..where(
            (FocusSessions f) => f.id.equals(id) & f.userId.equals(userId),
          ))
          .watchSingleOrNull()
          .map((FocusSessionRow? row) => row == null ? null : _toDomain(row));

  @override
  Future<FocusSession> create({
    required int durationMinutes,
    String? taskId,
    String? taskLabel,
    bool blockingEnabled = false,
    BlockingMode blockingMode = BlockingMode.soft,
  }) async {
    final DateTime timestamp = now();
    final String id = newId();
    await db
        .into(db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            id: id,
            userId: userId,
            durationMinutes: durationMinutes,
            taskId: Value<String?>(taskId),
            taskLabel: Value<String?>(taskLabel),
            status: Value<String>(FocusSessionStatus.active.wire),
            blockingEnabled: Value<bool>(blockingEnabled),
            blockingMode: Value<String>(blockingMode.wire),
            startedAt: Value<DateTime>(timestamp),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    emitter.emitCreated(
      userId: userId,
      entityType: EntityTypes.focusSession,
      entityId: id,
    );
    return (await _byId(id))!;
  }

  @override
  Future<void> update(FocusSession session) async {
    final FocusSession? existing = await _byId(session.id);
    if (existing == null) {
      return;
    }
    final DateTime timestamp = now();
    await (db.update(db.focusSessions)..where(
          (FocusSessions f) =>
              f.id.equals(session.id) & f.userId.equals(userId),
        ))
        .write(
          FocusSessionsCompanion(
            taskId: Value<String?>(session.taskId),
            taskLabel: Value<String?>(session.taskLabel),
            durationMinutes: Value<int>(session.durationMinutes),
            endedAt: Value<DateTime?>(session.endedAt),
            status: Value<String>(session.status.wire),
            blockingEnabled: Value<bool>(session.blockingEnabled),
            blockingMode: Value<String>(session.blockingMode.wire),
            blockAttempts: Value<int>(session.blockAttempts),
            capturesDuring: Value<String>(
              JsonCodecs.encode(session.capturesDuring),
            ),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    if (existing.status != session.status) {
      emitter.emitStatusChanged(
        userId: userId,
        entityType: EntityTypes.focusSession,
        entityId: session.id,
        from: existing.status.wire,
        to: session.status.wire,
      );
    }
  }

  @override
  Future<void> delete(String id) async {
    final DateTime timestamp = now();
    await (db.update(db.focusSessions)..where(
          (FocusSessions f) => f.id.equals(id) & f.userId.equals(userId),
        ))
        .write(
          FocusSessionsCompanion(
            deletedAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
  }

  Future<FocusSession?> _byId(String id) async {
    final FocusSessionRow? row =
        await (db.select(db.focusSessions)..where(
              (FocusSessions f) => f.id.equals(id) & f.userId.equals(userId),
            ))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  FocusSession _toDomain(FocusSessionRow row) => FocusSession(
    id: row.id,
    userId: row.userId,
    taskId: row.taskId,
    taskLabel: row.taskLabel,
    durationMinutes: row.durationMinutes,
    startedAt: row.startedAt,
    endedAt: row.endedAt,
    status: FocusSessionStatus.fromWire(row.status),
    blockingEnabled: row.blockingEnabled,
    blockingMode: BlockingMode.fromWire(row.blockingMode),
    blockAttempts: row.blockAttempts,
    capturesDuring: JsonCodecs.decodeList(
      row.capturesDuring,
    ).cast<String>().toList(growable: false),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

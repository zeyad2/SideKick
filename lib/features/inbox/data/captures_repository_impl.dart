import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/db/json_codec.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';

class CapturesRepositoryImpl extends LocalFirstRepository
    implements CapturesRepository, CaptureReplayLookup {
  CapturesRepositoryImpl({
    required super.db,
    required super.emitter,
    required super.idGenerator,
    required super.userId,
    super.clock,
  });

  @override
  Stream<List<Capture>> watchAll() =>
      (db.select(db.captures)
            ..where(
              (Captures c) =>
                  c.userId.equals(userId) &
                  c.deletedAt.isNull() &
                  c.status.equals(CaptureStatus.discarded.wire).not(),
            )
            ..orderBy(<OrderClauseGenerator<Captures>>[
              (Captures c) => OrderingTerm.desc(c.capturedAt),
            ]))
          .watch()
          .map(_mapRows);

  @override
  Stream<List<Capture>> watchByStatuses(Set<CaptureStatus> statuses) {
    final List<String> wires = statuses
        .map((CaptureStatus s) => s.wire)
        .toList(growable: false);
    return (db.select(db.captures)
          ..where(
            (Captures c) =>
                c.userId.equals(userId) &
                c.deletedAt.isNull() &
                c.status.isIn(wires),
          )
          ..orderBy(<OrderClauseGenerator<Captures>>[
            (Captures c) => OrderingTerm.desc(c.capturedAt),
          ]))
        .watch()
        .map(_mapRows);
  }

  @override
  Future<List<Capture>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return const <Capture>[];
    final List<CaptureRow> rows = await (db.select(
      db.captures,
    )..where((Captures c) => c.userId.equals(userId) & c.id.isIn(ids))).get();
    return _mapRows(rows);
  }

  @override
  Future<Capture?> findByAudioPath(String audioPath) async {
    final CaptureRow? row =
        await (db.select(db.captures)..where(
              (Captures c) =>
                  c.userId.equals(userId) &
                  c.deletedAt.isNull() &
                  c.audioPath.equals(audioPath),
            ))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<Capture> create({
    String? inputText,
    String? audioPath,
    DateTime? capturedAt,
    String source = 'audio',
  }) async {
    final DateTime timestamp = now();
    final String id = newId();
    final CaptureSource captureSource = CaptureSource.fromWire(source);
    await db
        .into(db.captures)
        .insert(
          CapturesCompanion.insert(
            id: id,
            userId: userId,
            source: captureSource.wire,
            inputText: Value<String?>(inputText),
            audioPath: Value<String?>(audioPath),
            status: Value<String>(CaptureStatus.pending.wire),
            capturedAt: Value<DateTime>(capturedAt ?? timestamp),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    emitter.emitCreated(
      userId: userId,
      entityType: EntityTypes.capture,
      entityId: id,
      metadata: <String, Object?>{'source': captureSource.wire},
    );
    return (await _byId(id))!;
  }

  @override
  Future<void> update(Capture capture) async {
    final Capture? existing = await _byId(capture.id);
    if (existing == null) return;
    final DateTime timestamp = now();
    await (db.update(db.captures)..where(
          (Captures c) => c.id.equals(capture.id) & c.userId.equals(userId),
        ))
        .write(
          CapturesCompanion(
            source: Value<String>(capture.source.wire),
            inputText: Value<String?>(capture.inputText),
            audioPath: Value<String?>(capture.audioPath),
            rawTranscript: Value<String?>(capture.rawTranscript),
            status: Value<String>(capture.status.wire),
            error: Value<String?>(capture.error),
            metadata: Value<String>(JsonCodecs.encode(capture.metadata)),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    if (existing.status != capture.status) {
      emitter.emitStatusChanged(
        userId: userId,
        entityType: EntityTypes.capture,
        entityId: capture.id,
        from: existing.status.wire,
        to: capture.status.wire,
      );
    }
  }

  @override
  Future<void> delete(String id) async {
    final DateTime timestamp = now();
    await (db.update(
      db.captures,
    )..where((Captures c) => c.id.equals(id) & c.userId.equals(userId))).write(
      CapturesCompanion(
        deletedAt: Value<DateTime>(timestamp),
        updatedAt: Value<DateTime>(timestamp),
        dirty: const Value<bool>(true),
      ),
    );
  }

  Future<Capture?> _byId(String id) async {
    final CaptureRow? row =
        await (db.select(
              db.captures,
            )..where((Captures c) => c.id.equals(id) & c.userId.equals(userId)))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  List<Capture> _mapRows(List<CaptureRow> rows) =>
      rows.map(_toDomain).toList(growable: false);

  Capture _toDomain(CaptureRow row) => Capture(
    id: row.id,
    userId: row.userId,
    source: CaptureSource.fromWire(row.source),
    inputText: row.inputText,
    audioPath: row.audioPath,
    rawTranscript: row.rawTranscript,
    status: CaptureStatus.fromWire(row.status),
    error: row.error,
    metadata: JsonCodecs.decodeMap(row.metadata),
    capturedAt: row.capturedAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

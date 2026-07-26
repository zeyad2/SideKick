import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/db/json_codec.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/inbox/domain/proposed_item.dart';

class CapturesRepositoryImpl extends LocalFirstRepository
    implements
        CapturesRepository,
        CaptureReplayLookup,
        CaptureProcessingTransitions {
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
    if (ids.isEmpty) {
      return const <Capture>[];
    }
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
  Future<Capture?> beginProcessing(String captureId) async {
    final Capture? existing = await _byId(captureId);
    if (existing == null ||
        (existing.status != CaptureStatus.pending &&
            existing.status != CaptureStatus.failed &&
            existing.status != CaptureStatus.processing)) {
      return null;
    }
    final DateTime timestamp = now();
    final int changed =
        await (db.update(db.captures)..where(
              (Captures c) =>
                  c.id.equals(captureId) &
                  c.userId.equals(userId) &
                  c.status.equals(existing.status.wire),
            ))
            .write(
              CapturesCompanion(
                status: Value<String>(CaptureStatus.processing.wire),
                updatedAt: Value<DateTime>(timestamp),
                dirty: const Value<bool>(true),
              ),
            );
    if (changed == 0) return null;
    if (existing.status != CaptureStatus.processing) {
      emitter.emitStatusChanged(
        userId: userId,
        entityType: EntityTypes.capture,
        entityId: captureId,
        from: existing.status.wire,
        to: CaptureStatus.processing.wire,
      );
    }
    return _byId(captureId);
  }

  @override
  Future<bool> finishProcessing(Capture capture) async {
    if (capture.status != CaptureStatus.ready &&
        capture.status != CaptureStatus.failed) {
      throw ArgumentError.value(
        capture.status,
        'capture.status',
        'must be ready or failed',
      );
    }
    final DateTime timestamp = now();
    final int changed =
        await (db.update(db.captures)..where(
              (Captures c) =>
                  c.id.equals(capture.id) &
                  c.userId.equals(userId) &
                  c.status.equals(CaptureStatus.processing.wire),
            ))
            .write(
              CapturesCompanion(
                audioPath: Value<String?>(capture.audioPath),
                rawTranscript: Value<String?>(capture.rawTranscript),
                llmType: Value<String>(capture.llmType.wire),
                title: Value<String?>(capture.title),
                details: Value<String?>(capture.details),
                suggestedSchedule: Value<String?>(
                  capture.suggestedSchedule == null
                      ? null
                      : JsonCodecs.encode(capture.suggestedSchedule),
                ),
                status: Value<String>(capture.status.wire),
                resultingType: Value<String?>(capture.resultingType?.wire),
                resultingId: Value<String?>(capture.resultingId),
                proposedItems: Value<String?>(
                  _encodeProposedItems(capture.proposedItems),
                ),
                dispositionedItemIds: Value<String>(
                  JsonCodecs.encode(capture.dispositionedItemIds),
                ),
                autoCommittedAt: Value<DateTime?>(capture.autoCommittedAt),
                updatedAt: Value<DateTime>(timestamp),
                dirty: const Value<bool>(true),
              ),
            );
    if (changed == 0) return false;
    emitter.emitStatusChanged(
      userId: userId,
      entityType: EntityTypes.capture,
      entityId: capture.id,
      from: CaptureStatus.processing.wire,
      to: capture.status.wire,
    );
    return true;
  }

  @override
  Future<Capture> create({
    String? audioPath,
    DateTime? capturedAt,
    String source = 'trigger',
  }) async {
    final DateTime timestamp = now();
    final String id = newId();
    await db
        .into(db.captures)
        .insert(
          CapturesCompanion.insert(
            id: id,
            userId: userId,
            audioPath: Value<String?>(audioPath),
            status: Value<String>(CaptureStatus.pending.wire),
            llmType: Value<String>(LlmType.uncategorized.wire),
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
      metadata: <String, Object?>{'source': source},
    );
    return (await _byId(id))!;
  }

  @override
  Future<void> update(Capture capture) async {
    final Capture? existing = await _byId(capture.id);
    if (existing == null) {
      return;
    }
    final DateTime timestamp = now();
    await (db.update(db.captures)..where(
          (Captures c) => c.id.equals(capture.id) & c.userId.equals(userId),
        ))
        .write(
          CapturesCompanion(
            audioPath: Value<String?>(capture.audioPath),
            rawTranscript: Value<String?>(capture.rawTranscript),
            llmType: Value<String>(capture.llmType.wire),
            title: Value<String?>(capture.title),
            details: Value<String?>(capture.details),
            suggestedSchedule: Value<String?>(
              capture.suggestedSchedule == null
                  ? null
                  : JsonCodecs.encode(capture.suggestedSchedule),
            ),
            status: Value<String>(capture.status.wire),
            resultingType: Value<String?>(capture.resultingType?.wire),
            resultingId: Value<String?>(capture.resultingId),
            proposedItems: Value<String?>(
              _encodeProposedItems(capture.proposedItems),
            ),
            dispositionedItemIds: Value<String>(
              JsonCodecs.encode(capture.dispositionedItemIds),
            ),
            autoCommittedAt: Value<DateTime?>(capture.autoCommittedAt),
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
    audioPath: row.audioPath,
    rawTranscript: row.rawTranscript,
    llmType: LlmType.fromWire(row.llmType),
    title: row.title,
    details: row.details,
    suggestedSchedule: JsonCodecs.decodeNullableMap(row.suggestedSchedule),
    status: CaptureStatus.fromWire(row.status),
    resultingType: ResultingType.fromWire(row.resultingType),
    resultingId: row.resultingId,
    proposedItems: _decodeProposedItems(row.proposedItems),
    dispositionedItemIds: JsonCodecs.decodeList(
      row.dispositionedItemIds,
    ).cast<String>(),
    autoCommittedAt: row.autoCommittedAt,
    capturedAt: row.capturedAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  static String? _encodeProposedItems(List<ProposedItem>? items) =>
      items == null
      ? null
      : JsonCodecs.encode(
          items.map((ProposedItem i) => i.toJson()).toList(growable: false),
        );

  static List<ProposedItem>? _decodeProposedItems(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return JsonCodecs.decodeList(
      raw,
    ).map<ProposedItem>(ProposedItem.fromStored).toList(growable: false);
  }
}

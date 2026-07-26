import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/features/inbox/domain/proposed_item.dart';

/// A raw brain-dump event (audio + transcript) awaiting triage. Immutable
/// inbox event; triaged INTO a typed record (task/note/habit). See SCHEMA.md.
@immutable
class Capture {
  const Capture({
    required this.id,
    required this.userId,
    required this.llmType,
    required this.status,
    required this.capturedAt,
    required this.createdAt,
    required this.updatedAt,
    this.audioPath,
    this.rawTranscript,
    this.title,
    this.details,
    this.suggestedSchedule,
    this.resultingType,
    this.resultingId,
    this.proposedItems,
    this.dispositionedItemIds = const <String>[],
    this.autoCommittedAt,
  });

  final String id;
  final String userId;
  final String? audioPath;
  final String? rawTranscript;
  final LlmType llmType;
  final String? title;
  final String? details;
  final Map<String, Object?>? suggestedSchedule;
  final CaptureStatus status;
  final ResultingType? resultingType;
  final String? resultingId;

  /// Ordered draft items decomposed from the rant (§4). `null` until the P4
  /// worker has run; an empty list never occurs (empty extraction falls back to
  /// a single `note` draft, §11).
  final List<ProposedItem>? proposedItems;

  /// Stable draft ids already saved or dropped. Remaining ids re-enter review.
  final List<String> dispositionedItemIds;

  /// Non-null only for captures materialized by the automatic gate.
  final DateTime? autoCommittedAt;
  final DateTime capturedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Capture copyWith({
    String? audioPath,
    String? rawTranscript,
    LlmType? llmType,
    String? title,
    String? details,
    Map<String, Object?>? suggestedSchedule,
    CaptureStatus? status,
    ResultingType? resultingType,
    String? resultingId,
    List<ProposedItem>? proposedItems,
    List<String>? dispositionedItemIds,
    DateTime? autoCommittedAt,
    bool clearAutoCommittedAt = false,
  }) => Capture(
    id: id,
    userId: userId,
    audioPath: audioPath ?? this.audioPath,
    rawTranscript: rawTranscript ?? this.rawTranscript,
    llmType: llmType ?? this.llmType,
    title: title ?? this.title,
    details: details ?? this.details,
    suggestedSchedule: suggestedSchedule ?? this.suggestedSchedule,
    status: status ?? this.status,
    resultingType: resultingType ?? this.resultingType,
    resultingId: resultingId ?? this.resultingId,
    proposedItems: proposedItems ?? this.proposedItems,
    dispositionedItemIds: dispositionedItemIds ?? this.dispositionedItemIds,
    autoCommittedAt: clearAutoCommittedAt
        ? null
        : (autoCommittedAt ?? this.autoCommittedAt),
    capturedAt: capturedAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// LOCAL-FIRST repository for [Capture]. Writes hit drift and return
/// immediately; sync is background (D5).
abstract interface class CapturesRepository {
  /// All non-discarded, non-deleted captures, newest first.
  Stream<List<Capture>> watchAll();

  /// Inbox queue: captures in the given statuses, newest first.
  Stream<List<Capture>> watchByStatuses(Set<CaptureStatus> statuses);

  /// Fetch specific captures by id (e.g. a focus session's `captures_during`).
  Future<List<Capture>> getByIds(List<String> ids);

  /// Create a capture LOCAL-FIRST (P3 native pipeline). `source` is recorded on
  /// the emitted `capture_created` event only.
  Future<Capture> create({
    String? audioPath,
    DateTime? capturedAt,
    String source,
  });

  /// Persist edits (transcript, triage fields, status). Emits a
  /// `capture_status_changed` event when [Capture.status] changes.
  Future<void> update(Capture capture);

  /// Soft-delete (tombstone) so the delete propagates through sync.
  Future<void> delete(String id);
}

/// Additive replay lookup that includes terminal captures hidden from inbox
/// streams. It prevents a journal replay after a crash from creating a second
/// capture row.
abstract interface class CaptureReplayLookup {
  Future<Capture?> findByAudioPath(String audioPath);
}

/// Atomic P4 state transitions that keep a stale Gemini response from
/// resurrecting a capture after the user has discarded or triaged it.
abstract interface class CaptureProcessingTransitions {
  Future<Capture?> beginProcessing(String captureId);

  /// Completes a `processing` row as either `ready` or `failed`. Returns false
  /// when another terminal action won the race.
  Future<bool> finishProcessing(Capture capture);
}

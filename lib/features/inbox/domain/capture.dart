import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';

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

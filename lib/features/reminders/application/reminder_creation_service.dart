import 'dart:io';

import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/reminders/application/reminder_draft_service.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

@immutable
class ReminderCreationResult {
  const ReminderCreationResult({
    required this.autoCommitted,
    required this.needsReview,
    this.captureId,
    this.unclearAudio = false,
    this.retryLimitReached = false,
  });

  final List<TaskReminder> autoCommitted;
  final List<ParsedReminderDraft> needsReview;
  final String? captureId;
  final bool unclearAudio;
  final bool retryLimitReached;
}

class ReminderCreationService {
  ReminderCreationService({
    required this.captures,
    required this.reminders,
    required this.drafts,
    required this.clock,
    this.autoCommitDelay = const Duration(seconds: 10),
    this.autoCommitConfidence = 0.75,
  });

  final CapturesRepository captures;
  final TaskRemindersRepository reminders;
  final ReminderDraftService drafts;
  final DateTime Function() clock;
  final Duration autoCommitDelay;
  final double autoCommitConfidence;
  final Map<String, int> _audioRetries = <String, int>{};

  Future<ReminderCreationResult> submitText(String input) async {
    final Capture capture = await captures.create(
      inputText: input,
      source: CaptureSource.typed.wire,
    );
    await captures.update(capture.copyWith(status: CaptureStatus.processing));
    try {
      final ReminderDraftParseResult parsed = await drafts.parseText(
        input,
        ReminderDraftContext(now: clock()),
      );
      final ReminderCreationResult result = await _saveParsed(
        parsed,
        source: TaskReminderSource.typed,
        captureId: capture.id,
      );
      await captures.update(
        capture.copyWith(
          status: parsed.isUnclear ? CaptureStatus.failed : CaptureStatus.ready,
          rawTranscript: parsed.rawTranscript,
          error: parsed.isUnclear ? 'Text was unclear.' : null,
          clearError: !parsed.isUnclear,
        ),
      );
      return result;
    } catch (error) {
      await captures.update(
        capture.copyWith(status: CaptureStatus.failed, error: error.toString()),
      );
      rethrow;
    }
  }

  Future<ReminderCreationResult> processAudioCapture(Capture capture) async {
    final String? path = capture.audioPath;
    if (path == null || path.isEmpty) {
      throw const ReminderDraftFormatException(
        'Audio capture has no file path.',
      );
    }
    final int retryCount = _audioRetries[capture.id] ?? 0;
    await captures.update(capture.copyWith(status: CaptureStatus.processing));
    try {
      final ReminderDraftParseResult parsed = await drafts.parseAudio(
        File(path),
        ReminderDraftContext(now: clock(), audioRetryCount: retryCount),
      );
      if (parsed.isUnclear) {
        final int nextRetryCount = retryCount + 1;
        _audioRetries[capture.id] = nextRetryCount;
        await captures.update(
          capture.copyWith(
            status: CaptureStatus.failed,
            rawTranscript: parsed.rawTranscript,
            error: nextRetryCount >= 2
                ? 'Audio was unclear twice. Type the reminder instead.'
                : 'Audio was unclear. Try recording again.',
          ),
        );
        return ReminderCreationResult(
          autoCommitted: const <TaskReminder>[],
          needsReview: const <ParsedReminderDraft>[],
          captureId: capture.id,
          unclearAudio: true,
          retryLimitReached: nextRetryCount >= 2,
        );
      }
      _audioRetries.remove(capture.id);
      final ReminderCreationResult result = await _saveParsed(
        parsed,
        source: TaskReminderSource.audio,
        captureId: capture.id,
      );
      await captures.update(
        capture.copyWith(
          status: CaptureStatus.ready,
          rawTranscript: parsed.rawTranscript,
          error: null,
          clearError: true,
        ),
      );
      return result;
    } catch (error) {
      await captures.update(
        capture.copyWith(status: CaptureStatus.failed, error: error.toString()),
      );
      rethrow;
    }
  }

  Future<int> activateDueAutoCommits() async {
    final DateTime now = clock();
    final List<TaskReminder> pending = await reminders
        .watchByStatus(TaskReminderStatus.pendingAutoCommit)
        .first;
    int activated = 0;
    for (final TaskReminder reminder in pending) {
      final DateTime? deadline = reminder.autoCommitDeadlineAt;
      if (deadline == null || deadline.isAfter(now)) {
        continue;
      }
      await reminders.update(
        _withStatus(reminder, TaskReminderStatus.active, clearDeadline: true),
      );
      activated++;
    }
    return activated;
  }

  Future<void> cancelAutoCommit(String id) async {
    final TaskReminder? reminder = await _findReminder(id);
    if (reminder == null ||
        reminder.status != TaskReminderStatus.pendingAutoCommit) {
      return;
    }
    await reminders.update(
      _withStatus(reminder, TaskReminderStatus.cancelled, clearDeadline: true),
    );
  }

  Future<void> editAutoCommit(
    String id, {
    required String title,
    String? details,
    DateTime? scheduledAt,
  }) async {
    final TaskReminder? reminder = await _findReminder(id);
    if (reminder == null ||
        reminder.status != TaskReminderStatus.pendingAutoCommit) {
      return;
    }
    await reminders.update(
      TaskReminder(
        id: reminder.id,
        userId: reminder.userId,
        title: title,
        details: details,
        status: reminder.status,
        source: reminder.source,
        confidence: 1,
        triggerType: reminder.triggerType,
        scheduledAt: scheduledAt ?? reminder.scheduledAt,
        placeId: reminder.placeId,
        geofenceTransition: reminder.geofenceTransition,
        dwellSeconds: reminder.dwellSeconds,
        autoCommitDeadlineAt: reminder.autoCommitDeadlineAt,
        captureId: reminder.captureId,
        aiExplanation: 'Edited before auto-commit.',
        aiContext: reminder.aiContext,
        createdAt: reminder.createdAt,
        updatedAt: reminder.updatedAt,
      ),
    );
  }

  Future<TaskReminder> approveReviewedDraft(
    ParsedReminderDraft draft, {
    required TaskReminderSource source,
    required String captureId,
    required String title,
    String? details,
    DateTime? scheduledAt,
    String? placeId,
    GeofenceTransition? geofenceTransition,
    int? dwellSeconds,
  }) {
    final String? approvedPlaceId = placeId ?? draft.placeId;
    final TaskReminderTriggerType triggerType = approvedPlaceId != null
        ? TaskReminderTriggerType.place
        : TaskReminderTriggerType.time;
    final DateTime? approvedScheduledAt = scheduledAt ?? draft.scheduledAt;
    final GeofenceTransition? approvedTransition =
        geofenceTransition ?? draft.geofenceTransition;
    if (triggerType == TaskReminderTriggerType.time &&
        approvedScheduledAt == null) {
      throw const ReminderDraftFormatException(
        'Reviewed time reminders need a scheduled time before activation.',
      );
    }
    if (triggerType == TaskReminderTriggerType.place &&
        approvedTransition == null) {
      throw const ReminderDraftFormatException(
        'Reviewed place reminders need a geofence transition before activation.',
      );
    }
    return reminders.create(
      TaskReminderDraft(
        title: title,
        details: details,
        status: TaskReminderStatus.active,
        source: source,
        confidence: 1,
        triggerType: triggerType,
        scheduledAt: triggerType == TaskReminderTriggerType.time
            ? approvedScheduledAt
            : null,
        placeId: approvedPlaceId,
        geofenceTransition: approvedTransition,
        dwellSeconds: dwellSeconds ?? draft.dwellSeconds,
        captureId: captureId,
        aiExplanation: 'Reviewed and approved before activation.',
        aiContext: _aiContext(draft),
      ),
    );
  }

  Future<ReminderCreationResult> _saveParsed(
    ReminderDraftParseResult parsed, {
    required TaskReminderSource source,
    required String captureId,
  }) async {
    if (parsed.isUnclear) {
      return ReminderCreationResult(
        autoCommitted: const <TaskReminder>[],
        needsReview: const <ParsedReminderDraft>[],
        captureId: captureId,
      );
    }
    final List<TaskReminder> autoCommitted = <TaskReminder>[];
    final List<ParsedReminderDraft> review = <ParsedReminderDraft>[];
    for (final ParsedReminderDraft draft in parsed.drafts) {
      if (_canAutoCommit(draft)) {
        autoCommitted.add(
          await reminders.create(
            TaskReminderDraft(
              title: draft.title,
              details: draft.details,
              status: TaskReminderStatus.pendingAutoCommit,
              source: source,
              confidence: draft.confidence,
              triggerType: draft.triggerType,
              scheduledAt: draft.scheduledAt,
              placeId: draft.placeId,
              geofenceTransition: draft.geofenceTransition,
              dwellSeconds: draft.dwellSeconds,
              autoCommitDeadlineAt: clock().add(autoCommitDelay),
              captureId: captureId,
              aiExplanation: draft.explanation,
              aiContext: _aiContext(draft),
            ),
          ),
        );
      } else {
        review.add(draft);
      }
    }
    return ReminderCreationResult(
      autoCommitted: autoCommitted,
      needsReview: review,
      captureId: captureId,
    );
  }

  bool _canAutoCommit(ParsedReminderDraft draft) =>
      draft.confidence >= autoCommitConfidence && draft.hasConcreteTrigger;

  Map<String, Object?> _aiContext(
    ParsedReminderDraft draft,
  ) => <String, Object?>{
    if (draft.placeCandidate != null) 'place_candidate': draft.placeCandidate,
    'auto_commit_eligible': _canAutoCommit(draft),
  };

  Future<TaskReminder?> _findReminder(String id) async {
    final List<TaskReminder> rows = await reminders.watchAll().first;
    for (final TaskReminder reminder in rows) {
      if (reminder.id == id) return reminder;
    }
    return null;
  }

  TaskReminder _withStatus(
    TaskReminder reminder,
    TaskReminderStatus status, {
    bool clearDeadline = false,
  }) => TaskReminder(
    id: reminder.id,
    userId: reminder.userId,
    title: reminder.title,
    details: reminder.details,
    status: status,
    source: reminder.source,
    confidence: reminder.confidence,
    triggerType: reminder.triggerType,
    scheduledAt: reminder.scheduledAt,
    placeId: reminder.placeId,
    geofenceTransition: reminder.geofenceTransition,
    dwellSeconds: reminder.dwellSeconds,
    autoCommitDeadlineAt: clearDeadline ? null : reminder.autoCommitDeadlineAt,
    captureId: reminder.captureId,
    aiExplanation: reminder.aiExplanation,
    aiContext: reminder.aiContext,
    createdAt: reminder.createdAt,
    updatedAt: reminder.updatedAt,
  );
}

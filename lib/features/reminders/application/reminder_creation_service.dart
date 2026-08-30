import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/reminders/application/assistant_context_builder.dart';
import 'package:sidekick/features/reminders/application/reminder_draft_service.dart';
import 'package:sidekick/features/reminders/application/reminder_scheduler.dart';
import 'package:sidekick/features/reminders/domain/reminder_event.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

@immutable
class PendingReviewDraft {
  const PendingReviewDraft({
    required this.captureId,
    required this.source,
    required this.draft,
  });

  final String captureId;
  final TaskReminderSource source;
  final ParsedReminderDraft draft;
}

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
    this.scheduler,
    this.contextBuilder,
    this.events,
    this.atomically,
    this.timeZoneSource,
    this.persistTimeZone,
    this.autoCommitDelay = const Duration(seconds: 10),
    this.autoCommitConfidence = 0.75,
  });

  final CapturesRepository captures;
  final TaskRemindersRepository reminders;
  final ReminderDraftService drafts;
  final DateTime Function() clock;
  final ReminderScheduler? scheduler;
  final AssistantContextBuilder? contextBuilder;
  final ReminderEventsRepository? events;
  final Future<T> Function<T>(Future<T> Function() action)? atomically;
  final DeviceTimeZoneSource? timeZoneSource;
  final Future<void> Function(String timeZoneName)? persistTimeZone;
  final Duration autoCommitDelay;
  final double autoCommitConfidence;

  static const String _captureStatePrefix = 'sidekick_state:';
  static const String _captureStateMetadataKey = 'draft_state';

  bool audioRetryLimitReached(Capture capture) =>
      audioRetryLimitReachedFor(capture);

  String? captureStateMessage(Capture capture) =>
      captureStateMessageFor(capture);

  static bool audioRetryLimitReachedFor(Capture capture) =>
      _decodeCaptureState(capture).audioAttempts >= 3;

  static String? captureStateMessageFor(Capture capture) =>
      _decodeCaptureState(capture).message;

  Future<void> associateReplacementRecording(
    Capture capture, {
    required String audioPath,
  }) async {
    final String trimmed = audioPath.trim();
    if (trimmed.isEmpty) {
      throw const ReminderDraftFormatException(
        'Replacement audio capture has no file path.',
      );
    }
    final Capture current = await _reloadCapture(capture);
    final _CaptureDraftState state = _decodeCaptureState(current);
    if (state.audioAttempts >= 3) {
      throw const ReminderDraftFormatException(
        'Audio retry limit has been reached; type the reminder instead.',
      );
    }
    await captures.update(
      current.copyWith(
        audioPath: trimmed,
        status: CaptureStatus.pending,
        metadata: _withCaptureState(
          current,
          _encodeCaptureState(
            reviewDrafts: state.reviewDrafts,
            source: state.source,
            audioAttempts: state.audioAttempts,
            message: 'Replacement recording attached. Draft audio when ready.',
          ),
        ),
        clearError: true,
      ),
    );
  }

  Future<ReminderCreationResult> submitText(String input) async {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const ReminderCreationResult(
        autoCommitted: <TaskReminder>[],
        needsReview: <ParsedReminderDraft>[],
      );
    }
    final Capture capture = await captures.create(
      inputText: trimmed,
      source: CaptureSource.typed.wire,
    );
    await captures.update(capture.copyWith(status: CaptureStatus.processing));
    try {
      final AssistantContext? assistantContext = await contextBuilder?.build();
      final ReminderDraftParseResult parsed = await drafts.parseText(
        trimmed,
        ReminderDraftContext(
          now: clock(),
          timeZoneName: await _timeZoneName(assistantContext),
          assistantContext: assistantContext,
        ),
      );
      final ReminderCreationResult result = await _runAtomic(() async {
        final ReminderCreationResult result = await _saveParsed(
          parsed,
          source: TaskReminderSource.typed,
          captureId: capture.id,
        );
        await captures.update(
          capture.copyWith(
            status: parsed.isUnclear
                ? CaptureStatus.failed
                : CaptureStatus.ready,
            rawTranscript: parsed.rawTranscript,
            error: parsed.isUnclear ? 'Text was unclear.' : null,
            metadata: _withCaptureState(
              capture,
              parsed.isUnclear
                  ? null
                  : _encodeCaptureState(
                      reviewDrafts: result.needsReview,
                      source: TaskReminderSource.typed,
                    ),
            ),
            clearError: !parsed.isUnclear && result.needsReview.isEmpty,
          ),
        );
        return result;
      });
      await _schedulePendingReminders(result.autoCommitted);
      return result;
    } catch (error) {
      await captures.update(
        capture.copyWith(status: CaptureStatus.failed, error: error.toString()),
      );
      rethrow;
    }
  }

  Future<TaskReminder> createManualReminder({
    required String title,
    String? details,
    required TaskReminderTriggerType triggerType,
    DateTime? scheduledAt,
    String? placeId,
    GeofenceTransition? geofenceTransition,
  }) async {
    final String cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw const ReminderDraftFormatException('Reminder title is required.');
    }
    if (triggerType == TaskReminderTriggerType.time &&
        (scheduledAt == null || !scheduledAt.isAfter(clock()))) {
      throw const ReminderDraftFormatException(
        'Choose a future date and time.',
      );
    }
    if (triggerType == TaskReminderTriggerType.place &&
        (placeId == null || geofenceTransition == null)) {
      throw const ReminderDraftFormatException(
        'Choose a saved place and whether you are arriving or leaving.',
      );
    }
    final TaskReminder reminder = await reminders.create(
      TaskReminderDraft(
        title: cleanTitle,
        details: details?.trim().isEmpty ?? true ? null : details!.trim(),
        source: TaskReminderSource.manual,
        confidence: 1,
        triggerType: triggerType,
        scheduledAt: triggerType == TaskReminderTriggerType.time
            ? scheduledAt
            : null,
        placeId: triggerType == TaskReminderTriggerType.place ? placeId : null,
        geofenceTransition: triggerType == TaskReminderTriggerType.place
            ? geofenceTransition
            : null,
      ),
    );
    await scheduler?.schedule(reminder);
    return reminder;
  }

  Future<ReminderCreationResult> processAudioCapture(Capture capture) async {
    final Capture current = await _reloadCapture(capture);
    final String? path = current.audioPath;
    if (path == null || path.isEmpty) {
      throw const ReminderDraftFormatException(
        'Audio capture has no file path.',
      );
    }
    final _CaptureDraftState initialState = _decodeCaptureState(current);
    final int retryCount = initialState.audioAttempts;
    if (retryCount >= 3) {
      await captures.update(
        current.copyWith(
          status: CaptureStatus.failed,
          error:
              'Audio was unclear after three attempts. Type the reminder instead.',
          metadata: _withCaptureState(
            current,
            _encodeCaptureState(
              reviewDrafts: initialState.reviewDrafts,
              source: initialState.source,
              audioAttempts: retryCount,
              message:
                  'Audio was unclear after three attempts. Type the reminder instead.',
            ),
          ),
        ),
      );
      return ReminderCreationResult(
        autoCommitted: const <TaskReminder>[],
        needsReview: const <ParsedReminderDraft>[],
        captureId: current.id,
        unclearAudio: true,
        retryLimitReached: true,
      );
    }
    await captures.update(current.copyWith(status: CaptureStatus.processing));
    try {
      final AssistantContext? assistantContext = await contextBuilder?.build();
      final ReminderDraftParseResult parsed = await drafts.parseAudio(
        File(path),
        ReminderDraftContext(
          now: clock(),
          audioRetryCount: retryCount,
          timeZoneName: await _timeZoneName(assistantContext),
          assistantContext: assistantContext,
        ),
      );
      if (parsed.isUnclear) {
        return _runAtomic(() async {
          final Capture latest = await _reloadCapture(current);
          final _CaptureDraftState latestState = _decodeCaptureState(latest);
          final int nextRetryCount = latestState.audioAttempts + 1;
          await captures.update(
            latest.copyWith(
              status: CaptureStatus.failed,
              rawTranscript: parsed.rawTranscript,
              error: nextRetryCount > 2
                  ? 'Audio was unclear after three attempts. Type the reminder instead.'
                  : 'Audio was unclear. Try recording again.',
              metadata: _withCaptureState(
                latest,
                _encodeCaptureState(
                  reviewDrafts: latestState.reviewDrafts,
                  source: latestState.source,
                  audioAttempts: nextRetryCount,
                  message: nextRetryCount > 2
                      ? 'Audio was unclear after three attempts. Type the reminder instead.'
                      : 'Audio was unclear. Try recording again.',
                ),
              ),
            ),
          );
          return ReminderCreationResult(
            autoCommitted: const <TaskReminder>[],
            needsReview: const <ParsedReminderDraft>[],
            captureId: current.id,
            unclearAudio: true,
            retryLimitReached: nextRetryCount > 2,
          );
        });
      }
      final ReminderCreationResult result = await _runAtomic(() async {
        final Capture latest = await _reloadCapture(current);
        final _CaptureDraftState latestState = _decodeCaptureState(latest);
        final ReminderCreationResult result = await _saveParsed(
          parsed,
          source: TaskReminderSource.audio,
          captureId: current.id,
        );
        await captures.update(
          latest.copyWith(
            status: CaptureStatus.ready,
            rawTranscript: parsed.rawTranscript,
            metadata: _withCaptureState(
              latest,
              _encodeCaptureState(
                reviewDrafts: result.needsReview,
                source: TaskReminderSource.audio,
                audioAttempts: latestState.audioAttempts,
              ),
            ),
            clearError: true,
          ),
        );
        return result;
      });
      await _schedulePendingReminders(result.autoCommitted);
      return result;
    } catch (error) {
      final Capture latest = await _reloadCapture(current);
      final _CaptureDraftState latestState = _decodeCaptureState(latest);
      await captures.update(
        latest.copyWith(
          status: CaptureStatus.failed,
          error: error.toString(),
          metadata: _withCaptureState(
            latest,
            _encodeCaptureState(
              reviewDrafts: latestState.reviewDrafts,
              source: latestState.source,
              audioAttempts: latestState.audioAttempts,
              message: error.toString(),
            ),
          ),
        ),
      );
      rethrow;
    }
  }

  Future<int> activateDueAutoCommits() async {
    final ReminderScheduler? attachedScheduler = scheduler;
    if (attachedScheduler != null) {
      return attachedScheduler.activateDueAutoCommits();
    }
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
      final TaskReminder active = _withStatus(
        reminder,
        TaskReminderStatus.active,
        clearDeadline: true,
      );
      await reminders.update(active);
      await scheduler?.schedule(active);
      activated++;
    }
    return activated;
  }

  Future<void> approveAutoCommit(String id) async {
    final TaskReminder? reminder = await _findReminder(id);
    if (reminder == null ||
        reminder.status != TaskReminderStatus.pendingAutoCommit) {
      return;
    }
    final TaskReminder active = _withStatus(
      reminder,
      TaskReminderStatus.active,
      clearDeadline: true,
    );
    await reminders.update(active);
    await events?.append(
      reminderId: active.id,
      eventType: ReminderEventType.activated,
      metadata: const <String, Object?>{'source': 'manual_approval'},
    );
    await scheduler?.schedule(active);
  }

  Future<List<PendingReviewDraft>> pendingReviewDrafts() async {
    final List<Capture> rows = await captures.watchByStatuses(<CaptureStatus>{
      CaptureStatus.ready,
      CaptureStatus.failed,
    }).first;
    return rows
        .expand((Capture capture) {
          final _CaptureDraftState state = _decodeCaptureState(capture);
          return state.reviewDrafts.map(
            (ParsedReminderDraft draft) => PendingReviewDraft(
              captureId: capture.id,
              source:
                  state.source ??
                  (capture.source == CaptureSource.audio
                      ? TaskReminderSource.audio
                      : TaskReminderSource.typed),
              draft: draft,
            ),
          );
        })
        .toList(growable: false);
  }

  Future<void> dismissReviewedDraft(PendingReviewDraft entry) async {
    final List<Capture> rows = await captures.getByIds(<String>[
      entry.captureId,
    ]);
    if (rows.isEmpty) return;
    final Capture capture = rows.single;
    final _CaptureDraftState state = _decodeCaptureState(capture);
    final List<ParsedReminderDraft> remaining = state.reviewDrafts
        .where(
          (ParsedReminderDraft draft) => draft.draftId != entry.draft.draftId,
        )
        .toList(growable: false);
    await captures.update(
      capture.copyWith(
        metadata: _withCaptureState(
          capture,
          _encodeCaptureState(
            reviewDrafts: remaining,
            source: state.source,
            audioAttempts: state.audioAttempts,
            message: state.message,
          ),
        ),
        error: state.message,
        clearError: state.message == null,
      ),
    );
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
    await scheduler?.cancel(id);
  }

  Future<void> cancelReminder(String id) async {
    final TaskReminder? reminder = await _findReminder(id);
    if (reminder == null ||
        !<TaskReminderStatus>{
          TaskReminderStatus.active,
          TaskReminderStatus.pendingAutoCommit,
        }.contains(reminder.status)) {
      return;
    }
    await reminders.update(
      _withStatus(reminder, TaskReminderStatus.cancelled, clearDeadline: true),
    );
    await scheduler?.cancel(id);
  }

  Future<void> reenableReminder(String id, {DateTime? scheduledAt}) async {
    final TaskReminder? reminder = await _findReminder(id);
    if (reminder == null ||
        <TaskReminderStatus>{
          TaskReminderStatus.active,
          TaskReminderStatus.pendingAutoCommit,
        }.contains(reminder.status)) {
      return;
    }
    final DateTime? nextSchedule = scheduledAt ?? reminder.scheduledAt;
    if (reminder.triggerType == TaskReminderTriggerType.time &&
        (nextSchedule == null || !nextSchedule.isAfter(clock()))) {
      throw StateError(
        'Choose a future time before re-enabling this reminder.',
      );
    }
    final TaskReminder active = TaskReminder(
      id: reminder.id,
      userId: reminder.userId,
      title: reminder.title,
      details: reminder.details,
      status: TaskReminderStatus.active,
      source: reminder.source,
      confidence: reminder.confidence,
      triggerType: reminder.triggerType,
      scheduledAt: nextSchedule,
      placeId: reminder.placeId,
      geofenceTransition: reminder.geofenceTransition,
      dwellSeconds: reminder.dwellSeconds,
      captureId: reminder.captureId,
      draftId: reminder.draftId,
      aiExplanation: reminder.aiExplanation,
      aiContext: reminder.aiContext,
      createdAt: reminder.createdAt,
      updatedAt: reminder.updatedAt,
    );
    await reminders.update(active);
    await events?.append(
      reminderId: active.id,
      eventType: ReminderEventType.activated,
      metadata: const <String, Object?>{'source': 'reminders_tab'},
    );
    await scheduler?.schedule(active);
  }

  Future<void> rescheduleReminder(String id, DateTime scheduledAt) async {
    final TaskReminder? reminder = await _findReminder(id);
    if (reminder == null ||
        reminder.triggerType != TaskReminderTriggerType.time) {
      return;
    }
    if (!scheduledAt.isAfter(clock())) {
      throw StateError('Reminder time must be in the future.');
    }
    final TaskReminder updated = TaskReminder(
      id: reminder.id,
      userId: reminder.userId,
      title: reminder.title,
      details: reminder.details,
      status: TaskReminderStatus.active,
      source: reminder.source,
      confidence: reminder.confidence,
      triggerType: reminder.triggerType,
      scheduledAt: scheduledAt,
      placeId: reminder.placeId,
      geofenceTransition: reminder.geofenceTransition,
      dwellSeconds: reminder.dwellSeconds,
      captureId: reminder.captureId,
      draftId: reminder.draftId,
      aiExplanation: reminder.aiExplanation,
      aiContext: reminder.aiContext,
      createdAt: reminder.createdAt,
      updatedAt: reminder.updatedAt,
    );
    await reminders.update(updated);
    await events?.append(
      reminderId: updated.id,
      eventType: ReminderEventType.edited,
      metadata: const <String, Object?>{
        'source': 'reminders_tab',
        'scheduled_at_changed': true,
      },
    );
    await scheduler?.schedule(updated);
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
    final TaskReminder edited = TaskReminder(
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
      draftId: reminder.draftId,
      aiExplanation: 'Edited before auto-commit.',
      aiContext: _withEditContext(reminder.aiContext),
      createdAt: reminder.createdAt,
      updatedAt: reminder.updatedAt,
    );
    await reminders.update(edited);
    await events?.append(
      reminderId: edited.id,
      eventType: ReminderEventType.edited,
      metadata: <String, Object?>{
        'source': 'auto_commit_review',
        'title_changed': title != reminder.title,
        'details_changed': details != reminder.details,
        'scheduled_at_changed': scheduledAt != null,
      },
    );
    await scheduler?.schedule(edited);
  }

  Future<void> editReminder(
    String id, {
    required String title,
    String? details,
    DateTime? scheduledAt,
  }) async {
    final TaskReminder? reminder = await _findReminder(id);
    if (reminder == null ||
        !<TaskReminderStatus>{
          TaskReminderStatus.active,
          TaskReminderStatus.pendingAutoCommit,
        }.contains(reminder.status)) {
      return;
    }
    final TaskReminder edited = TaskReminder(
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
      draftId: reminder.draftId,
      aiExplanation: reminder.status == TaskReminderStatus.pendingAutoCommit
          ? 'Edited before auto-commit.'
          : 'Edited after notification feedback.',
      aiContext: _withEditContext(reminder.aiContext),
      createdAt: reminder.createdAt,
      updatedAt: reminder.updatedAt,
    );
    await reminders.update(edited);
    await events?.append(
      reminderId: edited.id,
      eventType: ReminderEventType.edited,
      metadata: <String, Object?>{
        'source': reminder.status == TaskReminderStatus.pendingAutoCommit
            ? 'auto_commit_review'
            : 'reminder_edit',
        'title_changed': title != reminder.title,
        'details_changed': details != reminder.details,
        'scheduled_at_changed': scheduledAt != null,
      },
    );
    await scheduler?.schedule(edited);
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
  }) async {
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
    final ParsedReminderDraft approvedDraft = _withDraftId(
      draft,
      draft.draftId ?? _stableDraftId(draft, 0),
    );
    final TaskReminder? existing = await _findReminderByCaptureDraft(
      captureId,
      approvedDraft.draftId!,
    );
    if (existing != null) {
      await _clearPersistedReview(captureId, approvedDraft);
      await scheduler?.schedule(existing);
      return existing;
    }
    final TaskReminder reminder = await _runAtomic(() async {
      final TaskReminder created = await reminders.create(
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
          dwellSeconds: dwellSeconds ?? approvedDraft.dwellSeconds,
          captureId: captureId,
          draftId: approvedDraft.draftId,
          aiExplanation: 'Reviewed and approved before activation.',
          aiContext: _aiContext(approvedDraft),
        ),
      );
      await _clearPersistedReview(captureId, approvedDraft);
      return created;
    });
    await scheduler?.schedule(reminder);
    return reminder;
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
    final List<ParsedReminderDraft> normalizedDrafts = <ParsedReminderDraft>[
      for (int i = 0; i < parsed.drafts.length; i++)
        _withDraftId(
          parsed.drafts[i],
          parsed.drafts[i].draftId ?? _stableDraftId(parsed.drafts[i], i),
        ),
    ];
    final List<TaskReminder> autoCommitted = <TaskReminder>[];
    final List<ParsedReminderDraft> review = <ParsedReminderDraft>[];
    for (final ParsedReminderDraft draft in normalizedDrafts) {
      _validateDraftForPersistence(draft);
    }
    final List<TaskReminder> existing = (await reminders.watchAll().first)
        .where((TaskReminder reminder) => reminder.captureId == captureId)
        .toList(growable: false);
    final Set<String> existingDraftIds = existing
        .map((TaskReminder reminder) => reminder.aiContext?['draft_id'])
        .followedBy(existing.map((TaskReminder reminder) => reminder.draftId))
        .whereType<String>()
        .toSet();
    for (final TaskReminder reminder in existing) {
      if (reminder.status == TaskReminderStatus.pendingAutoCommit) {
        autoCommitted.add(reminder);
      }
    }
    final Set<String> seenReviewDraftIds = <String>{};
    final _CaptureDraftState persistedState = await _captureState(captureId);
    for (final ParsedReminderDraft draft in persistedState.reviewDrafts) {
      if (draft.draftId != null) {
        seenReviewDraftIds.add(draft.draftId!);
      }
    }
    for (final ParsedReminderDraft draft in normalizedDrafts) {
      if (existingDraftIds.contains(draft.draftId)) {
        continue;
      }
      if (seenReviewDraftIds.contains(draft.draftId)) {
        review.add(draft);
        continue;
      }
      if (_canAutoCommit(draft)) {
        final TaskReminder pending = await reminders.create(
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
            draftId: draft.draftId,
            aiExplanation: draft.explanation,
            aiContext: _aiContext(draft),
          ),
        );
        autoCommitted.add(pending);
      } else {
        review.add(draft);
        seenReviewDraftIds.add(draft.draftId!);
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

  Future<void> _schedulePendingReminders(
    List<TaskReminder> remindersToSchedule,
  ) async {
    for (final TaskReminder reminder in remindersToSchedule) {
      try {
        // Register the underlying trigger during the correction window. If the
        // app is killed before the deadline, the OS still owns the reminder;
        // cancel/edit paths reconcile this registration immediately.
        await scheduler?.schedule(reminder);
      } catch (_) {
        // Native permission/runtime failures must not roll back local-first
        // capture and reminder rows.
      }
    }
  }

  void _validateDraftForPersistence(ParsedReminderDraft draft) {
    if (draft.title.trim().isEmpty) {
      throw const ReminderDraftFormatException(
        'Reminder drafts must include a title.',
      );
    }
    if (!draft.confidence.isFinite ||
        draft.confidence < 0 ||
        draft.confidence > 1) {
      throw const ReminderDraftFormatException(
        'Reminder confidence must be finite and between 0 and 1.',
      );
    }
    if (draft.triggerType == TaskReminderTriggerType.time &&
        draft.placeId != null) {
      throw const ReminderDraftFormatException(
        'Time reminders cannot include place fields.',
      );
    }
    if (draft.triggerType == TaskReminderTriggerType.place &&
        draft.scheduledAt != null) {
      throw const ReminderDraftFormatException(
        'Place reminders cannot include scheduled_at.',
      );
    }
  }

  Map<String, Object?> _aiContext(
    ParsedReminderDraft draft,
  ) => <String, Object?>{
    if (draft.draftId != null) 'draft_id': draft.draftId,
    if (draft.placeCandidate != null) 'place_candidate': draft.placeCandidate,
    if (draft.contextItemsUsed.isNotEmpty)
      'context_items_used': draft.contextItemsUsed,
    'auto_commit_eligible': _canAutoCommit(draft),
  };

  Map<String, Object?> _withEditContext(Map<String, Object?>? current) =>
      <String, Object?>{
        ...?current,
        'user_edited': true,
        'context_feedback_event': ReminderEventType.edited.wire,
      };

  Future<TaskReminder?> _findReminder(String id) async {
    final List<TaskReminder> rows = await reminders.watchAll().first;
    for (final TaskReminder reminder in rows) {
      if (reminder.id == id) return reminder;
    }
    return null;
  }

  Future<TaskReminder?> _findReminderByCaptureDraft(
    String captureId,
    String draftId,
  ) async {
    final List<TaskReminder> rows = await reminders.watchAll().first;
    for (final TaskReminder reminder in rows) {
      if (reminder.captureId == captureId &&
          (reminder.draftId == draftId ||
              reminder.aiContext?['draft_id'] == draftId)) {
        return reminder;
      }
    }
    return null;
  }

  Future<_CaptureDraftState> _captureState(String captureId) async {
    final List<Capture> rows = await captures.getByIds(<String>[captureId]);
    if (rows.isEmpty) return const _CaptureDraftState();
    return _decodeCaptureState(rows.single);
  }

  Future<Capture> _reloadCapture(Capture capture) async {
    final List<Capture> rows = await captures.getByIds(<String>[capture.id]);
    if (rows.isEmpty) return capture;
    return rows.single;
  }

  Future<AtomicValue> _runAtomic<AtomicValue>(
    Future<AtomicValue> Function() action,
  ) {
    final tx = atomically;
    if (tx == null) {
      return action();
    }
    return tx<AtomicValue>(action);
  }

  Future<String> _timeZoneName(AssistantContext? context) async {
    final Object? prefs = context?.profile?['prefs'];
    if (prefs is Map<String, Object?>) {
      final Object? value = prefs['timezone'];
      if (value is String && value.trim().isNotEmpty) {
        final String storedZone = value.trim();
        if (HeuristicReminderDraftService.isSupportedTimeZone(storedZone)) {
          return storedZone;
        }
      }
    }
    final String zone = await timeZoneSource?.currentTimeZoneName() ?? 'UTC';
    if (!HeuristicReminderDraftService.isSupportedTimeZone(zone)) {
      throw ReminderDraftFormatException(
        'The device returned an unsupported timezone ($zone).',
      );
    }
    if (zone != 'UTC') {
      try {
        await persistTimeZone?.call(zone);
      } catch (_) {
        // Preference persistence is local-first enrichment; drafting can still
        // proceed with the zone returned by the device.
      }
    }
    return zone;
  }

  ParsedReminderDraft _withDraftId(ParsedReminderDraft draft, String id) =>
      ParsedReminderDraft(
        draftId: id,
        title: draft.title,
        details: draft.details,
        confidence: draft.confidence,
        triggerType: draft.triggerType,
        scheduledAt: draft.scheduledAt,
        placeId: draft.placeId,
        placeCandidate: draft.placeCandidate,
        geofenceTransition: draft.geofenceTransition,
        dwellSeconds: draft.dwellSeconds,
        explanation: draft.explanation,
        contextItemsUsed: draft.contextItemsUsed,
      );

  String _stableDraftId(ParsedReminderDraft draft, int index) {
    final String payload = jsonEncode(<String, Object?>{
      'index': index,
      'title': draft.title,
      'details': draft.details,
      'trigger_type': draft.triggerType.wire,
      'scheduled_at': draft.scheduledAt?.toUtc().toIso8601String(),
      'place_id': draft.placeId,
      'transition': draft.geofenceTransition?.wire,
    });
    int hash = 0xcbf29ce484222325;
    for (final int unit in payload.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return 'draft_${hash.toRadixString(16)}';
  }

  Future<void> _clearPersistedReview(
    String captureId,
    ParsedReminderDraft approved,
  ) async {
    final List<Capture> rows = await captures.getByIds(<String>[captureId]);
    if (rows.isEmpty) return;
    final Capture capture = rows.single;
    final _CaptureDraftState state = _decodeCaptureState(capture);
    if (state.reviewDrafts.isEmpty) return;
    final List<ParsedReminderDraft> remaining = state.reviewDrafts
        .where((ParsedReminderDraft draft) => draft.draftId != approved.draftId)
        .toList(growable: false);
    await captures.update(
      capture.copyWith(
        metadata: _withCaptureState(
          capture,
          _encodeCaptureState(
            reviewDrafts: remaining,
            source: state.source,
            audioAttempts: state.audioAttempts,
            message: state.message,
          ),
        ),
        error: state.message,
        clearError: state.message == null,
      ),
    );
  }

  String? _encodeCaptureState({
    List<ParsedReminderDraft> reviewDrafts = const <ParsedReminderDraft>[],
    TaskReminderSource? source,
    int audioAttempts = 0,
    String? message,
  }) {
    if (reviewDrafts.isEmpty && audioAttempts == 0 && message == null) {
      return null;
    }
    return '$_captureStatePrefix${jsonEncode(<String, Object?>{'review_drafts': reviewDrafts.map((ParsedReminderDraft draft) => draft.toJson()).toList(growable: false), 'source': source?.wire, if (audioAttempts > 0) 'audio_attempts': audioAttempts, 'message': message})}';
  }

  static Map<String, Object?> _withCaptureState(
    Capture capture,
    String? value,
  ) {
    final Map<String, Object?> metadata = <String, Object?>{
      ...capture.metadata,
    };
    if (value == null) {
      metadata.remove(_captureStateMetadataKey);
    } else {
      metadata[_captureStateMetadataKey] = value;
    }
    return metadata;
  }

  static _CaptureDraftState _decodeCaptureState(Capture capture) {
    final Object? metadataValue = capture.metadata[_captureStateMetadataKey];
    final String? value = metadataValue is String
        ? metadataValue
        : capture.error?.startsWith(_captureStatePrefix) == true
        ? capture.error
        : null;
    if (value == null || !value.startsWith(_captureStatePrefix)) {
      return const _CaptureDraftState();
    }
    try {
      final Object? decoded = jsonDecode(
        value.substring(_captureStatePrefix.length),
      );
      final Map<String, Object?> json = Map<String, Object?>.from(
        decoded as Map,
      );
      return _CaptureDraftState(
        reviewDrafts:
            List<Object?>.from(
                  json['review_drafts'] as List? ?? const <Object?>[],
                )
                .map(
                  (Object? value) => ParsedReminderDraft.fromJson(
                    Map<String, Object?>.from(value as Map),
                  ),
                )
                .toList(growable: false),
        source: json['source'] == null
            ? null
            : TaskReminderSource.fromWire(json['source']! as String),
        audioAttempts: (json['audio_attempts'] as num?)?.toInt() ?? 0,
        message: json['message'] as String?,
      );
    } catch (_) {
      return const _CaptureDraftState();
    }
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
    draftId: reminder.draftId,
    aiExplanation: reminder.aiExplanation,
    aiContext: reminder.aiContext,
    createdAt: reminder.createdAt,
    updatedAt: reminder.updatedAt,
  );
}

class _CaptureDraftState {
  const _CaptureDraftState({
    this.reviewDrafts = const <ParsedReminderDraft>[],
    this.source,
    this.audioAttempts = 0,
    this.message,
  });

  final List<ParsedReminderDraft> reviewDrafts;
  final TaskReminderSource? source;
  final int audioAttempts;
  final String? message;
}

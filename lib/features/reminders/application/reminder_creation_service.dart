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
  final Duration autoCommitDelay;
  final double autoCommitConfidence;

  static const String _captureStatePrefix = 'sidekick_state:';

  bool audioRetryLimitReached(Capture capture) =>
      audioRetryLimitReachedFor(capture);

  String? captureStateMessage(Capture capture) =>
      captureStateMessageFor(capture);

  static bool audioRetryLimitReachedFor(Capture capture) =>
      _decodeCaptureState(capture.error).audioAttempts >= 3;

  static String? captureStateMessageFor(Capture capture) =>
      _decodeCaptureState(capture.error).message;

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
    final _CaptureDraftState state = _decodeCaptureState(current.error);
    if (state.audioAttempts >= 3) {
      throw const ReminderDraftFormatException(
        'Audio retry limit has been reached; type the reminder instead.',
      );
    }
    await captures.update(
      current.copyWith(
        audioPath: trimmed,
        status: CaptureStatus.pending,
        error: _encodeCaptureState(
          reviewDrafts: state.reviewDrafts,
          source: state.source,
          audioAttempts: state.audioAttempts,
          message: 'Replacement recording attached. Draft audio when ready.',
        ),
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
          timeZoneName: _timeZoneName(assistantContext),
          assistantContext: assistantContext,
        ),
      );
      return _runAtomic(() async {
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
            error: parsed.isUnclear
                ? 'Text was unclear.'
                : _encodeCaptureState(
                    reviewDrafts: result.needsReview,
                    source: TaskReminderSource.typed,
                  ),
            clearError: !parsed.isUnclear && result.needsReview.isEmpty,
          ),
        );
        return result;
      });
    } catch (error) {
      await captures.update(
        capture.copyWith(status: CaptureStatus.failed, error: error.toString()),
      );
      rethrow;
    }
  }

  Future<ReminderCreationResult> processAudioCapture(Capture capture) async {
    final Capture current = await _reloadCapture(capture);
    final String? path = current.audioPath;
    if (path == null || path.isEmpty) {
      throw const ReminderDraftFormatException(
        'Audio capture has no file path.',
      );
    }
    final _CaptureDraftState initialState = _decodeCaptureState(current.error);
    final int retryCount = initialState.audioAttempts;
    if (retryCount >= 3) {
      await captures.update(
        current.copyWith(
          status: CaptureStatus.failed,
          error: _encodeCaptureState(
            reviewDrafts: initialState.reviewDrafts,
            source: initialState.source,
            audioAttempts: retryCount,
            message:
                'Audio was unclear after three attempts. Type the reminder instead.',
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
          timeZoneName: _timeZoneName(assistantContext),
          assistantContext: assistantContext,
        ),
      );
      if (parsed.isUnclear) {
        return _runAtomic(() async {
          final Capture latest = await _reloadCapture(current);
          final _CaptureDraftState latestState = _decodeCaptureState(
            latest.error,
          );
          final int nextRetryCount = latestState.audioAttempts + 1;
          await captures.update(
            latest.copyWith(
              status: CaptureStatus.failed,
              rawTranscript: parsed.rawTranscript,
              error: _encodeCaptureState(
                reviewDrafts: latestState.reviewDrafts,
                source: latestState.source,
                audioAttempts: nextRetryCount,
                message: nextRetryCount > 2
                    ? 'Audio was unclear after three attempts. Type the reminder instead.'
                    : 'Audio was unclear. Try recording again.',
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
      return _runAtomic(() async {
        final Capture latest = await _reloadCapture(current);
        final _CaptureDraftState latestState = _decodeCaptureState(
          latest.error,
        );
        final ReminderCreationResult result = await _saveParsed(
          parsed,
          source: TaskReminderSource.audio,
          captureId: current.id,
        );
        await captures.update(
          latest.copyWith(
            status: CaptureStatus.ready,
            rawTranscript: parsed.rawTranscript,
            error: _encodeCaptureState(
              reviewDrafts: result.needsReview,
              source: TaskReminderSource.audio,
              audioAttempts: latestState.audioAttempts,
            ),
            clearError:
                result.needsReview.isEmpty && latestState.audioAttempts == 0,
          ),
        );
        return result;
      });
    } catch (error) {
      final Capture latest = await _reloadCapture(current);
      final _CaptureDraftState latestState = _decodeCaptureState(latest.error);
      await captures.update(
        latest.copyWith(
          status: CaptureStatus.failed,
          error: _encodeCaptureState(
            reviewDrafts: latestState.reviewDrafts,
            source: latestState.source,
            audioAttempts: latestState.audioAttempts,
            message: error.toString(),
          ),
        ),
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

  Future<List<PendingReviewDraft>> pendingReviewDrafts() async {
    final List<Capture> rows = await captures.watchByStatuses(<CaptureStatus>{
      CaptureStatus.ready,
      CaptureStatus.failed,
    }).first;
    return rows
        .expand((Capture capture) {
          final _CaptureDraftState state = _decodeCaptureState(capture.error);
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
    final _CaptureDraftState state = _decodeCaptureState(capture.error);
    final List<ParsedReminderDraft> remaining = state.reviewDrafts
        .where(
          (ParsedReminderDraft draft) => draft.draftId != entry.draft.draftId,
        )
        .toList(growable: false);
    await captures.update(
      capture.copyWith(
        error: _encodeCaptureState(
          reviewDrafts: remaining,
          source: state.source,
          audioAttempts: state.audioAttempts,
          message: state.message,
        ),
        clearError: remaining.isEmpty && state.message == null,
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
              draftId: draft.draftId,
              aiExplanation: draft.explanation,
              aiContext: _aiContext(draft),
            ),
          ),
        );
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
    return _decodeCaptureState(rows.single.error);
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

  String _timeZoneName(AssistantContext? context) {
    final Object? prefs = context?.profile?['prefs'];
    if (prefs is Map<String, Object?>) {
      final Object? value = prefs['timezone'];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return 'UTC';
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
    final _CaptureDraftState state = _decodeCaptureState(capture.error);
    if (state.reviewDrafts.isEmpty) return;
    final List<ParsedReminderDraft> remaining = state.reviewDrafts
        .where((ParsedReminderDraft draft) => draft.draftId != approved.draftId)
        .toList(growable: false);
    await captures.update(
      capture.copyWith(
        error: _encodeCaptureState(
          reviewDrafts: remaining,
          source: state.source,
          audioAttempts: state.audioAttempts,
          message: state.message,
        ),
        clearError: remaining.isEmpty && state.message == null,
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

  static _CaptureDraftState _decodeCaptureState(String? value) {
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

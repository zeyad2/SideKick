import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sidekick/core/audio/pending_audio_queue.dart';
import 'package:sidekick/core/capture/capture_ingestion_barrier.dart';
import 'package:sidekick/core/capture/native_capture_api.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/core/events/event_emitter.dart';
import 'package:sidekick/features/goals/domain/goal.dart';
import 'package:sidekick/features/habits/domain/habit.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/inbox/domain/proposed_item.dart';
import 'package:sidekick/features/notes/domain/note.dart';
import 'package:sidekick/features/tasks/domain/task.dart';

class CaptureTriageDraft {
  const CaptureTriageDraft({
    required this.type,
    required this.title,
    required this.details,
    this.scheduledAt,
    this.habitLevel = HabitLevel.mini,
  });

  final ResultingType type;
  final String title;
  final String details;
  final DateTime? scheduledAt;
  final HabitLevel habitLevel;
}

class CaptureTriageResult {
  const CaptureTriageResult({required this.type, required this.id});
  final ResultingType type;
  final String id;
}

class CaptureTriageService {
  CaptureTriageService({
    required this.userId,
    required this.captures,
    required this.tasks,
    required this.notes,
    required this.habits,
    required this.goals,
    required this.emitter,
    required this.nativeApi,
    required this.pendingQueue,
    required this.barrier,
    required this.db,
    IdGenerator? idGenerator,
    DateTime Function()? clock,
    this.autoCommitUndoWindow = const Duration(seconds: 30),
  }) : idGenerator = idGenerator ?? IdGenerator(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final String userId;
  final CapturesRepository captures;
  final TasksRepository tasks;
  final NotesRepository notes;
  final HabitsRepository habits;
  final GoalsRepository goals;
  final EventEmitter emitter;
  final NativeCaptureApi nativeApi;
  final Future<PendingAudioQueue> pendingQueue;
  final CaptureIngestionBarrier barrier;
  final AppDatabase db;
  final IdGenerator idGenerator;
  final Duration autoCommitUndoWindow;
  final DateTime Function() _clock;
  final Map<String, Future<CaptureTriageResult>> _saving =
      <String, Future<CaptureTriageResult>>{};
  final Map<String, Future<List<CaptureTriageResult>>> _bulkSaving =
      <String, Future<List<CaptureTriageResult>>>{};

  Future<CaptureTriageResult> save(String captureId, CaptureTriageDraft draft) {
    final Future<CaptureTriageResult>? existing = _saving[captureId];
    if (existing != null) return existing;
    final Future<CaptureTriageResult> future = _saveWithLease(captureId, draft);
    _saving[captureId] = future;
    void clear() {
      if (identical(_saving[captureId], future)) _saving.remove(captureId);
    }

    unawaited(future.then<void>((_) => clear(), onError: (_, _) => clear()));
    return future;
  }

  /// Bulk materialisation for the N-item flow (docs/CAPTURE_DECOMPOSITION.md §6
  /// manual "Save all"; §12.4 auto-commit). Materialises every survivor draft
  /// into its real typed row — idempotently, keyed on each draft's stable client
  /// id ([ProposedItem.id]) — then flips the capture to `triaged`. Re-running is
  /// safe: existing child rows are returned, not duplicated.
  ///
  /// [items] is treated as the COMPLETE disposition of the capture (provided =
  /// saved, omitted = dropped), so the capture becomes terminal once this
  /// returns. [autoCommitted] records whether this ran without user review, for
  /// the `capture_triaged` audit event the notification / inbox strip read.
  Future<List<CaptureTriageResult>> saveAll(
    String captureId,
    List<ProposedItem> items, {
    Set<String> droppedItemIds = const <String>{},
    List<ProposedItem>? editedItems,
    bool autoCommitted = false,
  }) {
    final Future<List<CaptureTriageResult>>? existing = _bulkSaving[captureId];
    if (existing != null) return existing;
    final Future<List<CaptureTriageResult>> future = _saveAllWithLease(
      captureId,
      items,
      droppedItemIds: droppedItemIds,
      editedItems: editedItems,
      autoCommitted: autoCommitted,
    );
    _bulkSaving[captureId] = future;
    void clear() {
      if (identical(_bulkSaving[captureId], future)) {
        _bulkSaving.remove(captureId);
      }
    }

    unawaited(future.then<void>((_) => clear(), onError: (_, _) => clear()));
    return future;
  }

  Future<List<CaptureTriageResult>> _saveAllWithLease(
    String captureId,
    List<ProposedItem> items, {
    required Set<String> droppedItemIds,
    required List<ProposedItem>? editedItems,
    required bool autoCommitted,
  }) async {
    final CaptureIngestionLease lease = barrier.enter();
    try {
      final ({
        Capture capture,
        List<CaptureTriageResult> results,
        List<ProposedItem> auditItems,
        bool terminal,
      })
      committed = await db.transaction(() async {
        final Capture capture = await _capture(captureId);
        final List<ProposedItem> allEdits = editedItems ?? items;
        if (items.any((item) => item.title.trim().isEmpty) ||
            allEdits.any((item) => item.title.trim().isEmpty)) {
          throw ArgumentError('Every draft title is required.');
        }
        final Set<String> disposed = capture.dispositionedItemIds.toSet();
        final List<CaptureTriageResult> results = <CaptureTriageResult>[];
        for (final ProposedItem item in items) {
          if (!disposed.contains(item.id)) {
            results.add(await _materialize(capture, item));
            disposed.add(item.id);
          } else {
            results.add(CaptureTriageResult(type: item.kind, id: item.id));
          }
        }
        disposed.addAll(droppedItemIds);
        final List<ProposedItem> source = capture.proposedItems ?? items;
        final Set<String> sourceIds = source.map((item) => item.id).toSet();
        if (capture.proposedItems != null &&
            (items.any((item) => !sourceIds.contains(item.id)) ||
                droppedItemIds.any((id) => !sourceIds.contains(id)) ||
                (editedItems?.any((item) => !sourceIds.contains(item.id)) ??
                    false))) {
          throw ArgumentError('Disposition contains an unknown draft id.');
        }
        final Map<String, ProposedItem> edits = <String, ProposedItem>{
          for (final ProposedItem item in allEdits) item.id: item,
        };
        final List<ProposedItem> updatedSource = <ProposedItem>[
          for (final ProposedItem item in source) edits[item.id] ?? item,
        ];
        final bool terminal = source.every(
          (ProposedItem item) => disposed.contains(item.id),
        );
        // Any manual non-terminal save means the remaining drafts have entered
        // review and must never be mistaken for an interrupted automatic
        // checkpoint. Persist that durable intent in the existing confidence
        // contract; low drafts are structurally ineligible on every restart.
        final List<ProposedItem> persistedSource = !autoCommitted && !terminal
            ? <ProposedItem>[
                for (final ProposedItem item in updatedSource)
                  disposed.contains(item.id)
                      ? item
                      : item.copyWith(confidence: DraftConfidence.low),
              ]
            : updatedSource;
        await captures.update(
          capture.copyWith(
            status: terminal ? CaptureStatus.triaged : CaptureStatus.ready,
            proposedItems: persistedSource,
            dispositionedItemIds: disposed.toList(growable: false),
            autoCommittedAt: autoCommitted && terminal ? _clock() : null,
          ),
        );
        return (
          capture: capture,
          results: results,
          auditItems: persistedSource,
          terminal: terminal,
        );
      });
      final Capture capture = committed.capture;
      final List<CaptureTriageResult> results = committed.results;
      final List<ProposedItem> auditItems = committed.auditItems;
      if (committed.terminal && capture.status != CaptureStatus.triaged) {
        emitter.emit(
          userId: userId,
          eventType: 'capture_triaged',
          entityType: EntityTypes.capture,
          entityId: capture.id,
          metadata: <String, Object?>{
            'mode': autoCommitted ? 'auto' : 'bulk',
            'item_count': auditItems.length,
            'kinds': auditItems
                .map((ProposedItem item) => item.kind.wire)
                .toList(growable: false),
            'latency_ms': _clock()
                .difference(capture.capturedAt)
                .inMilliseconds,
          },
        );
      }
      if (committed.terminal) await _releaseAudio(capture);
      return results;
    } finally {
      lease.close();
    }
  }

  Future<CaptureTriageResult> _materialize(
    Capture capture,
    ProposedItem item,
  ) async {
    final String title = item.title.trim();
    final String? details = item.details?.trim();
    final String id = switch (item.kind) {
      ResultingType.task => (await _tasksLinked().createForCapture(
        captureId: capture.id,
        id: item.id,
        title: title,
        details: details,
        scheduledAt: item.scheduledAt,
      )).id,
      ResultingType.note => (await _notesLinked().createForCapture(
        captureId: capture.id,
        id: item.id,
        title: title,
        body: details,
      )).id,
      ResultingType.habit => (await _habitsLinked().createForCapture(
        captureId: capture.id,
        id: item.id,
        title: title,
        anchorDescription: item.anchor ?? details,
        levelConfig: <String, Object?>{
          'suggested_level': (item.level ?? HabitLevel.mini).wire,
        },
        frequencyConfig: item.cadence,
      )).id,
      ResultingType.goal => (await _goalsLinked().createForCapture(
        captureId: capture.id,
        id: item.id,
        title: title,
        why: item.why ?? details,
        targetDate: item.targetDate,
      )).id,
    };
    return CaptureTriageResult(type: item.kind, id: id);
  }

  CaptureLinkedTasksRepository _tasksLinked() {
    final TasksRepository repository = tasks;
    if (repository is! CaptureLinkedTasksRepository) {
      throw StateError('Tasks repository does not support idempotent triage.');
    }
    return repository as CaptureLinkedTasksRepository;
  }

  CaptureLinkedNotesRepository _notesLinked() {
    final NotesRepository repository = notes;
    if (repository is! CaptureLinkedNotesRepository) {
      throw StateError('Notes repository does not support idempotent triage.');
    }
    return repository as CaptureLinkedNotesRepository;
  }

  CaptureLinkedHabitsRepository _habitsLinked() {
    final HabitsRepository repository = habits;
    if (repository is! CaptureLinkedHabitsRepository) {
      throw StateError('Habits repository does not support idempotent triage.');
    }
    return repository as CaptureLinkedHabitsRepository;
  }

  CaptureLinkedGoalsRepository _goalsLinked() {
    final GoalsRepository repository = goals;
    if (repository is! CaptureLinkedGoalsRepository) {
      throw StateError('Goals repository does not support idempotent triage.');
    }
    return repository as CaptureLinkedGoalsRepository;
  }

  Future<CaptureTriageResult> _saveWithLease(
    String captureId,
    CaptureTriageDraft draft,
  ) async {
    final CaptureIngestionLease lease = barrier.enter();
    try {
      return await _save(captureId, draft);
    } finally {
      lease.close();
    }
  }

  Future<CaptureTriageResult> _save(
    String captureId,
    CaptureTriageDraft draft,
  ) async {
    final Capture capture = await _capture(captureId);
    if (capture.status == CaptureStatus.triaged &&
        capture.resultingType != null &&
        capture.resultingId != null) {
      await _releaseAudio(capture);
      return CaptureTriageResult(
        type: capture.resultingType!,
        id: capture.resultingId!,
      );
    }
    final String title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError.value(title, 'title', 'is required');

    final String resultingId = switch (draft.type) {
      ResultingType.task => await _saveTask(capture, draft),
      ResultingType.note => await _saveNote(capture, draft),
      ResultingType.habit => await _saveHabit(capture, draft),
      ResultingType.goal => await _saveGoal(capture, draft),
    };
    await captures.update(
      capture.copyWith(
        title: title,
        details: draft.details.trim(),
        status: CaptureStatus.triaged,
        resultingType: draft.type,
        resultingId: resultingId,
      ),
    );
    emitter.emit(
      userId: userId,
      eventType: 'capture_triaged',
      entityType: EntityTypes.capture,
      entityId: capture.id,
      metadata: <String, Object?>{
        'resulting_type': draft.type.wire,
        'latency_ms': _clock().difference(capture.capturedAt).inMilliseconds,
      },
    );
    await _releaseAudio(capture);
    return CaptureTriageResult(type: draft.type, id: resultingId);
  }

  Future<void> discard(String captureId) async {
    final CaptureIngestionLease lease = barrier.enter();
    try {
      final Capture capture = await _capture(captureId);
      if (capture.status == CaptureStatus.discarded) {
        await _releaseAudio(capture);
        return;
      }
      // The terminal row is durable before the native journal is acknowledged.
      // If the process dies between these writes, ingestion recognizes the
      // terminal row by audio path and safely completes acknowledgement.
      await captures.update(capture.copyWith(status: CaptureStatus.discarded));
      emitter.emit(
        userId: userId,
        eventType: 'capture_discarded',
        entityType: EntityTypes.capture,
        entityId: capture.id,
      );
      await _releaseAudio(capture);
    } finally {
      lease.close();
    }
  }

  /// Reverses an auto-commit (docs/CAPTURE_DECOMPOSITION.md §12.5 Undo). Every
  /// child row materialised from this capture's drafts is soft-deleted (keyed by
  /// the stable draft id, which is the child's id), and the capture returns to
  /// `ready` so it re-enters the inbox for review.
  ///
  /// The surviving drafts are RE-STAMPED with fresh ids before the capture is
  /// persisted: a soft-delete only tombstones a row (so the deletion propagates
  /// through sync), and [createForCapture] uses `insertOrIgnore`, so re-saving
  /// under the OLD ids would silently no-op against the tombstones and never
  /// resurrect the items. They are also downgraded to low confidence: Undo is
  /// an explicit rejection of automatic handling, and this durable marker keeps
  /// startup recovery from mistaking the reopened capture for an interrupted
  /// eligible checkpoint and auto-creating the tasks again.
  Future<void> undoAutoCommit(String captureId) async {
    final CaptureIngestionLease lease = barrier.enter();
    try {
      final ({String captureId, int itemCount}) undone = await db.transaction(
        () async {
          final Capture capture = await _capture(captureId);
          final DateTime? committedAt = capture.autoCommittedAt;
          if (capture.status != CaptureStatus.triaged ||
              committedAt == null ||
              _clock().difference(committedAt) > autoCommitUndoWindow) {
            throw StateError('The auto-commit Undo window has expired.');
          }
          final List<ProposedItem> drafts =
              capture.proposedItems ?? const <ProposedItem>[];
          for (final ProposedItem item in drafts) {
            switch (item.kind) {
              case ResultingType.task:
                await tasks.delete(item.id);
              case ResultingType.note:
                await notes.delete(item.id);
              case ResultingType.habit:
                await habits.delete(item.id);
              case ResultingType.goal:
                await goals.delete(item.id);
            }
          }
          final List<ProposedItem> reissued = <ProposedItem>[
            for (final ProposedItem item in drafts)
              item
                  .withId(idGenerator.v4())
                  .copyWith(confidence: DraftConfidence.low),
          ];
          await captures.update(
            capture.copyWith(
              proposedItems: reissued,
              dispositionedItemIds: const <String>[],
              status: CaptureStatus.ready,
              clearAutoCommittedAt: true,
            ),
          );
          return (captureId: capture.id, itemCount: drafts.length);
        },
      );
      emitter.emit(
        userId: userId,
        eventType: 'capture_auto_commit_undone',
        entityType: EntityTypes.capture,
        entityId: undone.captureId,
        metadata: <String, Object?>{'item_count': undone.itemCount},
      );
    } finally {
      lease.close();
    }
  }

  /// Hides the durable recovery receipt after the user has inspected/accepted
  /// the created records. It never deletes or rewrites those records.
  Future<void> acknowledgeAutoCommit(String captureId) async {
    final Capture capture = await _capture(captureId);
    if (capture.autoCommittedAt == null) return;
    await captures.update(capture.copyWith(clearAutoCommittedAt: true));
  }

  Future<String> _saveTask(Capture capture, CaptureTriageDraft draft) async {
    final List<Task> existing = await tasks.watchAll().first;
    for (final Task task in existing) {
      if (task.captureId == capture.id) return task.id;
    }
    final TasksRepository repository = tasks;
    if (repository is! CaptureLinkedTasksRepository) {
      throw StateError('Tasks repository does not support idempotent triage.');
    }
    return (await (repository as CaptureLinkedTasksRepository).createForCapture(
      captureId: capture.id,
      title: draft.title.trim(),
      details: draft.details.trim(),
      scheduledAt: draft.scheduledAt,
    )).id;
  }

  Future<String> _saveNote(Capture capture, CaptureTriageDraft draft) async {
    final List<Note> existing = await notes.watchAll().first;
    for (final Note note in existing) {
      if (note.captureId == capture.id) return note.id;
    }
    final NotesRepository repository = notes;
    if (repository is! CaptureLinkedNotesRepository) {
      throw StateError('Notes repository does not support idempotent triage.');
    }
    return (await (repository as CaptureLinkedNotesRepository).createForCapture(
      captureId: capture.id,
      title: draft.title.trim(),
      body: draft.details.trim(),
    )).id;
  }

  Future<String> _saveHabit(Capture capture, CaptureTriageDraft draft) async {
    final List<Habit> existing = await habits.watchAll().first;
    for (final Habit habit in existing) {
      if (habit.captureId == capture.id) return habit.id;
    }
    final HabitsRepository repository = habits;
    if (repository is! CaptureLinkedHabitsRepository) {
      throw StateError('Habits repository does not support idempotent triage.');
    }
    return (await (repository as CaptureLinkedHabitsRepository)
            .createForCapture(
              captureId: capture.id,
              title: draft.title.trim(),
              anchorDescription: draft.details.trim(),
              levelConfig: <String, Object?>{
                'suggested_level': draft.habitLevel.wire,
              },
            ))
        .id;
  }

  Future<String> _saveGoal(Capture capture, CaptureTriageDraft draft) async {
    final List<Goal> existing = await goals.watchAll().first;
    for (final Goal goal in existing) {
      if (goal.captureId == capture.id) return goal.id;
    }
    return (await _goalsLinked().createForCapture(
      captureId: capture.id,
      title: draft.title.trim(),
      why: draft.details.trim().isEmpty ? null : draft.details.trim(),
    )).id;
  }

  Future<Capture> _capture(String id) async {
    final List<Capture> rows = await captures.getByIds(<String>[id]);
    if (rows.isEmpty) throw StateError('Capture $id no longer exists.');
    return rows.single;
  }

  Future<void> _releaseAudio(Capture capture) async {
    await _acknowledgeNative(capture);
    await _removeQueuedFile(capture);
  }

  Future<void> _acknowledgeNative(Capture capture) async {
    final String? path = capture.audioPath;
    if (path == null) return;
    final pending = await nativeApi.pendingEvents(userId);
    for (final event in pending) {
      if (event.audioPath == path) await nativeApi.acknowledge(event.eventId);
    }
  }

  Future<void> _removeQueuedFile(Capture capture) async {
    final String? path = capture.audioPath;
    if (path == null) return;
    await (await pendingQueue).remove(p.basename(path));
  }
}

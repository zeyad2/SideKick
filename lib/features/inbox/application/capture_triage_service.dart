import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sidekick/core/audio/pending_audio_queue.dart';
import 'package:sidekick/core/capture/capture_ingestion_barrier.dart';
import 'package:sidekick/core/capture/native_capture_api.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/core/events/event_emitter.dart';
import 'package:sidekick/features/habits/domain/habit.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/notes/domain/note.dart';
import 'package:sidekick/features/tasks/domain/task.dart';

class CaptureTriageDraft {
  const CaptureTriageDraft({
    required this.type,
    required this.title,
    required this.details,
    this.scheduledAt,
    this.habitLevel = HabitLevel.normal,
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
    required this.emitter,
    required this.nativeApi,
    required this.pendingQueue,
    required this.barrier,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final String userId;
  final CapturesRepository captures;
  final TasksRepository tasks;
  final NotesRepository notes;
  final HabitsRepository habits;
  final EventEmitter emitter;
  final NativeCaptureApi nativeApi;
  final Future<PendingAudioQueue> pendingQueue;
  final CaptureIngestionBarrier barrier;
  final DateTime Function() _clock;
  final Map<String, Future<CaptureTriageResult>> _saving =
      <String, Future<CaptureTriageResult>>{};

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

import 'dart:async';
import 'dart:io';

import 'package:sidekick/core/capture/capture_contract.dart';
import 'package:sidekick/core/capture/capture_ingestion_barrier.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/sync/connectivity_service.dart';
import 'package:sidekick/features/inbox/data/gemini_client.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/inbox/domain/capture_analysis.dart';

/// Durable P4 worker. A failed API call changes only the row status; native
/// journal ownership and the audio file remain intact for the next retry.
class CaptureProcessingService {
  CaptureProcessingService({
    required this.captures,
    required this.gemini,
    required this.connectivity,
    required this.barrier,
    this.baseRetryDelay = const Duration(seconds: 30),
  });

  final CapturesRepository captures;
  final GeminiClient gemini;
  final ConnectivityService connectivity;
  final CaptureIngestionBarrier barrier;
  final Duration baseRetryDelay;

  final Set<String> _inFlight = <String>{};
  final Map<String, int> _attempts = <String, int>{};
  StreamSubscription<CapturedAudioEvent>? _captureSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _retryTimer;
  bool _disposed = false;

  Future<void> start(Stream<CapturedAudioEvent> captureEvents) async {
    _captureSubscription = captureEvents.listen(
      (CapturedAudioEvent event) => unawaited(processById(event.captureRowId)),
    );
    _connectivitySubscription = connectivity.onConnectedChanged.listen((
      bool connected,
    ) {
      if (connected) unawaited(retryNow());
    });
    await retryNow();
  }

  Future<void> retryNow() async {
    if (_disposed) return;
    _retryTimer?.cancel();
    final List<Capture> queued = await captures.watchByStatuses(<CaptureStatus>{
      CaptureStatus.pending,
      CaptureStatus.processing,
      CaptureStatus.failed,
    }).first;
    for (final Capture capture in queued.reversed) {
      await processById(capture.id);
    }
  }

  Future<void> processById(String captureId) async {
    if (_disposed || !_inFlight.add(captureId)) return;
    CaptureIngestionLease? lease;
    try {
      try {
        lease = barrier.enter();
      } on StateError {
        return;
      }
      final List<Capture> rows = await captures.getByIds(<String>[captureId]);
      if (rows.isEmpty) return;
      Capture capture = rows.single;
      if (capture.status == CaptureStatus.ready ||
          capture.status == CaptureStatus.triaged ||
          capture.status == CaptureStatus.discarded) {
        return;
      }
      final CapturesRepository repository = captures;
      if (repository is! CaptureProcessingTransitions) {
        throw StateError(
          'Captures repository does not support atomic processing transitions.',
        );
      }
      final CaptureProcessingTransitions transitions =
          repository as CaptureProcessingTransitions;
      final Capture? claimed = await transitions.beginProcessing(captureId);
      if (claimed == null) return;
      capture = claimed;
      final String? audioPath = capture.audioPath;
      if (audioPath == null || !File(audioPath).existsSync()) {
        final bool failed = await transitions.finishProcessing(
          capture.copyWith(status: CaptureStatus.failed),
        );
        if (failed) _scheduleRetry(captureId);
        return;
      }
      final CaptureAnalysis analysis = await gemini.analyzeCaptureAudio(
        File(audioPath),
      );
      final bool completed = await transitions.finishProcessing(
        capture.copyWith(
          rawTranscript: analysis.rawTranscript,
          llmType: analysis.type,
          title: analysis.title,
          details: analysis.details,
          suggestedSchedule: analysis.suggestedSchedule,
          status: CaptureStatus.ready,
        ),
      );
      if (completed) _attempts.remove(captureId);
    } catch (_) {
      final List<Capture> rows = await captures.getByIds(<String>[captureId]);
      bool failed = false;
      if (rows.isNotEmpty && rows.single.status == CaptureStatus.processing) {
        final CapturesRepository repository = captures;
        if (repository is CaptureProcessingTransitions) {
          failed = await (repository as CaptureProcessingTransitions)
              .finishProcessing(
                rows.single.copyWith(status: CaptureStatus.failed),
              );
        }
      }
      if (failed) _scheduleRetry(captureId);
    } finally {
      lease?.close();
      _inFlight.remove(captureId);
    }
  }

  void _scheduleRetry(String captureId) {
    if (_disposed) return;
    final int attempt = (_attempts[captureId] ?? 0) + 1;
    _attempts[captureId] = attempt;
    final int multiplier = 1 << (attempt - 1).clamp(0, 5);
    final Duration delay = baseRetryDelay * multiplier;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(retryNow()));
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    await _captureSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    while (_inFlight.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}

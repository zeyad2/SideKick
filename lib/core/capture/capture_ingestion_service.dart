import 'dart:async';

import 'package:sidekick/core/capture/capture_contract.dart';
import 'package:sidekick/core/capture/capture_ingestion_barrier.dart';
import 'package:sidekick/core/capture/native_capture_api.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';

/// The only bridge from native capture persistence into the frozen P2 data layer.
class CaptureIngestionService {
  CaptureIngestionService({
    required this.repository,
    required this.nativeApi,
    required this.ownerId,
    required this.barrier,
  });

  final CapturesRepository repository;
  final NativeCaptureApi nativeApi;
  final String ownerId;
  final CaptureIngestionBarrier barrier;
  final StreamController<CapturedAudioEvent> _events =
      StreamController<CapturedAudioEvent>.broadcast();
  final Map<String, Future<CapturedAudioEvent>> _inFlight =
      <String, Future<CapturedAudioEvent>>{};

  Stream<CapturedAudioEvent> get events => _events.stream;

  Future<CapturedAudioEvent> ingest(
    NativeCapturedAudio native, {
    String source = 'shortcut',
  }) {
    if (native.ownerId != ownerId) {
      return Future<CapturedAudioEvent>.error(
        StateError('Capture owner does not match the active repository.'),
      );
    }
    final Future<CapturedAudioEvent>? existing = _inFlight[native.eventId];
    if (existing != null) return existing;
    final Future<CapturedAudioEvent> future = _ingest(native, source: source);
    _inFlight[native.eventId] = future;
    void clear() {
      if (identical(_inFlight[native.eventId], future)) {
        _inFlight.remove(native.eventId);
      }
    }

    unawaited(future.then<void>((_) => clear(), onError: (_, _) => clear()));
    return future;
  }

  Future<CapturedAudioEvent> _ingest(
    NativeCapturedAudio native, {
    required String source,
  }) async {
    final CaptureIngestionLease lease = barrier.enter();
    try {
      final Capture? existing;
      final CapturesRepository captures = repository;
      if (captures is CaptureReplayLookup) {
        existing = await (captures as CaptureReplayLookup).findByAudioPath(
          native.audioPath,
        );
      } else {
        final List<Capture> current = await repository.watchAll().first;
        existing = current.cast<Capture?>().firstWhere(
          (Capture? capture) => capture?.audioPath == native.audioPath,
          orElse: () => null,
        );
      }
      final Capture capture =
          existing ??
          await repository.create(
            audioPath: native.audioPath,
            capturedAt: native.capturedAt,
            source: source,
          );
      // The native journal remains the durable owner through P3. P4 acknowledges
      // only after the capture has safely completed its offline processing path.
      final CapturedAudioEvent event = CapturedAudioEvent(
        audioFilePath: native.audioPath,
        captureRowId: capture.id,
      );
      _events.add(event);
      if (existing != null &&
          (capture.status == CaptureStatus.triaged ||
              capture.status == CaptureStatus.discarded)) {
        await nativeApi.acknowledge(native.eventId);
      }
      return event;
    } finally {
      lease.close();
    }
  }

  Future<void> dispose() async {
    await Future.wait<CapturedAudioEvent>(
      _inFlight.values,
      eagerError: false,
    ).catchError((_) => <CapturedAudioEvent>[]);
    await _events.close();
  }
}

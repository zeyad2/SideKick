import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sidekick/core/capture/capture_contract.dart';
import 'package:sidekick/core/capture/capture_ingestion_service.dart';
import 'package:sidekick/core/capture/native_capture_api.dart';
import 'package:sidekick/features/profile/domain/profile.dart';

enum CaptureOverlayStage { hidden, recording, processing, failed }

@immutable
class CaptureOverlayState {
  const CaptureOverlayState({
    this.stage = CaptureOverlayStage.hidden,
    this.startedAt,
    this.amplitude = 0,
    this.processingStep = 0,
    this.errorCode,
  });

  final CaptureOverlayStage stage;
  final DateTime? startedAt;
  final int amplitude;
  final int processingStep;
  final String? errorCode;
}

class CaptureCoordinator {
  CaptureCoordinator({
    required this.nativeApi,
    required this.ingestion,
    required this.profileRepository,
    required this.userId,
  });

  final NativeCaptureApi nativeApi;
  final CaptureIngestionService ingestion;
  final ProfileRepository profileRepository;
  final String userId;
  final StreamController<CaptureOverlayState> _states =
      StreamController<CaptureOverlayState>.broadcast();
  StreamSubscription<NativeCaptureSignal>? _nativeSubscription;
  Timer? _processingTimer;
  final Map<String, Future<void>> _persisting = <String, Future<void>>{};
  CaptureOverlayState _state = const CaptureOverlayState();

  CaptureOverlayState get currentState => _state;
  Stream<CaptureOverlayState> get states async* {
    yield _state;
    yield* _states.stream;
  }

  Stream<CapturedAudioEvent> get capturedAudioEvents => ingestion.events;

  Future<void> initialize() async {
    await nativeApi.initialize();
    _nativeSubscription = nativeApi.signals.listen(_handleSignal);
    await nativeApi.setOwner(userId);
    await nativeApi.retryFailed(userId);
    final Profile profile = await profileRepository.ensureExists();
    await nativeApi.configureTrigger(
      CaptureTriggerConfig.fromPrefs(profile.prefs),
    );
    if (await nativeApi.isRecording(userId)) {
      _emit(
        CaptureOverlayState(
          stage: CaptureOverlayStage.recording,
          startedAt: DateTime.now(),
        ),
      );
    }
    for (final NativeCapturedAudio event in await nativeApi.pendingEvents(
      userId,
    )) {
      await _persist(event);
    }
  }

  Future<void> startCapture() => nativeApi.startCapture();
  Future<void> stopCapture() => nativeApi.stopCapture();

  void dismissError() => _emit(const CaptureOverlayState());

  void _handleSignal(NativeCaptureSignal signal) {
    switch (signal) {
      case NativeRecordingStarted(:final capture):
        if (capture.ownerId != userId) return;
        _processingTimer?.cancel();
        _emit(
          CaptureOverlayState(
            stage: CaptureOverlayStage.recording,
            startedAt: capture.capturedAt.toLocal(),
          ),
        );
      case NativeRecordingLevel(:final amplitude):
        if (_state.stage == CaptureOverlayStage.recording) {
          _emit(
            CaptureOverlayState(
              stage: _state.stage,
              startedAt: _state.startedAt,
              amplitude: amplitude,
            ),
          );
        }
      case NativeCaptureSaved(:final capture):
        if (capture.ownerId != userId) return;
        unawaited(_persist(capture));
      case NativeCaptureFailed(:final code):
        _emit(
          CaptureOverlayState(
            stage: CaptureOverlayStage.failed,
            errorCode: code,
          ),
        );
    }
  }

  Future<void> _persist(NativeCapturedAudio event) {
    final Future<void>? existing = _persisting[event.eventId];
    if (existing != null) return existing;
    final Future<void> future = _persistOnce(event);
    _persisting[event.eventId] = future;
    unawaited(
      future.then<void>(
        (_) => _persisting.remove(event.eventId),
        onError: (_, _) => _persisting.remove(event.eventId),
      ),
    );
    return future;
  }

  Future<void> _persistOnce(NativeCapturedAudio event) async {
    _processingTimer?.cancel();
    _emit(const CaptureOverlayState(stage: CaptureOverlayStage.processing));
    try {
      await ingestion.ingest(event);
      var step = 0;
      _processingTimer = Timer.periodic(const Duration(milliseconds: 850), (
        Timer timer,
      ) {
        step += 1;
        if (step >= 3) {
          timer.cancel();
          _emit(const CaptureOverlayState());
        } else {
          _emit(
            CaptureOverlayState(
              stage: CaptureOverlayStage.processing,
              processingStep: step,
            ),
          );
        }
      });
    } catch (error) {
      _emit(
        CaptureOverlayState(
          stage: CaptureOverlayStage.failed,
          errorCode: error.runtimeType.toString(),
        ),
      );
    }
  }

  void _emit(CaptureOverlayState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  Future<void> dispose() async {
    _processingTimer?.cancel();
    await _nativeSubscription?.cancel();
    await ingestion.dispose();
    await _states.close();
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sidekick/core/capture/capture_contract.dart';

sealed class NativeCaptureSignal {
  const NativeCaptureSignal();
}

final class NativeRecordingStarted extends NativeCaptureSignal {
  const NativeRecordingStarted(this.capture);
  final NativeCapturedAudio capture;
}

final class NativeRecordingLevel extends NativeCaptureSignal {
  const NativeRecordingLevel(this.amplitude);
  final int amplitude;
}

final class NativeCaptureSaved extends NativeCaptureSignal {
  const NativeCaptureSaved(this.capture);
  final NativeCapturedAudio capture;
}

final class NativeCaptureFailed extends NativeCaptureSignal {
  const NativeCaptureFailed(this.code);
  final String code;
}

abstract interface class NativeCaptureApi {
  Stream<NativeCaptureSignal> get signals;
  Future<void> initialize();
  Future<void> setOwner(String? ownerId);
  Future<void> configureTrigger(CaptureTriggerConfig config);
  Future<List<NativeCapturedAudio>> pendingEvents(String ownerId);
  Future<List<NativeCapturedAudio>> retryFailed(String ownerId);
  Future<bool> isRecording(String ownerId);
  Future<void> acknowledge(String eventId);
  Future<void> startCapture();
  Future<void> stopCapture();
  Future<void> cancelCapture();
  Future<bool> isAccessibilityEnabled();
  Future<void> openAccessibilitySettings();
  Future<void> dispose();
}

class MethodChannelNativeCaptureApi implements NativeCaptureApi {
  MethodChannelNativeCaptureApi({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(captureMethodChannelName);

  final MethodChannel _channel;
  final StreamController<NativeCaptureSignal> _signals =
      StreamController<NativeCaptureSignal>.broadcast();
  bool _initialized = false;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  @override
  Stream<NativeCaptureSignal> get signals => _signals.stream;

  @override
  Future<void> initialize() async {
    if (_initialized || !_supported) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    final Map<Object?, Object?> arguments = call.arguments is Map
        ? Map<Object?, Object?>.from(call.arguments as Map)
        : const <Object?, Object?>{};
    switch (call.method) {
      case 'recordingStarted':
        _signals.add(
          NativeRecordingStarted(NativeCapturedAudio.fromMap(arguments)),
        );
      case 'recordingLevel':
        _signals.add(
          NativeRecordingLevel((arguments['amplitude'] as num?)?.toInt() ?? 0),
        );
      case 'captureSaved':
        _signals.add(
          NativeCaptureSaved(NativeCapturedAudio.fromMap(arguments)),
        );
      case 'captureError':
        _signals.add(
          NativeCaptureFailed(arguments['code'] as String? ?? 'unknown'),
        );
    }
    return null;
  }

  @override
  Future<void> configureTrigger(CaptureTriggerConfig config) async {
    if (_supported) {
      await _channel.invokeMethod<bool>(
        'configureTrigger',
        config.toMethodArguments(),
      );
    }
  }

  @override
  Future<void> setOwner(String? ownerId) async {
    if (_supported) {
      await _channel.invokeMethod<void>('setCaptureOwner', <String, Object?>{
        'ownerId': ownerId,
      });
    }
  }

  @override
  Future<List<NativeCapturedAudio>> pendingEvents(String ownerId) async {
    if (!_supported) return const <NativeCapturedAudio>[];
    final List<Object?> raw =
        await _channel.invokeListMethod<Object?>(
          'getPendingCaptureEvents',
          <String, Object?>{'ownerId': ownerId},
        ) ??
        const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(NativeCapturedAudio.fromMap)
        .toList(growable: false);
  }

  @override
  Future<List<NativeCapturedAudio>> retryFailed(String ownerId) async {
    if (!_supported) return const <NativeCapturedAudio>[];
    final List<Object?> raw =
        await _channel.invokeListMethod<Object?>(
          'retryFailedCaptures',
          <String, Object?>{'ownerId': ownerId},
        ) ??
        const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(NativeCapturedAudio.fromMap)
        .toList(growable: false);
  }

  @override
  Future<bool> isRecording(String ownerId) async {
    if (!_supported) return false;
    final Map<Object?, Object?>? state = await _channel
        .invokeMapMethod<Object?, Object?>('getCaptureState');
    final Object? active = state?['active'];
    return state?['isRecording'] == true &&
        active is Map<Object?, Object?> &&
        active['ownerId'] == ownerId;
  }

  @override
  Future<void> acknowledge(String eventId) async {
    if (_supported) {
      await _channel.invokeMethod<void>('ackCaptureEvent', <String, Object?>{
        'eventId': eventId,
      });
    }
  }

  @override
  Future<void> startCapture() async {
    if (_supported) await _channel.invokeMethod<void>('startCapture');
  }

  @override
  Future<void> stopCapture() async {
    if (_supported) await _channel.invokeMethod<void>('stopCapture');
  }

  @override
  Future<void> cancelCapture() async {
    if (_supported) await _channel.invokeMethod<void>('cancelCapture');
  }

  @override
  Future<bool> isAccessibilityEnabled() async => _supported
      ? await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false
      : false;

  @override
  Future<void> openAccessibilitySettings() async {
    if (_supported) {
      await _channel.invokeMethod<void>('openAccessibilitySettings');
    }
  }

  @override
  Future<void> dispose() async {
    if (_initialized) _channel.setMethodCallHandler(null);
    await _signals.close();
  }
}

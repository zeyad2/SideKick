import 'package:flutter/foundation.dart';

/// Frozen P3 handoff to P4 and later phases.
const String captureMethodChannelName = 'com.sidekick/capture';

@immutable
class CapturedAudioEvent {
  const CapturedAudioEvent({
    required this.nativeEventId,
    required this.audioFilePath,
    required this.captureRowId,
  });

  final String nativeEventId;
  final String audioFilePath;
  final String captureRowId;
}

@immutable
class NativeCapturedAudio {
  const NativeCapturedAudio({
    required this.eventId,
    required this.audioPath,
    required this.capturedAt,
    required this.ownerId,
  });

  factory NativeCapturedAudio.fromMap(Map<Object?, Object?> map) =>
      NativeCapturedAudio(
        eventId: map['eventId']! as String,
        audioPath: map['audioPath']! as String,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['capturedAtMs']! as num).toInt(),
          isUtc: true,
        ),
        ownerId: map['ownerId']! as String,
      );

  final String eventId;
  final String audioPath;
  final DateTime capturedAt;
  final String ownerId;
}

@immutable
class CaptureTriggerConfig {
  const CaptureTriggerConfig({
    this.key = 'volume_up',
    this.pressCount = 3,
    this.windowMs = 900,
  });

  factory CaptureTriggerConfig.fromPrefs(Map<String, Object?> prefs) {
    final Object? value = prefs['capture_trigger'];
    final Map<Object?, Object?> map = value is Map<Object?, Object?>
        ? value
        : const <Object?, Object?>{};
    return CaptureTriggerConfig(
      key: map['key'] == 'volume_down' ? 'volume_down' : 'volume_up',
      pressCount: ((map['press_count'] as num?)?.toInt() ?? 3).clamp(1, 5),
      windowMs: ((map['window_ms'] as num?)?.toInt() ?? 900).clamp(300, 2500),
    );
  }

  final String key;
  final int pressCount;
  final int windowMs;

  Map<String, Object?> toMethodArguments() => <String, Object?>{
    'key': key,
    'pressCount': pressCount,
    'windowMs': windowMs,
  };
}

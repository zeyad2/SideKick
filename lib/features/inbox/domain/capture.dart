import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';

@immutable
class Capture {
  const Capture({
    required this.id,
    required this.userId,
    required this.source,
    required this.status,
    required this.capturedAt,
    required this.createdAt,
    required this.updatedAt,
    this.inputText,
    this.audioPath,
    this.rawTranscript,
    this.error,
  });

  final String id;
  final String userId;
  final CaptureSource source;
  final String? inputText;
  final String? audioPath;
  final String? rawTranscript;
  final CaptureStatus status;
  final String? error;
  final DateTime capturedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Capture copyWith({
    CaptureSource? source,
    String? inputText,
    String? audioPath,
    String? rawTranscript,
    CaptureStatus? status,
    String? error,
  }) => Capture(
    id: id,
    userId: userId,
    source: source ?? this.source,
    inputText: inputText ?? this.inputText,
    audioPath: audioPath ?? this.audioPath,
    rawTranscript: rawTranscript ?? this.rawTranscript,
    status: status ?? this.status,
    error: error ?? this.error,
    capturedAt: capturedAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

abstract interface class CapturesRepository {
  Stream<List<Capture>> watchAll();
  Stream<List<Capture>> watchByStatuses(Set<CaptureStatus> statuses);
  Future<List<Capture>> getByIds(List<String> ids);
  Future<Capture> create({
    String? inputText,
    String? audioPath,
    DateTime? capturedAt,
    String source,
  });
  Future<void> update(Capture capture);
  Future<void> delete(String id);
}

abstract interface class CaptureReplayLookup {
  Future<Capture?> findByAudioPath(String audioPath);
}

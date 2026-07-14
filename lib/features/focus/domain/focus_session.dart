import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';

@immutable
class FocusSession {
  const FocusSession({
    required this.id,
    required this.userId,
    required this.durationMinutes,
    required this.startedAt,
    required this.status,
    required this.blockingEnabled,
    required this.blockingMode,
    required this.blockAttempts,
    required this.capturesDuring,
    required this.createdAt,
    required this.updatedAt,
    this.taskId,
    this.taskLabel,
    this.endedAt,
  });

  final String id;
  final String userId;
  final String? taskId;
  final String? taskLabel;
  final int durationMinutes;
  final DateTime startedAt;
  final DateTime? endedAt;
  final FocusSessionStatus status;
  final bool blockingEnabled;
  final BlockingMode blockingMode;
  final int blockAttempts;

  /// Ordered capture ids captured mid-session, surfaced after it ends (P7).
  final List<String> capturesDuring;
  final DateTime createdAt;
  final DateTime updatedAt;

  FocusSession copyWith({
    String? taskId,
    String? taskLabel,
    int? durationMinutes,
    DateTime? endedAt,
    FocusSessionStatus? status,
    bool? blockingEnabled,
    BlockingMode? blockingMode,
    int? blockAttempts,
    List<String>? capturesDuring,
  }) => FocusSession(
    id: id,
    userId: userId,
    taskId: taskId ?? this.taskId,
    taskLabel: taskLabel ?? this.taskLabel,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    status: status ?? this.status,
    blockingEnabled: blockingEnabled ?? this.blockingEnabled,
    blockingMode: blockingMode ?? this.blockingMode,
    blockAttempts: blockAttempts ?? this.blockAttempts,
    capturesDuring: capturesDuring ?? this.capturesDuring,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

abstract interface class FocusSessionsRepository {
  Stream<List<FocusSession>> watchAll();
  Stream<FocusSession?> watchById(String id);

  Future<FocusSession> create({
    required int durationMinutes,
    String? taskId,
    String? taskLabel,
    bool blockingEnabled,
    BlockingMode blockingMode,
  });

  /// Persist edits; emits `focus_session_status_changed` when status changes.
  Future<void> update(FocusSession session);
  Future<void> delete(String id);
}

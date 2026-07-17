import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';

@immutable
class Goal {
  const Goal({
    required this.id,
    required this.userId,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.why,
    this.targetDate,
  });

  final String id;
  final String userId;
  final String title;
  final String? why;
  final GoalStatus status;
  final DateTime? targetDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  Goal copyWith({
    String? title,
    String? why,
    GoalStatus? status,
    DateTime? targetDate,
  }) => Goal(
    id: id,
    userId: userId,
    title: title ?? this.title,
    why: why ?? this.why,
    status: status ?? this.status,
    targetDate: targetDate ?? this.targetDate,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

abstract interface class GoalsRepository {
  Stream<List<Goal>> watchAll();
  Stream<List<Goal>> watchByStatus(GoalStatus status);
  Future<Goal> create({
    required String title,
    String? why,
    DateTime? targetDate,
  });

  /// Persist edits; emits `goal_status_changed` when the status changes.
  Future<void> update(Goal goal);
  Future<void> delete(String id);
}

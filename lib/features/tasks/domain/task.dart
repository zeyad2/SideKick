import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';

@immutable
class Task {
  const Task({
    required this.id,
    required this.userId,
    required this.title,
    required this.status,
    required this.lastActivityAt,
    required this.createdAt,
    required this.updatedAt,
    this.captureId,
    this.goalId,
    this.details,
    this.nextAction,
    this.scheduledAt,
    this.completedAt,
  });

  final String id;
  final String userId;
  final String? captureId;
  final String? goalId;
  final String title;
  final String? details;
  final TaskStatus status;
  final String? nextAction;
  final DateTime? scheduledAt;
  final DateTime? completedAt;
  final DateTime lastActivityAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Task copyWith({
    String? goalId,
    String? title,
    String? details,
    TaskStatus? status,
    String? nextAction,
    DateTime? scheduledAt,
    DateTime? completedAt,
  }) => Task(
    id: id,
    userId: userId,
    captureId: captureId,
    goalId: goalId ?? this.goalId,
    title: title ?? this.title,
    details: details ?? this.details,
    status: status ?? this.status,
    nextAction: nextAction ?? this.nextAction,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    completedAt: completedAt ?? this.completedAt,
    lastActivityAt: lastActivityAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

abstract interface class TasksRepository {
  Stream<List<Task>> watchAll();
  Stream<List<Task>> watchByStatus(TaskStatus status);

  Future<Task> create({
    required String title,
    String? details,
    String? captureId,
    String? goalId,
    DateTime? scheduledAt,
  });

  /// Persist edits; bumps `last_activity_at` and emits `task_status_changed`
  /// when the status changes.
  Future<void> update(Task task);

  Future<void> delete(String id);
}

/// Additive P4 contract used to make capture triage idempotent without
/// changing the frozen P2 repository interface. The record is created with a
/// stable id and returns the existing row on replay. For the legacy 1:1 flow
/// that id is [captureId]; for the N-item decomposition flow (one rant → many
/// drafts) the caller passes the draft's stable client [id] so sibling drafts
/// from the same capture do not collide (docs/CAPTURE_DECOMPOSITION.md §11).
abstract interface class CaptureLinkedTasksRepository {
  Future<Task> createForCapture({
    required String captureId,
    required String title,
    String? id,
    String? details,
    DateTime? scheduledAt,
  });
}

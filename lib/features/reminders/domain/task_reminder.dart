import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';

@immutable
class TaskReminder {
  const TaskReminder({
    required this.id,
    required this.userId,
    required this.title,
    required this.status,
    required this.source,
    required this.confidence,
    required this.triggerType,
    required this.createdAt,
    required this.updatedAt,
    this.details,
    this.scheduledAt,
    this.placeId,
    this.geofenceTransition,
    this.dwellSeconds,
    this.autoCommitDeadlineAt,
    this.captureId,
    this.aiExplanation,
    this.aiContext,
  });

  final String id;
  final String userId;
  final String title;
  final String? details;
  final TaskReminderStatus status;
  final TaskReminderSource source;
  final double confidence;
  final TaskReminderTriggerType triggerType;
  final DateTime? scheduledAt;
  final String? placeId;
  final GeofenceTransition? geofenceTransition;
  final int? dwellSeconds;
  final DateTime? autoCommitDeadlineAt;
  final String? captureId;
  final String? aiExplanation;
  final Map<String, Object?>? aiContext;
  final DateTime createdAt;
  final DateTime updatedAt;

  TaskReminder copyWith({
    String? title,
    String? details,
    TaskReminderStatus? status,
    TaskReminderSource? source,
    double? confidence,
    TaskReminderTriggerType? triggerType,
    DateTime? scheduledAt,
    String? placeId,
    GeofenceTransition? geofenceTransition,
    int? dwellSeconds,
    DateTime? autoCommitDeadlineAt,
    String? captureId,
    String? aiExplanation,
    Map<String, Object?>? aiContext,
  }) => TaskReminder(
    id: id,
    userId: userId,
    title: title ?? this.title,
    details: details ?? this.details,
    status: status ?? this.status,
    source: source ?? this.source,
    confidence: confidence ?? this.confidence,
    triggerType: triggerType ?? this.triggerType,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    placeId: placeId ?? this.placeId,
    geofenceTransition: geofenceTransition ?? this.geofenceTransition,
    dwellSeconds: dwellSeconds ?? this.dwellSeconds,
    autoCommitDeadlineAt: autoCommitDeadlineAt ?? this.autoCommitDeadlineAt,
    captureId: captureId ?? this.captureId,
    aiExplanation: aiExplanation ?? this.aiExplanation,
    aiContext: aiContext ?? this.aiContext,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

abstract interface class TaskRemindersRepository {
  Stream<List<TaskReminder>> watchAll();
  Stream<List<TaskReminder>> watchByStatus(TaskReminderStatus status);
  Future<TaskReminder> create(TaskReminderDraft draft);
  Future<void> update(TaskReminder reminder);
  Future<void> delete(String id);
}

@immutable
class TaskReminderDraft {
  const TaskReminderDraft({
    required this.title,
    required this.source,
    required this.confidence,
    required this.triggerType,
    this.details,
    this.status = TaskReminderStatus.active,
    this.scheduledAt,
    this.placeId,
    this.geofenceTransition,
    this.dwellSeconds,
    this.autoCommitDeadlineAt,
    this.captureId,
    this.aiExplanation,
    this.aiContext,
  });

  final String title;
  final String? details;
  final TaskReminderStatus status;
  final TaskReminderSource source;
  final double confidence;
  final TaskReminderTriggerType triggerType;
  final DateTime? scheduledAt;
  final String? placeId;
  final GeofenceTransition? geofenceTransition;
  final int? dwellSeconds;
  final DateTime? autoCommitDeadlineAt;
  final String? captureId;
  final String? aiExplanation;
  final Map<String, Object?>? aiContext;
}

import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';

@immutable
class Reminder {
  const Reminder({
    required this.id,
    required this.userId,
    required this.reminderType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.taskId,
    this.habitId,
    this.scheduledAt,
    this.recurrence,
    this.snoozeUntil,
    this.placeId,
    this.geofenceTransition,
    this.dwellSeconds,
    this.copy,
  });

  final String id;
  final String userId;
  final ReminderType reminderType;
  final String? taskId;
  final String? habitId;
  final DateTime? scheduledAt;
  final Map<String, Object?>? recurrence;
  final DateTime? snoozeUntil;
  final String? placeId;
  final GeofenceTransition? geofenceTransition;
  final int? dwellSeconds;
  final String? copy;
  final ReminderStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Reminder copyWith({
    DateTime? scheduledAt,
    Map<String, Object?>? recurrence,
    DateTime? snoozeUntil,
    GeofenceTransition? geofenceTransition,
    int? dwellSeconds,
    String? copy,
    ReminderStatus? status,
  }) => Reminder(
    id: id,
    userId: userId,
    reminderType: reminderType,
    taskId: taskId,
    habitId: habitId,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    recurrence: recurrence ?? this.recurrence,
    snoozeUntil: snoozeUntil ?? this.snoozeUntil,
    placeId: placeId,
    geofenceTransition: geofenceTransition ?? this.geofenceTransition,
    dwellSeconds: dwellSeconds ?? this.dwellSeconds,
    copy: copy ?? this.copy,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

abstract interface class RemindersRepository {
  Stream<List<Reminder>> watchAll();

  /// Create a time-based reminder (P6).
  Future<Reminder> createTimeReminder({
    required DateTime scheduledAt,
    String? taskId,
    String? habitId,
    Map<String, Object?>? recurrence,
    String? copy,
  });

  /// Create a geofence reminder (P9).
  Future<Reminder> createGeofenceReminder({
    required String placeId,
    required GeofenceTransition transition,
    String? taskId,
    String? habitId,
    int dwellSeconds,
    String? copy,
  });

  /// Persist edits; emits `reminder_status_changed` when status changes.
  Future<void> update(Reminder reminder);
  Future<void> delete(String id);
}

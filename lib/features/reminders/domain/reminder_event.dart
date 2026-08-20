import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';

@immutable
class ReminderEvent {
  const ReminderEvent({
    required this.id,
    required this.userId,
    required this.reminderId,
    required this.eventType,
    required this.metadata,
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String reminderId;
  final ReminderEventType eventType;
  final Map<String, Object?> metadata;
  final DateTime occurredAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

abstract interface class ReminderEventsRepository {
  Future<ReminderEvent> append({
    required String reminderId,
    required ReminderEventType eventType,
    Map<String, Object?> metadata,
    String? id,
  });

  Stream<List<ReminderEvent>> watchForReminder(String reminderId);
}

import 'package:meta/meta.dart';

/// An immutable behavioural event (D9). Rows are only ever appended — never
/// updated or deleted by app code. See docs/EVENTS.md for the taxonomy and the
/// write-now / read-later contract.
@immutable
class DomainEvent {
  const DomainEvent({
    required this.id,
    required this.userId,
    required this.eventType,
    required this.occurredAt,
    this.entityType,
    this.entityId,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String userId;
  final String eventType;
  final String? entityType;
  final String? entityId;
  final Map<String, Object?> metadata;
  final DateTime occurredAt;
}

/// The `entity_type` breadcrumb values (loose polymorphic link, no FK).
abstract final class EntityTypes {
  static const String capture = 'capture';
  static const String task = 'task';
  static const String note = 'note';
  static const String goal = 'goal';
  static const String habit = 'habit';
  static const String habitCompletion = 'habit_completion';
  static const String place = 'place';
  static const String focusSession = 'focus_session';
  static const String vibeCheck = 'vibe_check';
  static const String reminder = 'reminder';
  static const String blockListEntry = 'block_list';
}

/// Generic STRUCTURAL event types emitted by the P2 repository layer itself.
/// Feature phases add the *semantic* types (see docs/EVENTS.md); these are the
/// two the generic layer owns.
abstract final class StructuralEventSuffix {
  static const String created = '_created';
  static const String statusChanged = '_status_changed';

  static String createdFor(String entityType) => '$entityType$created';
  static String statusChangedFor(String entityType) =>
      '$entityType$statusChanged';
}

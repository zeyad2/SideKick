import 'package:meta/meta.dart';

@immutable
class Habit {
  const Habit({
    required this.id,
    required this.userId,
    required this.title,
    required this.resetActive,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
    this.captureId,
    this.goalId,
    this.frequencyConfig,
    this.levelConfig,
    this.anchorDescription,
    this.resetStartedAt,
  });

  final String id;
  final String userId;
  final String? captureId;
  final String? goalId;
  final String title;
  final Map<String, Object?>? frequencyConfig;
  final Map<String, Object?>? levelConfig;
  final String? anchorDescription;

  /// Fresh Start (P5): a shame-free 3-day Mini reset run is in progress.
  final bool resetActive;
  final DateTime? resetStartedAt;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  Habit copyWith({
    String? goalId,
    String? title,
    Map<String, Object?>? frequencyConfig,
    Map<String, Object?>? levelConfig,
    String? anchorDescription,
    bool? resetActive,
    DateTime? resetStartedAt,
    bool? archived,
  }) => Habit(
    id: id,
    userId: userId,
    captureId: captureId,
    goalId: goalId ?? this.goalId,
    title: title ?? this.title,
    frequencyConfig: frequencyConfig ?? this.frequencyConfig,
    levelConfig: levelConfig ?? this.levelConfig,
    anchorDescription: anchorDescription ?? this.anchorDescription,
    resetActive: resetActive ?? this.resetActive,
    resetStartedAt: resetStartedAt ?? this.resetStartedAt,
    archived: archived ?? this.archived,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

abstract interface class HabitsRepository {
  Stream<List<Habit>> watchAll();
  Future<Habit> create({
    required String title,
    Map<String, Object?>? frequencyConfig,
    Map<String, Object?>? levelConfig,
    String? anchorDescription,
    String? captureId,
    String? goalId,
  });
  Future<void> update(Habit habit);
  Future<void> delete(String id);
}

/// Additive P4 idempotent writer for capture-derived habits.
abstract interface class CaptureLinkedHabitsRepository {
  Future<Habit> createForCapture({
    required String captureId,
    required String title,
    Map<String, Object?>? levelConfig,
    String? anchorDescription,
  });
}

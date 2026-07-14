import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';

/// An immutable completion-log row: any level counts as a full win (P5).
@immutable
class HabitCompletion {
  const HabitCompletion({
    required this.id,
    required this.userId,
    required this.habitId,
    required this.level,
    required this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.energyMode,
  });

  final String id;
  final String userId;
  final String habitId;
  final HabitLevel level;
  final EnergyMode? energyMode;
  final DateTime completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

abstract interface class HabitCompletionsRepository {
  Stream<List<HabitCompletion>> watchAll();
  Stream<List<HabitCompletion>> watchByHabit(String habitId);

  Future<HabitCompletion> create({
    required String habitId,
    required HabitLevel level,
    EnergyMode? energyMode,
    DateTime? completedAt,
  });

  Future<void> delete(String id);
}

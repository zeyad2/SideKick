import 'package:meta/meta.dart';

/// A post-session 3-tap mood signal (value 1..3). See focus_sessions (P7).
@immutable
class VibeCheck {
  const VibeCheck({
    required this.id,
    required this.userId,
    required this.value,
    required this.createdAt,
    required this.updatedAt,
    this.focusSessionId,
  });

  final String id;
  final String userId;
  final String? focusSessionId;
  final int value;
  final DateTime createdAt;
  final DateTime updatedAt;
}

abstract interface class VibeChecksRepository {
  Stream<List<VibeCheck>> watchAll();
  Future<VibeCheck> create({required int value, String? focusSessionId});
  Future<void> delete(String id);
}

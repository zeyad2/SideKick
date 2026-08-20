import 'package:meta/meta.dart';

@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.userId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.title,
  });

  final String id;
  final String userId;
  final String? title;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
}

@immutable
class Message {
  const Message({
    required this.id,
    required this.userId,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String conversationId;
  final String role;
  final String content;
  final Map<String, Object?> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
}

abstract interface class ConversationRepository {
  Stream<List<Conversation>> watchAll();
  Future<Conversation> create({String? title, String status = 'open'});
  Future<Message> addMessage({
    required String conversationId,
    required String role,
    required String content,
    Map<String, Object?> metadata,
  });
  Stream<List<Message>> watchMessages(String conversationId);
}

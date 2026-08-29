import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/db/json_codec.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/features/conversations/domain/conversation.dart';

class ConversationRepositoryImpl extends LocalFirstRepository
    implements ConversationRepository {
  ConversationRepositoryImpl({
    required super.db,
    required super.emitter,
    required super.idGenerator,
    required super.userId,
    super.clock,
  });

  @override
  Stream<List<Conversation>> watchAll() =>
      (db.select(db.conversations)
            ..where(
              (Conversations c) =>
                  c.userId.equals(userId) & c.deletedAt.isNull(),
            )
            ..orderBy(<OrderClauseGenerator<Conversations>>[
              (Conversations c) => OrderingTerm.desc(c.createdAt),
            ]))
          .watch()
          .map((rows) => rows.map(_conversation).toList(growable: false));

  @override
  Future<Conversation> create({String? title, String status = 'open'}) async {
    final DateTime timestamp = now();
    final String id = newId();
    await db
        .into(db.conversations)
        .insert(
          ConversationsCompanion.insert(
            id: id,
            userId: userId,
            title: Value<String?>(title),
            status: Value<String>(status),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    emitter.emitCreated(
      userId: userId,
      entityType: EntityTypes.conversation,
      entityId: id,
    );
    return (await _conversationById(id))!;
  }

  @override
  Future<Message> addMessage({
    required String conversationId,
    required String role,
    required String content,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final DateTime timestamp = now();
    final String id = newId();
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: id,
            userId: userId,
            conversationId: conversationId,
            role: role,
            content: content,
            metadata: Value<String>(JsonCodecs.encode(metadata)),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    emitter.emitCreated(
      userId: userId,
      entityType: EntityTypes.message,
      entityId: id,
      metadata: <String, Object?>{'conversation_id': conversationId},
    );
    return (await _messageById(id))!;
  }

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      (db.select(db.messages)
            ..where(
              (Messages m) =>
                  m.userId.equals(userId) &
                  m.conversationId.equals(conversationId) &
                  m.deletedAt.isNull(),
            )
            ..orderBy(<OrderClauseGenerator<Messages>>[
              (Messages m) => OrderingTerm.asc(m.createdAt),
            ]))
          .watch()
          .map((rows) => rows.map(_message).toList(growable: false));

  Future<Conversation?> _conversationById(String id) async {
    final ConversationRow? row =
        await (db.select(db.conversations)..where(
              (Conversations c) => c.id.equals(id) & c.userId.equals(userId),
            ))
            .getSingleOrNull();
    return row == null ? null : _conversation(row);
  }

  Future<Message?> _messageById(String id) async {
    final MessageRow? row =
        await (db.select(
              db.messages,
            )..where((Messages m) => m.id.equals(id) & m.userId.equals(userId)))
            .getSingleOrNull();
    return row == null ? null : _message(row);
  }

  Conversation _conversation(ConversationRow row) => Conversation(
    id: row.id,
    userId: row.userId,
    title: row.title,
    status: row.status,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  Message _message(MessageRow row) => Message(
    id: row.id,
    userId: row.userId,
    conversationId: row.conversationId,
    role: row.role,
    content: row.content,
    metadata: JsonCodecs.decodeMap(row.metadata),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

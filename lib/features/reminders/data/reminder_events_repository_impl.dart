import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/db/json_codec.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/features/reminders/domain/reminder_event.dart';

class ReminderEventsRepositoryImpl extends LocalFirstRepository
    implements ReminderEventsRepository {
  ReminderEventsRepositoryImpl({
    required super.db,
    required super.emitter,
    required super.idGenerator,
    required super.userId,
    super.clock,
  });

  @override
  Future<ReminderEvent> append({
    required String reminderId,
    required ReminderEventType eventType,
    Map<String, Object?> metadata = const <String, Object?>{},
    String? id,
  }) async {
    final DateTime timestamp = now();
    final String eventId = id ?? newId();
    await db
        .into(db.reminderEvents)
        .insert(
          ReminderEventsCompanion.insert(
            id: eventId,
            userId: userId,
            reminderId: reminderId,
            eventType: eventType.wire,
            metadata: Value<String>(JsonCodecs.encode(metadata)),
            occurredAt: Value<DateTime>(timestamp),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return (await _byId(eventId))!;
  }

  @override
  Stream<List<ReminderEvent>> watchForReminder(String reminderId) =>
      (db.select(db.reminderEvents)
            ..where(
              (ReminderEvents e) =>
                  e.userId.equals(userId) &
                  e.reminderId.equals(reminderId) &
                  e.deletedAt.isNull(),
            )
            ..orderBy(<OrderClauseGenerator<ReminderEvents>>[
              (ReminderEvents e) => OrderingTerm.asc(e.occurredAt),
            ]))
          .watch()
          .map((rows) => rows.map(_toDomain).toList(growable: false));

  @override
  Future<List<ReminderEvent>> recentActions({required int limit}) async {
    if (limit <= 0) return const <ReminderEvent>[];
    final List<String> actionTypes = <ReminderEventType>[
      ReminderEventType.done,
      ReminderEventType.later,
      ReminderEventType.dismissed,
      ReminderEventType.wrongPlace,
      ReminderEventType.edited,
    ].map((ReminderEventType type) => type.wire).toList(growable: false);
    final List<ReminderEventRow> rows =
        await (db.select(db.reminderEvents)
              ..where(
                (ReminderEvents e) =>
                    e.userId.equals(userId) &
                    e.deletedAt.isNull() &
                    e.eventType.isIn(actionTypes),
              )
              ..orderBy(<OrderClauseGenerator<ReminderEvents>>[
                (ReminderEvents e) => OrderingTerm.desc(e.occurredAt),
              ])
              ..limit(limit))
            .get();
    return rows.map(_toDomain).toList(growable: false);
  }

  @override
  Future<ReminderEvent?> findById(String id) => _byId(id);

  @override
  Future<ReminderEvent?> findByNativeActionId(String nativeActionId) async {
    final List<ReminderEventRow> rows =
        await (db.select(db.reminderEvents)..where(
              (ReminderEvents e) =>
                  e.userId.equals(userId) & e.deletedAt.isNull(),
            ))
            .get();
    for (final ReminderEventRow row in rows) {
      final ReminderEvent event = _toDomain(row);
      if (event.metadata['native_action_id'] == nativeActionId) return event;
    }
    return null;
  }

  Future<ReminderEvent?> _byId(String id) async {
    final ReminderEventRow? row =
        await (db.select(db.reminderEvents)..where(
              (ReminderEvents e) => e.id.equals(id) & e.userId.equals(userId),
            ))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  ReminderEvent _toDomain(ReminderEventRow row) => ReminderEvent(
    id: row.id,
    userId: row.userId,
    reminderId: row.reminderId,
    eventType: ReminderEventType.fromWire(row.eventType),
    metadata: JsonCodecs.decodeMap(row.metadata),
    occurredAt: row.occurredAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

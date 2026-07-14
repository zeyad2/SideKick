import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/db/json_codec.dart';
import 'package:sidekick/core/events/domain_event.dart';

/// The write-only append-only event log (D9). Exposes ONLY `append` (immutable
/// — no update/delete) plus a minimal `getSince` for tests. There is
/// deliberately NO read/query/analytics API: the read side is a future plan.
abstract interface class EventsRepository {
  /// Appends an immutable event LOCAL-FIRST, marking it dirty for sync. Returns
  /// once the local write completes.
  Future<void> append(DomainEvent event);

  /// TEST-ONLY minimal read: events with `occurred_at >= since`, oldest first.
  /// Not a product read surface — do not build UI on this.
  @visibleForTesting
  Future<List<DomainEvent>> getSince(DateTime since);
}

class DriftEventsRepository implements EventsRepository {
  DriftEventsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> append(DomainEvent event) async {
    // Append-only INSERT. Client-generated id + occurred_at, dirty for sync.
    // updated_at == created_at because the row is immutable (0002 contract).
    await _db
        .into(_db.events)
        .insert(
          EventsCompanion.insert(
            id: event.id,
            userId: event.userId,
            eventType: event.eventType,
            entityType: Value<String?>(event.entityType),
            entityId: Value<String?>(event.entityId),
            metadata: Value<String>(JsonCodecs.encode(event.metadata)),
            occurredAt: Value<DateTime>(event.occurredAt),
            createdAt: Value<DateTime>(event.occurredAt),
            updatedAt: Value<DateTime>(event.occurredAt),
            dirty: const Value<bool>(true),
          ),
        );
  }

  @override
  Future<List<DomainEvent>> getSince(DateTime since) async {
    final List<EventRow> rows =
        await (_db.select(_db.events)
              ..where((Events e) => e.occurredAt.isBiggerOrEqualValue(since))
              ..orderBy(<OrderClauseGenerator<Events>>[
                (Events e) => OrderingTerm.asc(e.occurredAt),
              ]))
            .get();
    return rows.map(_toDomain).toList(growable: false);
  }

  DomainEvent _toDomain(EventRow row) => DomainEvent(
    id: row.id,
    userId: row.userId,
    eventType: row.eventType,
    entityType: row.entityType,
    entityId: row.entityId,
    metadata: JsonCodecs.decodeMap(row.metadata),
    occurredAt: row.occurredAt,
  );
}

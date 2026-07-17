import 'package:drift/drift.dart';
import 'package:sidekick/core/data/local_first_repository.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/events/domain_event.dart';
import 'package:sidekick/features/places/domain/place.dart';

class PlacesRepositoryImpl extends LocalFirstRepository
    implements PlacesRepository {
  PlacesRepositoryImpl({
    required super.db,
    required super.emitter,
    required super.idGenerator,
    required super.userId,
    super.clock,
  });

  @override
  Stream<List<Place>> watchAll() =>
      (db.select(db.places)
            ..where(
              (Places p) => p.userId.equals(userId) & p.deletedAt.isNull(),
            )
            ..orderBy(<OrderClauseGenerator<Places>>[
              (Places p) => OrderingTerm.desc(p.createdAt),
            ]))
          .watch()
          .map(
            (List<PlaceRow> rows) =>
                rows.map(_toDomain).toList(growable: false),
          );

  @override
  Future<Place> create({
    required String name,
    required double lat,
    required double lng,
    int radiusM = 150,
  }) async {
    final DateTime timestamp = now();
    final String id = newId();
    await db
        .into(db.places)
        .insert(
          PlacesCompanion.insert(
            id: id,
            userId: userId,
            name: name,
            lat: lat,
            lng: lng,
            radiusM: Value<int>(radiusM),
            createdAt: Value<DateTime>(timestamp),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
    emitter.emitCreated(
      userId: userId,
      entityType: EntityTypes.place,
      entityId: id,
    );
    final PlaceRow row = await (db.select(
      db.places,
    )..where((Places p) => p.id.equals(id))).getSingle();
    return _toDomain(row);
  }

  @override
  Future<void> update(Place place) async {
    final DateTime timestamp = now();
    await (db.update(
          db.places,
        )..where((Places p) => p.id.equals(place.id) & p.userId.equals(userId)))
        .write(
          PlacesCompanion(
            name: Value<String>(place.name),
            lat: Value<double>(place.lat),
            lng: Value<double>(place.lng),
            radiusM: Value<int>(place.radiusM),
            updatedAt: Value<DateTime>(timestamp),
            dirty: const Value<bool>(true),
          ),
        );
  }

  @override
  Future<void> delete(String id) async {
    final DateTime timestamp = now();
    await (db.update(
      db.places,
    )..where((Places p) => p.id.equals(id) & p.userId.equals(userId))).write(
      PlacesCompanion(
        deletedAt: Value<DateTime>(timestamp),
        updatedAt: Value<DateTime>(timestamp),
        dirty: const Value<bool>(true),
      ),
    );
  }

  Place _toDomain(PlaceRow row) => Place(
    id: row.id,
    userId: row.userId,
    name: row.name,
    lat: row.lat,
    lng: row.lng,
    radiusM: row.radiusM,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

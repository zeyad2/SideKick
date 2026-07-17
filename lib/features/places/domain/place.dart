import 'package:meta/meta.dart';

@immutable
class Place {
  const Place({
    required this.id,
    required this.userId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusM,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final double lat;
  final double lng;
  final int radiusM;
  final DateTime createdAt;
  final DateTime updatedAt;

  Place copyWith({String? name, double? lat, double? lng, int? radiusM}) =>
      Place(
        id: id,
        userId: userId,
        name: name ?? this.name,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        radiusM: radiusM ?? this.radiusM,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

abstract interface class PlacesRepository {
  Stream<List<Place>> watchAll();
  Future<Place> create({
    required String name,
    required double lat,
    required double lng,
    int radiusM,
  });
  Future<void> update(Place place);
  Future<void> delete(String id);
}

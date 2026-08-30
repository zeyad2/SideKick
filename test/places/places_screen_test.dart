import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/core/theme/app_theme_registry.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/features/places/domain/place.dart';
import 'package:sidekick/features/places/presentation/places_screen.dart';

void main() {
  testWidgets('saves the map pin instead of forcing current location', (
    WidgetTester tester,
  ) async {
    final _FakePlacesRepository repository = _FakePlacesRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [placesRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: AppThemeScope(
              theme: AppThemeRegistry.byName(AppThemeRegistry.defaultThemeName),
              child: const PlacesScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'Coffee shop');
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
    await tester.pump(const Duration(milliseconds: 300));
    final Finder saveButton = find.widgetWithText(
      FilledButton,
      'Save selected location',
    );
    await tester.ensureVisible(saveButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(saveButton);
    await tester.pump();

    expect(repository.createdName, 'Coffee shop');
    expect(repository.createdLat, closeTo(20, 1));
    expect(repository.createdLng, closeTo(0, 1));
    expect(find.textContaining('Coffee shop saved'), findsOneWidget);
  });
}

class _FakePlacesRepository implements PlacesRepository {
  String? createdName;
  double? createdLat;
  double? createdLng;

  @override
  Future<Place> create({
    required String name,
    required double lat,
    required double lng,
    int radiusM = 150,
  }) async {
    createdName = name;
    createdLat = lat;
    createdLng = lng;
    final DateTime now = DateTime.utc(2026, 8, 30);
    return Place(
      id: '790978b4-10e8-4c15-b3c0-2f21fce36a51',
      userId: 'user-1',
      name: name,
      lat: lat,
      lng: lng,
      radiusM: radiusM,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> update(Place place) async {}

  @override
  Stream<List<Place>> watchAll() => Stream<List<Place>>.value(const <Place>[]);
}

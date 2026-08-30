import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sidekick/features/places/presentation/place_map_picker.dart';

void main() {
  testWidgets('tap selects a location and renders its geofence pin', (
    WidgetTester tester,
  ) async {
    final MapController controller = MapController();
    addTearDown(controller.dispose);
    LatLng? selected;

    Widget app() => MaterialApp(
      home: Scaffold(
        body: Center(
          child: PlaceMapPicker(
            controller: controller,
            selected: selected,
            onSelected: (LatLng point) => selected = point,
          ),
        ),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
    await tester.pump(const Duration(milliseconds: 300));

    expect(selected, isNotNull);
    expect(selected!.latitude, closeTo(PlaceMapPicker.worldCenter.latitude, 1));
    expect(
      selected!.longitude,
      closeTo(PlaceMapPicker.worldCenter.longitude, 1),
    );

    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.byKey(const Key('selected-place-pin')), findsOneWidget);
    final CircleLayer circle = tester.widget<CircleLayer>(
      find.byType(CircleLayer),
    );
    expect(circle.circles.single.radius, 150);
    expect(circle.circles.single.useRadiusInMeter, isTrue);
  });
}

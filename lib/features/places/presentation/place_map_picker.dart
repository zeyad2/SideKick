import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class PlaceMapPicker extends StatelessWidget {
  const PlaceMapPicker({
    required this.controller,
    required this.selected,
    required this.onSelected,
    this.onMapReady,
    this.radiusM = 150,
    super.key,
  });

  static const LatLng worldCenter = LatLng(20, 0);

  final MapController controller;
  final LatLng? selected;
  final ValueChanged<LatLng> onSelected;
  final VoidCallback? onMapReady;
  final int radiusM;

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'Place location map. Tap to choose a reminder location.',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          key: const Key('place-map-picker'),
          height: 320,
          child: FlutterMap(
            mapController: controller,
            options: MapOptions(
              initialCenter: selected ?? worldCenter,
              initialZoom: selected == null ? 2.5 : 16,
              minZoom: 2,
              maxZoom: 19,
              onMapReady: onMapReady,
              onTap: (_, LatLng point) => onSelected(point),
            ),
            children: <Widget>[
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.sidekick.sidekick',
                maxNativeZoom: 19,
              ),
              if (selected != null)
                CircleLayer(
                  circles: <CircleMarker<Object>>[
                    CircleMarker<Object>(
                      point: selected!,
                      radius: radiusM.toDouble(),
                      useRadiusInMeter: true,
                      color: primary.withValues(alpha: 0.16),
                      borderColor: primary,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              if (selected != null)
                MarkerLayer(
                  markers: <Marker>[
                    Marker(
                      point: selected!,
                      width: 48,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: Icon(
                        Icons.location_pin,
                        key: const Key('selected-place-pin'),
                        color: primary,
                        size: 46,
                        shadows: const <Shadow>[
                          Shadow(color: Colors.white, blurRadius: 3),
                        ],
                      ),
                    ),
                  ],
                ),
              const RichAttributionWidget(
                attributions: <SourceAttribution>[
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

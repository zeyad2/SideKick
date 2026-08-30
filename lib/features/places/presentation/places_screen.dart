import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:sidekick/core/capture/capture_permissions.dart';
import 'package:sidekick/core/capture/capture_providers.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/widgets/pill_button.dart';
import 'package:sidekick/core/theme/widgets/surface_card.dart';
import 'package:sidekick/features/places/application/current_location_platform.dart';
import 'package:sidekick/features/places/domain/place.dart';
import 'package:sidekick/features/places/presentation/place_map_picker.dart';

final StreamProvider<List<Place>> placesProvider = StreamProvider<List<Place>>((
  Ref ref,
) {
  return ref.watch(placesRepositoryProvider).watchAll();
});

class PlacesScreen extends ConsumerStatefulWidget {
  const PlacesScreen({super.key});

  @override
  ConsumerState<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends ConsumerState<PlacesScreen> {
  final TextEditingController _name = TextEditingController();
  final MapController _mapController = MapController();
  LatLng? _selectedLocation;
  bool _mapReady = false;
  bool _findingLocation = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _findingLocation = true);
    try {
      final permissions = CapturePermissions(
        ref.read(nativeCaptureApiProvider),
      );
      if (!await permissions.requestLocation()) {
        _message('Location permission is needed to save this place.');
        return;
      }
      final CurrentCoordinates point = await const CurrentLocationPlatform()
          .getCurrent();
      final LatLng selected = LatLng(point.lat, point.lng);
      setState(() => _selectedLocation = selected);
      if (_mapReady) _mapController.move(selected, 17);
      _message('Pin moved to your current location.');
    } on PlatformException catch (error) {
      _message(error.message ?? 'Could not get your current location.');
    } catch (_) {
      _message(
        'Could not find your location. Check location services and retry.',
      );
    } finally {
      if (mounted) setState(() => _findingLocation = false);
    }
  }

  Future<void> _saveSelectedLocation() async {
    final String name = _name.text.trim();
    final LatLng? selected = _selectedLocation;
    if (name.isEmpty) {
      _message('Give this place a name, like Home, Work, or Gym.');
      return;
    }
    if (selected == null) {
      _message('Tap the map to choose where this place should trigger.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(placesRepositoryProvider)
          .create(name: name, lat: selected.latitude, lng: selected.longitude);
      _name.clear();
      setState(() => _selectedLocation = null);
      _message('$name saved. You can now use it in place reminders.');
    } catch (_) {
      _message('Could not save this place. Please retry.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _delete(Place place) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Remove ${place.name}?'),
        content: const Text(
          'Existing reminders keep their details, but this place will no longer appear when creating a reminder.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(placesRepositoryProvider).delete(place.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final AsyncValue<List<Place>> places = ref.watch(placesProvider);
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.all(theme.spacing.mobileMargin),
        children: <Widget>[
          Text('Places', style: theme.textTheme.displaySmall),
          SizedBox(height: theme.spacing.sm),
          Text(
            'Save the places you use often. Sidekick can remind you when you arrive or leave.',
            style: theme.textTheme.bodyMedium,
          ),
          SizedBox(height: theme.spacing.lg),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Add a place', style: theme.textTheme.titleLarge),
                SizedBox(height: theme.spacing.sm),
                Text(
                  'Move around the map and tap the exact location. The circle shows the roughly 150 m trigger area.',
                  style: theme.textTheme.bodySmall,
                ),
                SizedBox(height: theme.spacing.md),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Place name',
                    hintText: 'Home, Work, Gym…',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                SizedBox(height: theme.spacing.md),
                PlaceMapPicker(
                  controller: _mapController,
                  selected: _selectedLocation,
                  onMapReady: () => _mapReady = true,
                  onSelected: (LatLng point) {
                    setState(() => _selectedLocation = point);
                  },
                ),
                SizedBox(height: theme.spacing.sm),
                Text(
                  _selectedLocation == null
                      ? 'No location selected yet.'
                      : 'Selected: ${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)}',
                  key: const Key('selected-place-coordinates'),
                  style: theme.textTheme.bodySmall,
                ),
                SizedBox(height: theme.spacing.md),
                PillButton(
                  label: _findingLocation
                      ? 'Finding your location…'
                      : 'Use my current location',
                  onPressed: _findingLocation || _saving
                      ? null
                      : _useCurrentLocation,
                  variant: PillButtonVariant.secondary,
                ),
                SizedBox(height: theme.spacing.sm),
                PillButton(
                  label: _saving ? 'Saving place…' : 'Save selected location',
                  onPressed: _saving ? null : _saveSelectedLocation,
                ),
              ],
            ),
          ),
          SizedBox(height: theme.spacing.xl),
          Text('Saved places', style: theme.textTheme.headlineMedium),
          SizedBox(height: theme.spacing.sm),
          places.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const SurfaceCard(
              child: Text('Saved places are unavailable right now.'),
            ),
            data: (List<Place> rows) => rows.isEmpty
                ? const SurfaceCard(
                    child: Text(
                      'No places saved yet. Pick one on the map above.',
                    ),
                  )
                : Column(
                    children: rows
                        .map(
                          (Place place) => Padding(
                            padding: EdgeInsets.only(bottom: theme.spacing.sm),
                            child: SurfaceCard(
                              child: Row(
                                children: <Widget>[
                                  const Icon(Icons.location_on_rounded),
                                  SizedBox(width: theme.spacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          place.name,
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        Text(
                                          'Triggers within about ${place.radiusM} m',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove ${place.name}',
                                    onPressed: () => _delete(place),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }
}

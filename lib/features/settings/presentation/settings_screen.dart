import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/capture/capture_permissions.dart';
import 'package:sidekick/core/capture/capture_providers.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/core/sync/sync_providers.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/widgets/pill_button.dart';
import 'package:sidekick/core/theme/widgets/surface_card.dart';
import 'package:sidekick/features/places/domain/place.dart';

final StreamProvider<List<Place>> settingsPlacesProvider =
    StreamProvider<List<Place>>((Ref ref) {
      return ref.watch(placesRepositoryProvider).watchAll();
    });

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  Future<CapturePermissionSnapshot>? _status;

  CapturePermissions get _permissions =>
      CapturePermissions(ref.read(nativeCaptureApiProvider));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    setState(() {
      _status = _permissions.status();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    await action();
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final AsyncValue<List<Place>> places = ref.watch(settingsPlacesProvider);
    final bool syncAvailable = ref.watch(syncEngineProvider) != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.all(theme.spacing.mobileMargin),
        children: <Widget>[
          Text('Voice capture', style: theme.textTheme.headlineMedium),
          SizedBox(height: theme.spacing.sm),
          Text(
            'Default trigger: triple-press Volume Up. Sidekick writes audio to '
            'your device before it does anything online.',
            style: theme.textTheme.bodyMedium,
          ),
          SizedBox(height: theme.spacing.lg),
          FutureBuilder<CapturePermissionSnapshot>(
            future: _status,
            builder: (BuildContext context, snapshot) {
              final CapturePermissionSnapshot? value = snapshot.data;
              return SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _PermissionRow(
                      label: 'Microphone',
                      granted: value?.microphone == true,
                    ),
                    SizedBox(height: theme.spacing.md),
                    PillButton(
                      label: value?.microphone == true
                          ? 'Microphone allowed'
                          : 'Allow microphone',
                      onPressed: value?.microphone == true
                          ? null
                          : () => _run(() async {
                              await _permissions.requestMicrophone();
                            }),
                    ),
                    SizedBox(height: theme.spacing.lg),
                    _PermissionRow(
                      label: 'Notifications',
                      granted: value?.notifications == true,
                    ),
                    SizedBox(height: theme.spacing.md),
                    PillButton(
                      label: value?.notifications == true
                          ? 'Notifications allowed'
                          : 'Allow notifications',
                      onPressed: value?.notifications == true
                          ? null
                          : () => _run(() async {
                              await _permissions.requestNotifications();
                            }),
                    ),
                    SizedBox(height: theme.spacing.lg),
                    _PermissionRow(
                      label: 'Location while using app',
                      granted: value?.location == true,
                    ),
                    SizedBox(height: theme.spacing.md),
                    PillButton(
                      label: value?.location == true
                          ? 'Location allowed'
                          : 'Allow location',
                      onPressed: value?.location == true
                          ? null
                          : () => _run(() async {
                              await _permissions.requestLocation();
                            }),
                      variant: PillButtonVariant.secondary,
                    ),
                    SizedBox(height: theme.spacing.lg),
                    _PermissionRow(
                      label: 'Background location for place reminders',
                      granted: value?.backgroundLocation == true,
                    ),
                    SizedBox(height: theme.spacing.md),
                    PillButton(
                      label: value?.backgroundLocation == true
                          ? 'Background location allowed'
                          : 'Allow background location',
                      onPressed: value?.backgroundLocation == true
                          ? null
                          : () => _run(() async {
                              await _permissions.requestBackgroundLocation();
                            }),
                      variant: PillButtonVariant.secondary,
                    ),
                    SizedBox(height: theme.spacing.lg),
                    _PermissionRow(
                      label: 'Global hardware trigger',
                      granted: value?.accessibility == true,
                    ),
                    SizedBox(height: theme.spacing.md),
                    PillButton(
                      label: value?.accessibility == true
                          ? 'Accessibility enabled'
                          : 'Open accessibility settings',
                      onPressed: value?.accessibility == true
                          ? null
                          : () => _run(_permissions.openAccessibilitySettings),
                    ),
                    SizedBox(height: theme.spacing.lg),
                    _PermissionRow(
                      label: 'Battery optimization exemption',
                      granted: value?.ignoringBatteryOptimizations == true,
                    ),
                    SizedBox(height: theme.spacing.sm),
                    Text(
                      'Optional, but recommended on OEMs that aggressively stop '
                      'background services.',
                      style: theme.textTheme.bodySmall,
                    ),
                    SizedBox(height: theme.spacing.md),
                    PillButton(
                      label: value?.ignoringBatteryOptimizations == true
                          ? 'Battery protection configured'
                          : 'Review battery settings',
                      onPressed: value?.ignoringBatteryOptimizations == true
                          ? null
                          : () => _run(
                              _permissions.requestBatteryOptimizationExemption,
                            ),
                      variant: PillButtonVariant.secondary,
                    ),
                  ],
                ),
              );
            },
          ),
          SizedBox(height: theme.spacing.xl),
          Text('Saved places', style: theme.textTheme.headlineMedium),
          SizedBox(height: theme.spacing.sm),
          SurfaceCard(
            child: places.when(
              loading: () => const Text('Checking saved places...'),
              error: (_, _) => const Text('Saved places unavailable.'),
              data: (List<Place> rows) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _PermissionRow(
                    label: rows.isEmpty
                        ? 'No saved places yet'
                        : '${rows.length} saved place(s)',
                    granted: rows.isNotEmpty,
                  ),
                  SizedBox(height: theme.spacing.sm),
                  Text(
                    rows.isEmpty
                        ? 'Place reminders stay in review until a place is saved.'
                        : rows
                              .map(
                                (Place place) =>
                                    '${place.name} (${place.radiusM}m)',
                              )
                              .join('\n'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: theme.spacing.xl),
          Text('Sync and account', style: theme.textTheme.headlineMedium),
          SizedBox(height: theme.spacing.sm),
          SurfaceCard(
            child: Column(
              children: <Widget>[
                _PermissionRow(label: 'Sync engine', granted: syncAvailable),
                SizedBox(height: theme.spacing.md),
                _PermissionRow(label: 'Account session', granted: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.label, required this.granted});
  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Row(
      children: <Widget>[
        Icon(
          granted ? Icons.check_circle_rounded : Icons.circle_outlined,
          color: granted
              ? theme.colors.secondary
              : theme.colors.onSurfaceVariant,
        ),
        SizedBox(width: theme.spacing.sm),
        Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
      ],
    );
  }
}

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
import 'package:sidekick/features/settings/application/android_reminder_sound_platform.dart';
import 'package:sidekick/features/settings/domain/reminder_sound.dart';

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
  Future<ReminderSoundState>? _sounds;
  String? _soundBusy;

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
      _sounds = ref.read(reminderSoundPlatformProvider).state();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    await action();
    if (mounted) _refresh();
  }

  Future<void> _runSound(
    String operation,
    Future<void> Function(ReminderSoundPlatform platform) action,
  ) async {
    if (_soundBusy != null) return;
    setState(() => _soundBusy = operation);
    try {
      await action(ref.read(reminderSoundPlatformProvider));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _soundBusy = null;
          _sounds = ref.read(reminderSoundPlatformProvider).state();
        });
      }
    }
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
          Text('Reminder sound', style: theme.textTheme.headlineMedium),
          SizedBox(height: theme.spacing.sm),
          Text(
            'Use the system alarm, download a small optional tone, or import '
            'an audio file already on this device. Downloaded and imported '
            'sounds stay local and are not synced.',
            style: theme.textTheme.bodyMedium,
          ),
          SizedBox(height: theme.spacing.md),
          FutureBuilder<ReminderSoundState>(
            future: _sounds,
            builder: (BuildContext context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SurfaceCard(
                  child: Text('Checking reminder sounds...'),
                );
              }
              if (snapshot.hasError || snapshot.data == null) {
                return const SurfaceCard(
                  child: Text('Reminder sounds are unavailable.'),
                );
              }
              final ReminderSoundState state = snapshot.data!;
              return SurfaceCard(
                child: Column(
                  children: <Widget>[
                    _SoundRow(
                      name: 'System alarm',
                      detail: 'Uses the alarm sound configured in Android.',
                      selected: state.systemSelected,
                      busy: _soundBusy != null,
                      onSelect: () => _runSound(
                        'system',
                        (ReminderSoundPlatform platform) =>
                            platform.select('system'),
                      ),
                      onPreview: () => _runSound(
                        'preview-system',
                        (ReminderSoundPlatform platform) =>
                            platform.preview('system'),
                      ),
                    ),
                    for (final ReminderSoundOption sound in state.catalog) ...[
                      Divider(height: theme.spacing.xl),
                      _SoundRow(
                        name: sound.name,
                        detail: sound.downloaded
                            ? 'Downloaded • CC0'
                            : 'Optional download • CC0',
                        selected: sound.selected,
                        busy: _soundBusy != null,
                        onSelect: sound.downloaded
                            ? () => _runSound(
                                sound.id,
                                (ReminderSoundPlatform platform) =>
                                    platform.select(sound.id),
                              )
                            : null,
                        onDownload: sound.downloaded
                            ? null
                            : () => _runSound(
                                'download-${sound.id}',
                                (ReminderSoundPlatform platform) =>
                                    platform.download(sound.id),
                              ),
                        onPreview: sound.downloaded
                            ? () => _runSound(
                                'preview-${sound.id}',
                                (ReminderSoundPlatform platform) =>
                                    platform.preview(sound.id),
                              )
                            : null,
                        onDelete: sound.downloaded
                            ? () => _runSound(
                                'delete-${sound.id}',
                                (ReminderSoundPlatform platform) =>
                                    platform.delete(sound.id),
                              )
                            : null,
                      ),
                    ],
                    Divider(height: theme.spacing.xl),
                    _SoundRow(
                      name: state.localName ?? 'Local audio file',
                      detail: state.localAvailable
                          ? 'Imported from this device'
                          : 'MP3, WAV, OGG, AAC, or M4A',
                      selected: state.localSelected,
                      busy: _soundBusy != null,
                      onSelect: state.localAvailable
                          ? () => _runSound(
                              'local',
                              (ReminderSoundPlatform platform) =>
                                  platform.select('local'),
                            )
                          : null,
                      onDownload: () => _runSound(
                        'pick-local',
                        (ReminderSoundPlatform platform) =>
                            platform.chooseLocalFile(),
                      ),
                      downloadLabel: state.localAvailable
                          ? 'Replace file'
                          : 'Choose file',
                      onPreview: state.localAvailable
                          ? () => _runSound(
                              'preview-local',
                              (ReminderSoundPlatform platform) =>
                                  platform.preview('local'),
                            )
                          : null,
                      onDelete: state.localAvailable
                          ? () => _runSound(
                              'delete-local',
                              (ReminderSoundPlatform platform) =>
                                  platform.delete('local'),
                            )
                          : null,
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

class _SoundRow extends StatelessWidget {
  const _SoundRow({
    required this.name,
    required this.detail,
    required this.selected,
    required this.busy,
    this.onSelect,
    this.onDownload,
    this.downloadLabel = 'Download',
    this.onPreview,
    this.onDelete,
  });

  final String name;
  final String detail;
  final bool selected;
  final bool busy;
  final VoidCallback? onSelect;
  final VoidCallback? onDownload;
  final String downloadLabel;
  final VoidCallback? onPreview;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected
                  ? theme.colors.secondary
                  : theme.colors.onSurfaceVariant,
            ),
            SizedBox(width: theme.spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(name, style: theme.textTheme.titleMedium),
                  Text(detail, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: theme.spacing.sm),
        Wrap(
          spacing: theme.spacing.sm,
          runSpacing: theme.spacing.xs,
          children: <Widget>[
            if (onDownload != null)
              OutlinedButton(
                onPressed: busy ? null : onDownload,
                child: Text(downloadLabel),
              ),
            if (onSelect != null)
              FilledButton(
                onPressed: busy || selected ? null : onSelect,
                child: Text(selected ? 'Selected' : 'Select'),
              ),
            if (onPreview != null)
              TextButton.icon(
                onPressed: busy ? null : onPreview,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Preview'),
              ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Remove downloaded sound',
                onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
      ],
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

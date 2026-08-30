import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/sync/sync_providers.dart';
import 'package:sidekick/core/theme/app_theme_registry.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/features/settings/application/android_reminder_sound_platform.dart';
import 'package:sidekick/features/settings/domain/reminder_sound.dart';
import 'package:sidekick/features/settings/presentation/settings_screen.dart';

void main() {
  test('native reminder sound state preserves catalog and selection', () {
    final ReminderSoundState state = ReminderSoundState.fromMap(
      <Object?, Object?>{
        'selectedId': 'gentle_bell',
        'localAvailable': true,
        'localName': 'My alarm.mp3',
        'catalog': <Object?>[
          <Object?, Object?>{
            'id': 'gentle_bell',
            'name': 'Gentle Bell',
            'downloaded': true,
            'selected': true,
          },
          <Object?, Object?>{
            'id': 'bright_chime',
            'name': 'Bright Chime',
            'downloaded': false,
            'selected': false,
          },
        ],
      },
    );

    expect(state.selectedId, 'gentle_bell');
    expect(state.catalog, hasLength(2));
    expect(state.catalog.first.name, 'Gentle Bell');
    expect(state.catalog.first.downloaded, isTrue);
    expect(state.localName, 'My alarm.mp3');
    expect(state.localAvailable, isTrue);
  });

  testWidgets('settings exposes optional downloads and local audio', (
    WidgetTester tester,
  ) async {
    final _FakeReminderSoundPlatform sounds = _FakeReminderSoundPlatform();
    final theme = AppThemeRegistry.byName(AppThemeRegistry.defaultThemeName);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsPlacesProvider.overrideWith(
            (Ref ref) => Stream.value(const []),
          ),
          syncEngineProvider.overrideWithValue(null),
          reminderSoundPlatformProvider.overrideWithValue(sounds),
        ],
        child: AppThemeScope(
          theme: theme,
          child: MaterialApp(
            theme: theme.toThemeData(),
            home: const SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Gentle Bell'), 300);

    expect(find.text('Reminder sound'), findsOneWidget);
    expect(find.text('Gentle Bell'), findsOneWidget);
    expect(find.text('Bright Chime'), findsOneWidget);

    final Finder download = find.widgetWithText(OutlinedButton, 'Download').first;
    await tester.ensureVisible(download);
    await tester.pumpAndSettle();
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(sounds.downloaded, <String>['gentle_bell']);

    await tester.scrollUntilVisible(find.text('Choose file'), 200);
    expect(find.text('Choose file'), findsOneWidget);
  });
}

class _FakeReminderSoundPlatform implements ReminderSoundPlatform {
  final List<String> downloaded = <String>[];

  @override
  Future<ReminderSoundState> state() async => const ReminderSoundState(
    selectedId: 'system',
    catalog: <ReminderSoundOption>[
      ReminderSoundOption(
        id: 'gentle_bell',
        name: 'Gentle Bell',
        downloaded: false,
        selected: false,
      ),
      ReminderSoundOption(
        id: 'bright_chime',
        name: 'Bright Chime',
        downloaded: false,
        selected: false,
      ),
    ],
  );

  @override
  Future<void> download(String id) async => downloaded.add(id);

  @override
  Future<void> chooseLocalFile() async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> preview(String id) async {}

  @override
  Future<void> select(String id) async {}
}

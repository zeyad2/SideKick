import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/app.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/providers/core_providers.dart';
import 'package:sidekick/core/sync/sync_providers.dart';
import 'package:sidekick/core/theme/app_theme_registry.dart';
import 'package:sidekick/core/theme/theme_providers.dart';
import 'package:sidekick/features/profile/preferences_providers.dart';

import 'support/fakes.dart';

void main() {
  // Overrides that put the app past the P2 auth gate into the themed shell, so
  // the P0 theme + shell contract is still exercised end-to-end. Auth/sync are
  // faked; the database is in-memory — no Supabase.
  final signedIn = [
    appDatabaseProvider.overrideWith((Ref ref) {
      final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
      ref.onDispose(db.close);
      return db;
    }),
    authRepositoryProvider.overrideWithValue(FakeAuthRepository.signedIn('u1')),
    onboardingCompletedProvider.overrideWithValue(true),
    syncEngineProvider.overrideWithValue(null),
  ];

  testWidgets('renders the themed shell and switches destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(overrides: signedIn, child: const SidekickApp()),
    );
    await tester.pumpAndSettle();

    final Scaffold scaffold = tester.widget<Scaffold>(
      find.byType(Scaffold).first,
    );
    expect(
      scaffold.backgroundColor,
      AppThemeRegistry.byName(
        AppThemeRegistry.defaultThemeName,
      ).colors.background,
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Inbox'), findsWidgets);
    expect(find.text('Habits'), findsOneWidget);
    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Habits'));
    await tester.pumpAndSettle();

    expect(find.text('Habits'), findsWidgets);
  });

  testWidgets('active theme override changes widgets without widget changes', (
    WidgetTester tester,
  ) async {
    final analog = AppThemeRegistry.byName(AppThemeRegistry.defaultThemeName);
    final throwaway = analog.copyWith(
      name: 'Throwaway',
      colors: analog.colors.copyWith(
        surface: Colors.black,
        background: Colors.black,
        primaryContainer: Colors.purple,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...signedIn,
          activeThemeProvider.overrideWithValue(throwaway),
        ],
        child: const SidekickApp(),
      ),
    );
    await tester.pumpAndSettle();

    final Scaffold scaffold = tester.widget<Scaffold>(
      find.byType(Scaffold).first,
    );
    final DecoratedBox orb = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.bySemanticsLabel('Companion'),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final BoxDecoration decoration = orb.decoration as BoxDecoration;

    expect(scaffold.backgroundColor, throwaway.colors.background);
    expect(scaffold.backgroundColor, isNot(analog.colors.background));
    expect(decoration.color, throwaway.colors.primaryContainer);
  });
}

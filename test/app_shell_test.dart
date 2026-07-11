import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/app.dart';
import 'package:sidekick/core/theme/app_theme_registry.dart';
import 'package:sidekick/core/theme/theme_providers.dart';

void main() {
  testWidgets('renders the themed shell and switches destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SidekickApp()));
    await tester.pumpAndSettle();

    final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
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
        overrides: [activeThemeProvider.overrideWithValue(throwaway)],
        child: const SidekickApp(),
      ),
    );
    await tester.pumpAndSettle();

    final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final DecoratedBox orb = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.bySemanticsLabel('Companion'),
        matching: find.byType(DecoratedBox),
      ),
    );
    final BoxDecoration decoration = orb.decoration as BoxDecoration;

    expect(scaffold.backgroundColor, throwaway.colors.background);
    expect(scaffold.backgroundColor, isNot(analog.colors.background));
    expect(decoration.color, throwaway.colors.primaryContainer);
  });
}

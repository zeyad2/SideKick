import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/theme/app_theme.dart';
import 'package:sidekick/core/theme/app_theme_registry.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/features/inbox/application/inbox_providers.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/inbox/presentation/inbox_screen.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 7, 15);
  late Capture capture;

  setUp(() {
    capture = Capture(
      id: 'capture-1',
      userId: 'u1',
      audioPath: '/pending/capture.aac',
      rawTranscript: 'Lazem akalem el dentist bokra after work.',
      llmType: LlmType.task,
      title: 'Call the dentist',
      details: 'Book an appointment after work.',
      suggestedSchedule: const <String, Object?>{'day': 'tomorrow'},
      status: CaptureStatus.ready,
      capturedAt: now,
      createdAt: now,
      updatedAt: now,
    );
  });

  testWidgets('inbox shows energy choices and a ready capture card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inboxCapturesProvider.overrideWith(
            (Ref ref) => Stream<List<Capture>>.value(<Capture>[capture]),
          ),
          energyModeProvider.overrideWith(
            (Ref ref) => Stream<EnergyMode>.value(EnergyMode.low),
          ),
        ],
        child: _themed(const InboxScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your inbox'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Charged'), findsOneWidget);
    expect(find.text('Call the dentist'), findsOneWidget);
    expect(find.text('TASK · REVIEW'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('triage keeps transcript visible and preselects AI category', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(child: _themed(CaptureTriageSheet(capture: capture))),
    );
    await tester.pumpAndSettle();

    expect(find.text(capture.rawTranscript!), findsOneWidget);
    expect(find.text('Task'), findsOneWidget);
    final ChoiceChip taskChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Task'),
    );
    expect(taskChip.selected, isTrue);
    final TextField title = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    expect(title.controller!.text, 'Call the dentist');
    expect(find.text('Add schedule'), findsNothing);
  });
}

Widget _themed(Widget child) {
  final AppTheme theme = AppThemeRegistry.byName(
    AppThemeRegistry.defaultThemeName,
  );
  return AppThemeScope(
    theme: theme,
    child: MaterialApp(
      theme: theme.toThemeData(),
      home: Scaffold(body: child),
    ),
  );
}

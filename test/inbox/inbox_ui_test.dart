import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/theme/app_theme.dart';
import 'package:sidekick/core/theme/app_theme_registry.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/features/inbox/application/inbox_providers.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/inbox/domain/proposed_item.dart';
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

  testWidgets('bulk review renders one card per proposed item', (
    WidgetTester tester,
  ) async {
    final Capture decomposed = capture.copyWith(
      proposedItems: <ProposedItem>[
        const ProposedItem(
          id: 'd1',
          kind: ResultingType.task,
          title: 'Call the dentist',
          confidence: DraftConfidence.high,
        ),
        const ProposedItem(
          id: 'd2',
          kind: ResultingType.note,
          title: 'Idea for the pitch',
          confidence: DraftConfidence.low,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(child: _themed(CaptureTriageSheet(capture: decomposed))),
    );
    await tester.pumpAndSettle();

    // Two editable cards, the low-confidence hint, and a count-aware CTA.
    expect(find.widgetWithText(TextField, 'Title'), findsNWidgets(2));
    expect(find.text('Worth a second look'), findsOneWidget);
    expect(find.text('Save all 2 items'), findsOneWidget);
  });

  testWidgets('dropping an item updates the count and can be undone', (
    WidgetTester tester,
  ) async {
    final Capture decomposed = capture.copyWith(
      proposedItems: <ProposedItem>[
        const ProposedItem(
          id: 'd1',
          kind: ResultingType.task,
          title: 'Call the dentist',
          confidence: DraftConfidence.high,
        ),
        const ProposedItem(
          id: 'd2',
          kind: ResultingType.note,
          title: 'Idea for the pitch',
          confidence: DraftConfidence.high,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(child: _themed(CaptureTriageSheet(capture: decomposed))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Save all 2 items'), findsOneWidget);

    // Drop the first item.
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Save 1 item'), findsOneWidget);
    expect(find.text('Dropped: Call the dentist'), findsOneWidget);

    // Undo restores it.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Save all 2 items'), findsOneWidget);
  });

  testWidgets('switching a task draft to habit defaults to Mini', (
    WidgetTester tester,
  ) async {
    final Capture decomposed = capture.copyWith(
      proposedItems: const <ProposedItem>[
        ProposedItem(
          id: 'switch-to-habit',
          kind: ResultingType.task,
          title: 'Stretch',
          confidence: DraftConfidence.low,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(child: _themed(CaptureTriageSheet(capture: decomposed))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Habit'));
    await tester.pumpAndSettle();

    final ChoiceChip mini = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Mini'),
    );
    expect(mini.selected, isTrue);
  });

  testWidgets('custom habit cadence remains stored but not authored', (
    WidgetTester tester,
  ) async {
    final Capture decomposed = capture.copyWith(
      proposedItems: const <ProposedItem>[
        ProposedItem(
          id: 'custom-habit',
          kind: ResultingType.habit,
          title: 'Practice scales',
          confidence: DraftConfidence.low,
          cadence: <String, Object?>{
            'type': 'custom',
            'per_week': 3,
            'interval_days': 2,
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(child: _themed(CaptureTriageSheet(capture: decomposed))),
    );
    await tester.pumpAndSettle();

    final ChoiceChip daily = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Daily'),
    );
    final ChoiceChip weekly = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Weekly'),
    );
    expect(daily.selected, isFalse);
    expect(weekly.selected, isFalse);
    expect(find.text('Custom'), findsNothing);
  });

  testWidgets(
    'dropping the last partial draft finalizes instead of discarding',
    (WidgetTester tester) async {
      final Capture partial = capture.copyWith(
        dispositionedItemIds: const <String>['already-saved'],
        proposedItems: const <ProposedItem>[
          ProposedItem(
            id: 'already-saved',
            kind: ResultingType.task,
            title: 'Already saved',
            confidence: DraftConfidence.low,
          ),
          ProposedItem(
            id: 'last-draft',
            kind: ResultingType.note,
            title: 'Last draft',
            confidence: DraftConfidence.low,
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(child: _themed(CaptureTriageSheet(capture: partial))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Last draft'), findsOneWidget);
      expect(find.text('Already saved'), findsNothing);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Drop remaining'), findsOneWidget);
      expect(find.text('Discard capture'), findsNothing);
    },
  );
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

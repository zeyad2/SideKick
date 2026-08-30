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
import 'package:sidekick/features/places/domain/place.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';
import 'package:sidekick/features/reminders/presentation/reminder_formatters.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 7, 15);

  Capture capture(CaptureStatus status) => Capture(
    id: 'capture-1',
    userId: 'u1',
    source: CaptureSource.audio,
    audioPath: '/pending/capture.aac',
    rawTranscript: 'Remind me to call the dentist tomorrow after work.',
    status: status,
    capturedAt: now,
    createdAt: now,
    updatedAt: now,
  );

  TaskReminder pendingReminder() => TaskReminder(
    id: 'reminder-1',
    userId: 'u1',
    title: 'Call the dentist',
    details: 'Bring insurance card.',
    status: TaskReminderStatus.pendingAutoCommit,
    source: TaskReminderSource.typed,
    confidence: 0.9,
    triggerType: TaskReminderTriggerType.time,
    scheduledAt: DateTime.utc(2026, 7, 16, 9),
    autoCommitDeadlineAt: DateTime.now().toUtc().add(
      const Duration(seconds: 10),
    ),
    aiExplanation: 'Detected a time trigger.',
    createdAt: now,
    updatedAt: now,
  );

  testWidgets('home shows typed and audio reminder entry points', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inboxCapturesProvider.overrideWith(
            (Ref ref) => Stream<List<Capture>>.value(<Capture>[]),
          ),
          inboxTaskRemindersProvider.overrideWith(
            (Ref ref) =>
                Stream<List<TaskReminder>>.value(const <TaskReminder>[]),
          ),
          homePlacesProvider.overrideWith(
            (Ref ref) => Stream<List<Place>>.value(const <Place>[]),
          ),
        ],
        child: _themed(const InboxScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('What’s next'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'What should I remind you about?'),
      findsOneWidget,
    );
    expect(find.text('Date & time'), findsOneWidget);
    expect(find.text('Place'), findsOneWidget);
    expect(find.text('Choose date and time'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Create reminder'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Say it instead'),
      findsOneWidget,
    );
    expect(find.byTooltip('Start audio capture'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Nothing upcoming yet.'), findsOneWidget);
    expect(find.text('AUDIO CAPTURES'), findsNothing);
    expect(find.text('Habit'), findsNothing);
    expect(find.text('Goal'), findsNothing);
    expect(find.text('Note'), findsNothing);
  });

  testWidgets('home keeps raw saved audio out of the user experience', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inboxCapturesProvider.overrideWith(
            (Ref ref) => Stream<List<Capture>>.value(<Capture>[
              capture(CaptureStatus.ready),
            ]),
          ),
          inboxTaskRemindersProvider.overrideWith(
            (Ref ref) =>
                Stream<List<TaskReminder>>.value(const <TaskReminder>[]),
          ),
          homePlacesProvider.overrideWith(
            (Ref ref) => Stream<List<Place>>.value(const <Place>[]),
          ),
        ],
        child: _themed(const InboxScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AUDIO CAPTURES'), findsNothing);
    expect(find.text('Capture ready for POC drafting'), findsNothing);
    expect(find.text('Review your thoughts'), findsNothing);
    expect(find.text('Shape this thought'), findsNothing);
  });

  testWidgets('pending auto-commit reminder can be edited or cancelled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inboxCapturesProvider.overrideWith(
            (Ref ref) => Stream<List<Capture>>.value(<Capture>[]),
          ),
          inboxTaskRemindersProvider.overrideWith(
            (Ref ref) => Stream<List<TaskReminder>>.value(<TaskReminder>[
              pendingReminder(),
            ]),
          ),
          homePlacesProvider.overrideWith(
            (Ref ref) => Stream<List<Place>>.value(const <Place>[]),
          ),
        ],
        child: _themed(const InboxScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('AUTO-COMMIT COUNTDOWN'), findsOneWidget);
    expect(find.text(reminderScheduleLabel(pendingReminder())), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Approve now'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Edit'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/theme/app_theme.dart';
import 'package:sidekick/core/theme/app_theme_registry.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';
import 'package:sidekick/features/reminders/presentation/reminder_formatters.dart';
import 'package:sidekick/features/reminders/presentation/reminders_screen.dart';

void main() {
  final DateTime now = DateTime.now().toUtc();

  TaskReminder reminder({
    required String id,
    required TaskReminderStatus status,
    DateTime? scheduledAt,
  }) => TaskReminder(
    id: id,
    userId: 'u1',
    title: id == 'active' ? 'Call the dentist' : 'Renew passport',
    details: 'Bring the documents.',
    status: status,
    source: TaskReminderSource.audio,
    confidence: 0.91,
    triggerType: TaskReminderTriggerType.time,
    scheduledAt: scheduledAt,
    createdAt: now,
    updatedAt: now,
  );

  testWidgets('calendar shows trigger details and lifecycle actions', (
    WidgetTester tester,
  ) async {
    final TaskReminder active = reminder(
      id: 'active',
      status: TaskReminderStatus.active,
      scheduledAt: now.add(const Duration(days: 1)),
    );
    final TaskReminder cancelled = reminder(
      id: 'cancelled',
      status: TaskReminderStatus.cancelled,
      scheduledAt: now.subtract(const Duration(days: 1)),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allTaskRemindersProvider.overrideWith(
            (Ref ref) => Stream<List<TaskReminder>>.value(<TaskReminder>[
              active,
              cancelled,
            ]),
          ),
        ],
        child: _themed(const RemindersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(find.text(reminderScheduleLabel(active)), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Move'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Re-enable'), findsOneWidget);
    expect(find.text('Created from audio • time reminder'), findsWidgets);
  });
}

Widget _themed(Widget child) {
  final AppTheme theme = AppThemeRegistry.byName(
    AppThemeRegistry.defaultThemeName,
  );
  return AppThemeScope(
    theme: theme,
    child: MaterialApp(theme: theme.toThemeData(), home: child),
  );
}

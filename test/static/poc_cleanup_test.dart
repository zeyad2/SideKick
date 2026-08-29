import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final Directory repo = Directory.current;

  test('app shell exposes only POC destinations', () {
    final String shell = File(
      '${repo.path}/lib/features/shell/presentation/app_shell.dart',
    ).readAsStringSync();

    for (final String label in <String>[
      'Capture',
      'Reminders',
      'Places',
      'Settings',
    ]) {
      expect(shell, contains("label: '$label'"));
    }

    for (final String removed in <String>[
      'Habits',
      'Fresh Start',
      'Done',
      'Goals',
      'Notes',
      'Focus',
      'App blocking',
      'Vibe',
    ]) {
      expect(shell, isNot(contains(removed)));
    }
  });

  test('active app entrypoints import no removed feature package', () {
    final List<File> activeFiles = <File>[
      File('${repo.path}/lib/app.dart'),
      File('${repo.path}/lib/core/capture/capture_providers.dart'),
      File('${repo.path}/lib/core/providers/repository_providers.dart'),
      File('${repo.path}/lib/core/router/app_router.dart'),
      File('${repo.path}/lib/core/router/app_routes.dart'),
      File('${repo.path}/lib/core/sync/syncable_tables.dart'),
      File('${repo.path}/lib/features/inbox/application/inbox_providers.dart'),
      File('${repo.path}/lib/features/inbox/presentation/inbox_screen.dart'),
      File(
        '${repo.path}/lib/features/settings/presentation/settings_screen.dart',
      ),
      File('${repo.path}/lib/features/shell/presentation/app_shell.dart'),
    ];

    for (final String removedImport in <String>[
      'features/habits/',
      'features/goals/',
      'features/notes/',
      'features/focus/',
      'features/tasks/',
      'features/settings/data/block_list',
      'features/chat/',
    ]) {
      for (final File file in activeFiles) {
        expect(
          file.readAsStringSync(),
          isNot(contains(removedImport)),
          reason: '${file.path} imports $removedImport',
        );
      }
    }

    final String router = File(
      '${repo.path}/lib/core/router/app_router.dart',
    ).readAsStringSync();
    for (final String removedRoute in <String>[
      'habits',
      'freshStart',
      'focus',
      'chat',
      'conversation',
    ]) {
      expect(router, isNot(contains(removedRoute)));
    }
  });

  test('no active chat route or UI import exists', () {
    final Iterable<File> activeDartFiles = Directory('${repo.path}/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'));

    for (final File file in activeDartFiles) {
      final String source = file.readAsStringSync();
      if (file.path.contains('features\\conversations\\data') ||
          file.path.contains('features\\conversations\\domain')) {
        continue;
      }
      expect(source, isNot(contains('ChatScreen')), reason: file.path);
      expect(source, isNot(contains('/chat')), reason: file.path);
      expect(
        source,
        isNot(contains('features/conversations/presentation')),
        reason: file.path,
      );
    }
  });

  test('active sync registry contains only POC tables', () {
    final String syncableTables = File(
      '${repo.path}/lib/core/sync/syncable_tables.dart',
    ).readAsStringSync();

    for (final String table in <String>[
      'profiles',
      'captures',
      'places',
      'task_reminders',
      'reminder_events',
      'conversations',
      'messages',
      'events',
    ]) {
      expect(syncableTables, contains("SyncableTable('$table'"));
    }

    for (final String removedTable in <String>[
      'goals',
      'tasks',
      'notes',
      'habits',
      'habit_completions',
      'focus_sessions',
      'vibe_checks',
      'reminders',
      'block_list',
    ]) {
      expect(syncableTables, isNot(contains("SyncableTable('$removedTable'")));
    }
  });

  test('Android time reminders use native durable notification actions', () {
    final String scheduler = File(
      '${repo.path}/lib/features/reminders/application/android_reminder_schedule_platform.dart',
    ).readAsStringSync();

    expect(scheduler, isNot(contains('_notificationId')));
    expect(scheduler, isNot(contains('zonedSchedule')));
    expect(scheduler, contains('scheduleTimeReminder'));
    expect(scheduler, contains('managedNotificationId'));
    expect(
      scheduler,
      isNot(contains('ReminderNotificationDispatcher.dispatchPayload')),
    );
  });

  test('README links only to POC or archive docs', () {
    final String readme = File('${repo.path}/README.md').readAsStringSync();
    final RegExp markdownLink = RegExp(r'\[[^\]]+\]\(([^)]+)\)');

    for (final RegExpMatch match in markdownLink.allMatches(readme)) {
      final String target = match.group(1)!;
      if (!target.endsWith('.md')) continue;
      expect(
        target.startsWith('docs/POC_') ||
            target == 'docs/FUTURE_PLANS.md' ||
            target.startsWith('docs/archive/'),
        isTrue,
        reason: '$target is not a current POC or archive document',
      );
    }
  });
}

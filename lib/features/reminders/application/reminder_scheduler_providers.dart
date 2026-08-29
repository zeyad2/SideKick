import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/providers/core_providers.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/features/reminders/application/android_reminder_schedule_platform.dart';
import 'package:sidekick/features/reminders/application/reminder_scheduler.dart';

final Provider<ReminderSchedulePlatform> reminderSchedulePlatformProvider =
    Provider<ReminderSchedulePlatform>(
      (Ref ref) => AndroidReminderSchedulePlatform(),
    );

final Provider<ReminderSchedulerService> reminderSchedulerProvider =
    Provider<ReminderSchedulerService>((Ref ref) {
      return ReminderSchedulerService(
        reminders: ref.watch(taskRemindersRepositoryProvider),
        events: ref.watch(reminderEventsRepositoryProvider),
        places: ref.watch(placesRepositoryProvider),
        platform: ref.watch(reminderSchedulePlatformProvider),
        clock: ref.watch(clockProvider),
        atomically: ref.watch(appDatabaseProvider).transaction,
      );
    });

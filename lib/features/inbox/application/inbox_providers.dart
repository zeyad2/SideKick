import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/providers/core_providers.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/core/utils/app_config.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/reminders/application/reminder_creation_service.dart';
import 'package:sidekick/features/reminders/application/reminder_draft_service.dart';
import 'package:sidekick/features/reminders/domain/task_reminder.dart';

final StreamProvider<List<Capture>> inboxCapturesProvider =
    StreamProvider<List<Capture>>((Ref ref) {
      return ref
          .watch(capturesRepositoryProvider)
          .watchByStatuses(<CaptureStatus>{
            CaptureStatus.pending,
            CaptureStatus.processing,
            CaptureStatus.ready,
            CaptureStatus.failed,
          });
    });

final StreamProvider<List<TaskReminder>> inboxTaskRemindersProvider =
    StreamProvider<List<TaskReminder>>((Ref ref) {
      return ref.watch(taskRemindersRepositoryProvider).watchAll();
    });

final Provider<ReminderDraftService> reminderDraftServiceProvider =
    Provider<ReminderDraftService>((Ref ref) {
      if (!AppConfig.hasGeminiConfiguration) {
        return const HeuristicReminderDraftService();
      }
      return const GeminiReminderDraftService(
        apiKey: AppConfig.geminiApiKey,
        model: AppConfig.geminiModel,
      );
    });

final Provider<ReminderCreationService> reminderCreationServiceProvider =
    Provider<ReminderCreationService>((Ref ref) {
      return ReminderCreationService(
        captures: ref.watch(capturesRepositoryProvider),
        reminders: ref.watch(taskRemindersRepositoryProvider),
        drafts: ref.watch(reminderDraftServiceProvider),
        clock: ref.watch(clockProvider),
      );
    });

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/capture/capture_providers.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/providers/core_providers.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/core/utils/app_config.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';
import 'package:sidekick/features/places/domain/place.dart';
import 'package:sidekick/features/reminders/application/assistant_context_builder.dart';
import 'package:sidekick/features/reminders/application/audio_reminder_retry_controller.dart';
import 'package:sidekick/features/reminders/application/reminder_creation_service.dart';
import 'package:sidekick/features/reminders/application/reminder_draft_service.dart';
import 'package:sidekick/features/reminders/application/reminder_scheduler.dart';
import 'package:sidekick/features/reminders/application/reminder_scheduler_providers.dart';
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
      return ref.watch(taskRemindersRepositoryProvider).watchAll().map((
        List<TaskReminder> reminders,
      ) {
        final DateTime now = DateTime.now().toUtc();
        final List<TaskReminder> upcoming = reminders
            .where(
              (TaskReminder reminder) =>
                  reminder.status == TaskReminderStatus.pendingAutoCommit ||
                  (reminder.status == TaskReminderStatus.active &&
                      (reminder.triggerType == TaskReminderTriggerType.place ||
                          (reminder.scheduledAt?.isAfter(now) ?? false))),
            )
            .toList();
        upcoming.sort((TaskReminder left, TaskReminder right) {
          if (left.status == TaskReminderStatus.pendingAutoCommit &&
              right.status != TaskReminderStatus.pendingAutoCommit) {
            return -1;
          }
          if (right.status == TaskReminderStatus.pendingAutoCommit &&
              left.status != TaskReminderStatus.pendingAutoCommit) {
            return 1;
          }
          final DateTime? a = left.scheduledAt;
          final DateTime? b = right.scheduledAt;
          if (a != null && b != null) return a.compareTo(b);
          if (a != null) return -1;
          if (b != null) return 1;
          return right.updatedAt.compareTo(left.updatedAt);
        });
        return upcoming;
      });
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

final StreamProvider<List<Place>> homePlacesProvider =
    StreamProvider<List<Place>>((Ref ref) {
      return ref.watch(placesRepositoryProvider).watchAll();
    });

final Provider<AssistantContextBuilder> assistantContextBuilderProvider =
    Provider<AssistantContextBuilder>((Ref ref) {
      return RepositoryAssistantContextBuilder(
        profile: ref.watch(profileRepositoryProvider),
        places: ref.watch(placesRepositoryProvider),
        reminders: ref.watch(taskRemindersRepositoryProvider),
        events: ref.watch(reminderEventsRepositoryProvider),
        captures: ref.watch(capturesRepositoryProvider),
      );
    });

final Provider<ReminderCreationService> reminderCreationServiceProvider =
    Provider<ReminderCreationService>((Ref ref) {
      final ReminderSchedulePlatform platform = ref.watch(
        reminderSchedulePlatformProvider,
      );
      return ReminderCreationService(
        captures: ref.watch(capturesRepositoryProvider),
        reminders: ref.watch(taskRemindersRepositoryProvider),
        drafts: ref.watch(reminderDraftServiceProvider),
        clock: ref.watch(clockProvider),
        scheduler: ref.watch(reminderSchedulerProvider),
        contextBuilder: ref.watch(assistantContextBuilderProvider),
        events: ref.watch(reminderEventsRepositoryProvider),
        atomically: ref.watch(appDatabaseProvider).transaction,
        timeZoneSource: platform is DeviceTimeZoneSource
            ? platform as DeviceTimeZoneSource
            : null,
        persistTimeZone: (String zone) => ref
            .read(profileRepositoryProvider)
            .mergePrefs(<String, Object?>{'timezone': zone}),
      );
    });

final Provider<AudioReminderRetryController?>
audioReminderRetryControllerProvider = Provider<AudioReminderRetryController?>((
  Ref ref,
) {
  final coordinator = ref.watch(captureCoordinatorProvider);
  if (coordinator == null) return null;
  final ReminderCreationService creation = ref.watch(
    reminderCreationServiceProvider,
  );
  final native = ref.watch(nativeCaptureApiProvider);
  final AudioReminderRetryController controller = AudioReminderRetryController(
    captures: ref.watch(capturesRepositoryProvider),
    connectivity: ref.watch(connectivityServiceProvider),
    captureEvents: coordinator.capturedAudioEvents,
    barrier: ref.watch(captureIngestionBarrierProvider),
    processAudio: (capture) async {
      await creation.processAudioCapture(capture);
    },
    acknowledgeProcessed: (capture) async {
      final pending = await native.pendingEvents(coordinator.userId);
      for (final event in pending) {
        if (event.audioPath == capture.audioPath) {
          await native.acknowledge(event.eventId);
        }
      }
    },
  );
  controller.start();
  ref.onDispose(() => unawaited(controller.dispose()));
  return controller;
});

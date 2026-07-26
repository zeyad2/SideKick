import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/capture/capture_providers.dart';
import 'package:sidekick/core/providers/core_providers.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/core/utils/app_config.dart';
import 'package:sidekick/features/inbox/application/auto_commit_notifications.dart';
import 'package:sidekick/features/inbox/application/capture_processing_service.dart';
import 'package:sidekick/features/inbox/application/inbox_providers.dart';
import 'package:sidekick/features/inbox/data/gemini_client.dart';
import 'package:sidekick/features/inbox/domain/capture_analysis.dart';
import 'package:sidekick/features/inbox/domain/proposed_item.dart';

final Provider<AutoCommitNotifications?> autoCommitNotificationsProvider =
    Provider<AutoCommitNotifications?>((Ref ref) {
      if (ref.watch(currentUserIdProvider) == null) return null;
      final AutoCommitNotifications notifications = AutoCommitNotifications();
      final StreamSubscription<AutoCommitNotificationRequest> subscription =
          notifications.actions.listen((request) async {
            if (request.action == AutoCommitNotificationAction.undo) {
              try {
                await ref
                    .read(captureTriageServiceProvider)
                    .undoAutoCommit(request.captureId);
              } on StateError {
                // Stale notification actions are deliberately ignored once the
                // brief Undo window or durable receipt has expired.
              }
            } else {
              ref
                  .read(autoCommitEditRequestProvider.notifier)
                  .request(request.captureId);
            }
          });
      unawaited(notifications.initialize());
      ref.onDispose(() {
        unawaited(subscription.cancel());
        unawaited(notifications.dispose());
      });
      return notifications;
    });

final Provider<GeminiClient> geminiClientProvider = Provider<GeminiClient>(
  (Ref ref) => AppConfig.hasGeminiConfiguration
      ? GeminiFlashClient(
          apiKey: AppConfig.geminiApiKey,
          model: AppConfig.geminiModel,
        )
      : const _UnconfiguredGeminiClient(),
);

class _UnconfiguredGeminiClient implements GeminiClient {
  const _UnconfiguredGeminiClient();

  @override
  Future<CaptureAnalysis> analyzeCaptureAudio(File audioFile) =>
      Future<CaptureAnalysis>.error(
        const GeminiRequestException('GEMINI_API_KEY is not configured.'),
      );
}

final Provider<CaptureProcessingService?> captureProcessingServiceProvider =
    Provider<CaptureProcessingService?>((Ref ref) {
      final String? userId = ref.watch(currentUserIdProvider);
      final coordinator = ref.watch(captureCoordinatorProvider);
      if (userId == null || coordinator == null) return null;
      final CaptureProcessingService service = CaptureProcessingService(
        captures: ref.watch(capturesRepositoryProvider),
        gemini: ref.watch(geminiClientProvider),
        connectivity: ref.watch(connectivityServiceProvider),
        barrier: ref.watch(captureIngestionBarrierProvider),
        triage: ref.watch(captureTriageServiceProvider),
        idGenerator: ref.watch(idGeneratorProvider),
        onAutoCommit: (String captureId, List<ProposedItem> items) {
          final AutoCommitNotifications? notifications = ref.read(
            autoCommitNotificationsProvider,
          );
          if (notifications != null) {
            unawaited(notifications.show(captureId, items));
          }
        },
      );
      unawaited(service.start(coordinator.capturedAudioEvents));
      ref.onDispose(() => unawaited(service.dispose()));
      return service;
    });

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/capture/capture_providers.dart';
import 'package:sidekick/core/providers/core_providers.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/core/utils/app_config.dart';
import 'package:sidekick/features/inbox/application/capture_processing_service.dart';
import 'package:sidekick/features/inbox/data/gemini_client.dart';
import 'package:sidekick/features/inbox/domain/capture_analysis.dart';

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
      );
      unawaited(service.start(coordinator.capturedAudioEvents));
      ref.onDispose(() => unawaited(service.dispose()));
      return service;
    });

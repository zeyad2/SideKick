import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/capture/capture_coordinator.dart';
import 'package:sidekick/core/capture/capture_ingestion_service.dart';
import 'package:sidekick/core/capture/native_capture_api.dart';
import 'package:sidekick/core/providers/core_providers.dart';
import 'package:sidekick/core/providers/repository_providers.dart';

final Provider<NativeCaptureApi> nativeCaptureApiProvider =
    Provider<NativeCaptureApi>((Ref ref) {
      final NativeCaptureApi api = MethodChannelNativeCaptureApi();
      ref.onDispose(() => unawaited(api.dispose()));
      return api;
    });

/// Keeps native ownership correct even while no signed-in coordinator exists.
final Provider<void> captureOwnerBindingProvider = Provider<void>((Ref ref) {
  final String? userId = ref.watch(currentUserIdProvider);
  final NativeCaptureApi native = ref.watch(nativeCaptureApiProvider);
  unawaited(native.initialize().then((_) => native.setOwner(userId)));
});

final Provider<CaptureCoordinator?> captureCoordinatorProvider =
    Provider<CaptureCoordinator?>((Ref ref) {
      final String? userId = ref.watch(currentUserIdProvider);
      if (userId == null) return null;
      final NativeCaptureApi native = ref.watch(nativeCaptureApiProvider);
      final CaptureCoordinator coordinator = CaptureCoordinator(
        nativeApi: native,
        ingestion: CaptureIngestionService(
          repository: ref.watch(capturesRepositoryProvider),
          nativeApi: native,
          ownerId: userId,
          barrier: ref.watch(captureIngestionBarrierProvider),
        ),
        profileRepository: ref.watch(profileRepositoryProvider),
        userId: userId,
      );
      unawaited(coordinator.initialize());
      ref.onDispose(() => unawaited(coordinator.dispose()));
      return coordinator;
    });

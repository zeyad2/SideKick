import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/capture/capture_providers.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/providers/core_providers.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/features/inbox/application/capture_triage_service.dart';
import 'package:sidekick/features/inbox/application/energy_mode_service.dart';
import 'package:sidekick/features/inbox/domain/capture.dart';

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

final StreamProvider<EnergyMode> energyModeProvider =
    StreamProvider<EnergyMode>((Ref ref) {
      return ref
          .watch(profileRepositoryProvider)
          .watch()
          .map(
            (profile) =>
                EnergyMode.fromWire(
                  profile?.prefs[EnergyModeService.preferenceKey] as String?,
                ) ??
                EnergyMode.normal,
          );
    });

final Provider<EnergyModeService> energyModeServiceProvider =
    Provider<EnergyModeService>(
      (Ref ref) => EnergyModeService(
        userId: ref.watch(requireUserIdProvider),
        profiles: ref.watch(profileRepositoryProvider),
        emitter: ref.watch(eventEmitterProvider),
      ),
    );

final Provider<CaptureTriageService> captureTriageServiceProvider =
    Provider<CaptureTriageService>(
      (Ref ref) => CaptureTriageService(
        userId: ref.watch(requireUserIdProvider),
        captures: ref.watch(capturesRepositoryProvider),
        tasks: ref.watch(tasksRepositoryProvider),
        notes: ref.watch(notesRepositoryProvider),
        habits: ref.watch(habitsRepositoryProvider),
        goals: ref.watch(goalsRepositoryProvider),
        emitter: ref.watch(eventEmitterProvider),
        nativeApi: ref.watch(nativeCaptureApiProvider),
        pendingQueue: ref.watch(pendingAudioQueueProvider.future),
        barrier: ref.watch(captureIngestionBarrierProvider),
        db: ref.watch(appDatabaseProvider),
        idGenerator: ref.watch(idGeneratorProvider),
      ),
    );

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sidekick/core/audio/pending_audio_queue.dart';
import 'package:sidekick/core/capture/capture_ingestion_barrier.dart';
import 'package:sidekick/core/data/id_generator.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/events/event_emitter.dart';
import 'package:sidekick/core/events/events_repository.dart';
import 'package:sidekick/core/sync/connectivity_service.dart';
import 'package:sidekick/core/sync/sync_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The single local-first database instance for the app session.
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>((
  Ref ref,
) {
  final AppDatabase db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final Provider<IdGenerator> idGeneratorProvider = Provider<IdGenerator>(
  (Ref ref) => IdGenerator(),
);

final Provider<DateTime Function()> clockProvider =
    Provider<DateTime Function()>(
      (Ref ref) =>
          () => DateTime.now().toUtc(),
    );

final Provider<CaptureIngestionBarrier> captureIngestionBarrierProvider =
    Provider<CaptureIngestionBarrier>((Ref ref) => CaptureIngestionBarrier());

/// The Supabase client (initialised in `main` before the app runs).
final Provider<SupabaseClient> supabaseClientProvider =
    Provider<SupabaseClient>((Ref ref) => Supabase.instance.client);

final Provider<ConnectivityService> connectivityServiceProvider =
    Provider<ConnectivityService>((Ref ref) => ConnectivityPlusService());

/// The write-only append-only event log (D9).
final Provider<EventsRepository> eventsRepositoryProvider =
    Provider<EventsRepository>(
      (Ref ref) => DriftEventsRepository(ref.watch(appDatabaseProvider)),
    );

/// The non-blocking event-emission hook the repositories ride on (D9).
final Provider<EventEmitter> eventEmitterProvider = Provider<EventEmitter>(
  (Ref ref) => EventEmitter(
    ref.watch(eventsRepositoryProvider),
    ref.watch(idGeneratorProvider),
  ),
);

final Provider<SyncGateway> syncGatewayProvider = Provider<SyncGateway>(
  (Ref ref) => SupabaseSyncGateway(ref.watch(supabaseClientProvider)),
);

/// The device-storage queue for captured audio (P3/P4 fill it). Async because
/// it resolves the platform documents directory.
final FutureProvider<PendingAudioQueue> pendingAudioQueueProvider =
    FutureProvider<PendingAudioQueue>((Ref ref) async {
      final directory = await getApplicationDocumentsDirectory();
      return DirectoryPendingAudioQueue(baseDir: directory);
    });

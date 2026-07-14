import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/providers/core_providers.dart';
import 'package:sidekick/core/sync/sync_engine.dart';

/// The sync engine for the signed-in user. Rebuilt when the user changes; the
/// old engine is disposed (its connectivity subscription cancelled).
final Provider<SyncEngine?> syncEngineProvider = Provider<SyncEngine?>((
  Ref ref,
) {
  final String? userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return null;
  }
  final SyncEngine engine = DriftSyncEngine(
    db: ref.watch(appDatabaseProvider),
    gateway: ref.watch(syncGatewayProvider),
    connectivity: ref.watch(connectivityServiceProvider),
    userId: userId,
  );
  engine.start();
  ref.onDispose(engine.dispose);
  return engine;
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/auth/auth_repository.dart';
import 'package:sidekick/core/providers/core_providers.dart';

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (Ref ref) => SupabaseAuthRepository(
        ref.watch(supabaseClientProvider).auth,
        ref.watch(appDatabaseProvider),
      ),
    );

/// The live session state. Seeded synchronously with the cached session (so the
/// app never blocks on a network auth check), then follows auth changes.
final StreamProvider<SessionState> sessionProvider =
    StreamProvider<SessionState>(
      (Ref ref) => ref.watch(authRepositoryProvider).watch(),
    );

/// The signed-in user's id, read SYNCHRONOUSLY from the cached session — `null`
/// when signed out. Rebuilds whenever the session changes.
final Provider<String?> currentUserIdProvider = Provider<String?>((Ref ref) {
  ref.watch(sessionProvider);
  return ref.watch(authRepositoryProvider).current.userId;
});

/// The signed-in user's id, or throws if signed out. Repository providers use
/// this — they are only ever read from signed-in surfaces.
final Provider<String> requireUserIdProvider = Provider<String>((Ref ref) {
  final String? userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    throw StateError('No signed-in user; repository read while signed out.');
  }
  return userId;
});

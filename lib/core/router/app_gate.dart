import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/sync/sync_providers.dart';
import 'package:sidekick/features/profile/domain/profile.dart';
import 'package:sidekick/features/profile/preferences_providers.dart';

/// The single source of truth for the root redirect. Collapses auth, profile,
/// and first-sync state into one decision so the router never has to.
enum AppGate {
  /// Signed in, but we don't yet know if the user is new — hold on a splash.
  loading,
  login,
  onboarding,
  ready,
}

/// Decides where a session belongs.
///
/// The subtle case this exists for: sign-out wipes the local database, so a
/// returning user on a fresh install (or a second device) has NO local profile
/// row the instant they sign in. If we routed on "no local profile → onboarding"
/// we would re-run onboarding and, because that write is local-first with a
/// fresh timestamp, last-write-wins would push it up and OVERWRITE their real
/// synced preferences. So when the profile is absent we wait for the first sync
/// cycle to settle before concluding the user is genuinely new.
final Provider<AppGate> appGateProvider = Provider<AppGate>((Ref ref) {
  ref.watch(sessionProvider);
  final bool signedIn = ref.watch(authRepositoryProvider).current.isSignedIn;
  if (!signedIn) {
    return AppGate.login;
  }

  final Profile? profile = switch (ref.watch(profileProvider)) {
    AsyncData<Profile?>(:final Profile? value) => value,
    _ => null,
  };
  if (profile != null) {
    // A known local profile decides immediately — offline-safe for the common
    // case of a user opening the app on a device they already onboarded on.
    return profile.onboardingCompleted ? AppGate.ready : AppGate.onboarding;
  }

  // No local profile row yet. Only treat the user as new once the first sync
  // has settled; until then a pull may still bring their profile down. If a
  // pull later lands, [profileProvider] emits and this provider re-evaluates.
  final bool settled = !ref.watch(initialSyncSettledProvider).isLoading;
  return settled ? AppGate.onboarding : AppGate.loading;
});

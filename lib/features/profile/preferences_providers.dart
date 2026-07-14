import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/features/profile/domain/profile.dart';

/// The signed-in user's profile/preferences, live from local drift. `null`
/// until the local row exists (the gate calls `ensureExists` after sign-in).
final StreamProvider<Profile?> profileProvider = StreamProvider<Profile?>(
  (Ref ref) => ref.watch(profileRepositoryProvider).watch(),
);

/// The persona *generated-text* language preference (D2), available app-wide.
/// Defaults to English until the profile loads. UI chrome ignores this.
final Provider<PersonaLanguage> personaLanguageProvider =
    Provider<PersonaLanguage>((Ref ref) {
      final Profile? profile = _profileOrNull(ref);
      return profile?.personaResponseLanguage ?? PersonaLanguage.english;
    });

/// Whether first-run onboarding has been completed. Drives the root gate.
final Provider<bool> onboardingCompletedProvider = Provider<bool>((Ref ref) {
  final Profile? profile = _profileOrNull(ref);
  return profile?.onboardingCompleted ?? false;
});

Profile? _profileOrNull(Ref ref) => switch (ref.watch(profileProvider)) {
  AsyncData<Profile?>(:final Profile? value) => value,
  _ => null,
};

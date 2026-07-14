import 'package:meta/meta.dart';
import 'package:sidekick/core/domain/enums.dart';

/// One row per user; holds preferences (D2 persona language, theme, and the
/// additive `prefs` JSON blob for client-only UI config — SCHEMA.md §Preferences).
@immutable
class Profile {
  const Profile({
    required this.id,
    required this.personaResponseLanguage,
    required this.theme,
    required this.prefs,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final PersonaLanguage personaResponseLanguage;
  final String theme;
  final Map<String, Object?> prefs;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Onboarding writes this flag into [prefs] once the first-run step is done.
  static const String onboardingCompletedKey = 'onboarding_completed';

  bool get onboardingCompleted => prefs[onboardingCompletedKey] == true;

  Profile copyWith({
    PersonaLanguage? personaResponseLanguage,
    String? theme,
    Map<String, Object?>? prefs,
  }) => Profile(
    id: id,
    personaResponseLanguage:
        personaResponseLanguage ?? this.personaResponseLanguage,
    theme: theme ?? this.theme,
    prefs: prefs ?? this.prefs,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// LOCAL-FIRST repository for the signed-in user's [Profile]/preferences.
abstract interface class ProfileRepository {
  /// The current user's profile, or `null` until a local row exists.
  Stream<Profile?> watch();

  Future<Profile?> get();

  /// Ensure a local profile row exists (defaults) for the user, creating it
  /// LOCAL-FIRST if absent. Idempotent.
  Future<Profile> ensureExists();

  Future<void> setPersonaLanguage(PersonaLanguage language);
  Future<void> setTheme(String theme);

  /// Merge [values] into the `prefs` blob (shallow), LOCAL-FIRST.
  Future<void> mergePrefs(Map<String, Object?> values);
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/features/profile/data/profile_repository_impl.dart';
import 'package:sidekick/features/profile/domain/profile.dart';

void main() {
  late AppDatabase db;
  late ProfileRepositoryImpl profiles;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    profiles = ProfileRepositoryImpl(db: db, userId: 'u1');
  });

  tearDown(() => db.close());

  test('ensureExists creates a defaulted, dirty profile row (idempotent)', () async {
    final Profile created = await profiles.ensureExists();
    expect(created.personaResponseLanguage, PersonaLanguage.english);
    expect(created.theme, 'analog_companion');
    expect(created.onboardingCompleted, isFalse);

    await profiles.ensureExists();
    final rows = await db.select(db.profiles).get();
    expect(rows.length, 1, reason: 'ensureExists is idempotent');
    expect(rows.single.dirty, isTrue);
  });

  test('onboarding persists persona language + completion flag', () async {
    await profiles.setPersonaLanguage(PersonaLanguage.egyptianArabic);
    await profiles.mergePrefs(<String, Object?>{
      Profile.onboardingCompletedKey: true,
    });

    final Profile? saved = await profiles.get();
    expect(saved!.personaResponseLanguage, PersonaLanguage.egyptianArabic);
    expect(saved.onboardingCompleted, isTrue);
  });

  test('mergePrefs is a shallow merge that keeps prior keys', () async {
    await profiles.mergePrefs(<String, Object?>{'a': 1});
    await profiles.mergePrefs(<String, Object?>{'b': 2});

    final Profile? saved = await profiles.get();
    expect(saved!.prefs['a'], 1);
    expect(saved.prefs['b'], 2);
  });

  test('watch streams the live profile', () async {
    final Future<Profile?> firstNonNull =
        profiles.watch().firstWhere((Profile? p) => p != null);
    await profiles.setPersonaLanguage(PersonaLanguage.english);
    final Profile? profile = await firstNonNull;
    expect(profile, isNotNull);
  });
}

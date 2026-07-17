import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/auth/auth_repository.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/router/app_gate.dart';
import 'package:sidekick/core/sync/sync_providers.dart';
import 'package:sidekick/features/profile/domain/profile.dart';
import 'package:sidekick/features/profile/preferences_providers.dart';

import '../support/fakes.dart';

void main() {
  Profile profile({required bool onboarded}) => Profile(
    id: 'u1',
    personaResponseLanguage: PersonaLanguage.egyptianArabic,
    theme: 'analog_companion',
    prefs: <String, Object?>{Profile.onboardingCompletedKey: onboarded},
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  Future<AppGate> gateFor({
    required AuthRepository auth,
    Profile? Function()? profileValue,
    bool syncSettled = true,
  }) async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileProvider.overrideWith(
          (Ref ref) => Stream<Profile?>.value(
            profileValue == null ? null : profileValue(),
          ),
        ),
        initialSyncSettledProvider.overrideWith(
          (Ref ref) =>
              syncSettled ? Future<void>.value() : Completer<void>().future,
        ),
      ],
    );
    addTearDown(container.dispose);
    // Keep the graph alive so the async leaves resolve and the gate recomputes.
    container.listen(appGateProvider, (_, _) {});
    await pumpEventQueue();
    return container.read(appGateProvider);
  }

  test('signed out routes to login', () async {
    expect(
      await gateFor(auth: FakeAuthRepository.signedOut()),
      AppGate.login,
    );
  });

  test('signed in with an onboarded local profile is ready', () async {
    expect(
      await gateFor(
        auth: FakeAuthRepository.signedIn('u1'),
        profileValue: () => profile(onboarded: true),
      ),
      AppGate.ready,
    );
  });

  test('signed in with a not-yet-onboarded profile routes to onboarding', () async {
    expect(
      await gateFor(
        auth: FakeAuthRepository.signedIn('u1'),
        profileValue: () => profile(onboarded: false),
      ),
      AppGate.onboarding,
    );
  });

  test(
    'signed in with no local profile HOLDS on loading until sync settles',
    () async {
      expect(
        await gateFor(
          auth: FakeAuthRepository.signedIn('u1'),
          syncSettled: false,
        ),
        AppGate.loading,
        reason: 'a returning user must not be treated as new before the pull',
      );
    },
  );

  test(
    'signed in with no local profile AFTER sync settles routes to onboarding',
    () async {
      expect(
        await gateFor(auth: FakeAuthRepository.signedIn('u1')),
        AppGate.onboarding,
      );
    },
  );
}

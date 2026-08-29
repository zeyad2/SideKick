# Phase 5 Android Dogfood Hardening

## Status

BLOCKED

## Summary

The automated Android hardening gates pass and two concrete reliability bugs
were fixed: durable audio captures now enter drafting without requiring the
Capture screen, transient network/Gemini failures retry when connectivity
returns, crash-stale `processing` captures recover, completed native capture
journal entries are acknowledged, scheduler failures no longer masquerade as
user dismissals, and Android 13+ notification delivery exits safely when
notification permission is denied instead of risking a receiver crash.

Phase 5 cannot pass yet because no physical Android device was attached. A
Pixel 10 AVD was found and used for an emulator preflight, but the phase
objective and manual acceptance explicitly require real-device evidence for
lock-screen/background capture, notification actions, geofences, dwell, and
reboot behavior. The preflight also found that the `SUPABASE_URL` in `.env`
currently resolves to `NXDOMAIN`, which blocks sign-up and every authenticated
manual flow until the backend configuration is repaired.

## Deliverables completed

- [ ] Run real-device Android acceptance (blocked: no Android device attached).
- [x] Harden capture reliability for automatic audio drafting and online retry.
- [x] Harden notification-permission denial behavior.
- [x] Preserve scheduler, geofence, sync, and correction regression coverage.
- [x] Freeze feature additions for two weeks, 2026-08-24 through 2026-09-07.
- [x] Keep non-POC directions in `docs/FUTURE_PLANS.md`.
- [x] Add `docs/reports/DOGFOOD_LOG.md`.

## Tests run

- `C:\src\flutter\bin\flutter.bat emulators`: found the `Pixel_10` AVD.
- `C:\src\flutter\bin\flutter.bat devices`: found the booted Android emulator
  in addition to desktop/web targets; no physical Android hardware was found.
- `C:\src\flutter\bin\flutter.bat test`: PASS, 113 tests after Phase 5
  hardening (including scheduler, sync, and static cleanup regressions).
- `C:\src\flutter\bin\flutter.bat test test\reminders\audio_reminder_retry_controller_test.dart`:
  PASS, 4 tests.
- `C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze`: PASS, no issues
  after the Phase 5 Dart changes.
- `C:\src\flutter\bin\flutter.bat analyze`: PASS, no issues after Phase 5
  hardening.
- `android\.\gradlew.bat :app:testDebugUnitTest --rerun-tasks`: PASS, including
  Android 13 notification-permission denial and reminder runtime regressions.
- `supabase test db`: PASS, 4 files / 10 pgTAP tests.
- `C:\src\flutter\bin\flutter.bat build apk --debug --dart-define-from-file=.env`:
  PASS; produced the configured
  `build/app/outputs/flutter-apk/app-debug.apk`.
- `git diff --check`: PASS.

The system Flutter SDK had to run outside the managed sandbox because its host
cache hangs when isolated. The repository-local `.tooling/flutter` checkout is
incomplete and contains packages but no Flutter executable.

## Device and Android version

- Emulator: Android Studio AVD `Pixel_10`, reported model
  `sdk_gphone16k_x86_64`.
- Emulator Android version/API level: Android 17 / API 37.
- Physical device model and Android version: NOT AVAILABLE.
- Detection evidence: ADB contained only `emulator-5554`; no physical serial
  was attached.

## Permission state

NOT AVAILABLE on physical hardware. On the emulator, notification, microphone,
precise location, and background location were all denied; the signed-out app
launched and relaunched after reboot without a Flutter or native crash. The
accessibility service could be enabled and remained enabled across the emulator
reboot. Automated Android coverage verifies that a denied Android 13+
notification permission does not crash reminder delivery. The Settings UI
continues to expose microphone, notification, foreground location, background
location, accessibility, and battery states.

## Battery optimization state

NOT AVAILABLE on physical hardware. The state and exemption settings path are
present, but OEM behavior remains unverified.

## Manual acceptance

The rows below remain physical-device requirements. The Pixel 10 AVD preflight
does not convert any of them to PASS.

- [ ] Shortcut capture from lock screen — NOT RUN.
- [ ] Shortcut capture from background — NOT RUN.
- [ ] Shortcut capture inside another app — NOT RUN.
- [ ] Typed reminder creation — NOT RUN.
- [ ] Audio reminder creation — NOT RUN.
- [ ] Multi-task audio capture — NOT RUN.
- [ ] Time reminder fires — NOT RUN.
- [ ] Enter geofence reminder fires — NOT RUN.
- [ ] Exit geofence reminder fires — NOT RUN.
- [ ] Dwell filtering works — NOT RUN.
- [ ] Done/Later/Dismiss/Wrong Place actions work — NOT RUN.
- [ ] Reboot/app restart restores active reminders — NOT RUN.
- [ ] Offline capture retries AI processing when online — NOT RUN on hardware;
  automated controller coverage passes.
- [ ] Removed features absent from navigation/settings — NOT RUN manually;
  static Flutter regression coverage passes.

Use `docs/reports/DOGFOOD_LOG.md` to record the first hardware session.

## Bugs fixed during hardening

1. Saved native audio was ingested durably but did not automatically enter the
   reminder drafting pipeline. `AudioReminderRetryController` now listens to
   durable capture events and processes the associated capture row.
2. Pending audio and transient transport/Gemini failures did not retry when
   connectivity returned. The controller performs a cold-start/online sweep
   and listens for connectivity recovery. Unclear-audio failures remain in the
   explicit user retry flow and are never automatically retried.
3. The native reminder receiver attempted to post on Android 13+ without first
   checking `POST_NOTIFICATIONS`. It now exits safely when permission is denied.
4. A process death during AI drafting could leave a durable audio capture stuck
   in `processing`. Startup/online recovery now treats `processing` audio as a
   crash-stale lease while the in-process ID guard prevents concurrent retries.
5. Successfully processed native captures could remain in the native journal
   indefinitely. The capture event now carries its native event ID, terminal
   replay acknowledges already-ready rows, and the lifecycle retry controller
   acknowledges matching journal entries after successful processing.
6. Scheduler registration failures were written as `dismissed` reminder events,
   polluting user feedback and later AI context. Resync now keeps operational
   failures separate from the Done/Later/Dismiss/Wrong Place event contract;
   permission state remains visible in Settings.
7. Sign-out could drain native ingestion while an untracked AI draft future
   continued beyond the database wipe. Audio drafting and ACK now hold the same
   auth-transition lease, controller disposal joins live futures, and a lease
   invalidated by sign-out suppresses journal ACK so replay remains available.
8. A narrower sign-out race existed before the controller acquired that lease:
   a delayed capture-row lookup could resume after wipe/reopen. Live callbacks
   now acquire the lease synchronously before their first await, lookup futures
   are tracked and joined, and cold/online retry sweeps protect their initial
   database read under the same lease.
9. The app shell instantiated the user-owned reminder scheduler while signed
   out. A configured APK therefore reached the login route and then failed with
   `No signed-in user; repository read while signed out`. Scheduler lifecycle is
   now auth-gated, detached on sign-out, and covered by a signed-out shell
   regression.

## Pixel 10 emulator preflight

- PASS: booted `Pixel_10`, installed the configured debug APK, and verified the
  signed-out login semantics through Android UI automation.
- PASS: denied notification, microphone, precise-location, and background-
  location permissions; launch remained crash-free.
- PASS: rebooted Android, verified boot completion, and relaunched to the
  signed-out login route without a Flutter/native crash.
- PASS: enabled the accessibility service and verified it remained enabled
  after reboot.
- BLOCKED: sign-up displayed the app's safe `No connection` state because the
  configured Supabase hostname returns DNS `NXDOMAIN` from both host and AVD.
- INCONCLUSIVE: an ADB `input keyevent` changes volume but bypasses Android's
  accessibility key filter. Raw input injection requires root, and this Play
  image forbids root, so triple-volume shortcut behavior was not claimed.
- NOT RUN: authenticated typed/audio reminders, delivery/actions, geofences,
  dwell, sync, and offline retry because authentication cannot complete.
- Evidence: `build/dogfood-post-reboot.xml` contains the post-reboot
  `Welcome back.` login semantics. Emulator `screencap` rendered the Flutter
  surface black, so XML semantics and system/logcat state were used instead of
  a misleading screenshot.

## Changed contracts

- Added lifecycle-owned `AudioReminderRetryController` with `start`,
  `retryEligible`, and `dispose` behavior.
- Added `audioReminderRetryControllerProvider`; `SidekickApp` keeps it alive for
  the signed-in capture owner.
- `CapturedAudioEvent` now includes `nativeEventId` so journal ownership can be
  handed off only after durable processing succeeds.
- No schema, sync, route, scheduler, or AI JSON contract changed.

## Bugs deferred after freeze

- The configured Supabase project hostname is unavailable (`NXDOMAIN`), so the
  backend URL must be corrected before authenticated dogfood can begin.
- Physical-device notification, proximity-alert geofence, dwell, OEM power,
  and reboot behavior remain unverified. This is the Phase 5 blocker, not an
  accepted product debt.
- Google Play Services geofencing remains deferred unless device dogfood proves
  `LocationManager.addProximityAlert` unreliable; the existing Phase 3 debt
  entry owns that decision.
- Android/Gradle plugin deprecation warnings remain build-tooling debt; they do
  not fail the current Android build and are outside the dogfood defect scope.

## Known debt

- External Gemini context consent hardening remains logged in `TECH_DEBT.md`.
- The repository-local Flutter checkout is not executable; host Flutter is the
  current reproducible toolchain.

## Recommendation

Continue Android dogfood after attaching a physical Android device. Do not
start the iOS proof or revisit product scope until the full manual checklist has
evidence. If proximity enter/exit is unreliable on that device, replace the
deprecated proximity-alert implementation with Play Services geofencing before
continuing the dogfood window.

## Smallest fixes needed to unblock Phase 5

1. Correct `SUPABASE_URL` to a live project endpoint and verify sign-up/sign-in.
2. Attach a physical Android device with USB debugging enabled.
3. Install the current configured debug build and record device, Android, permission, and
   battery-optimization state in `DOGFOOD_LOG.md`.
4. Execute every manual acceptance row across foreground, background, locked,
   killed, offline/online, and reboot states.
5. Fix only failures in the Phase 5 hardening categories, rerun the automated
   gates, and update this report to PASS or PASS-WITH-DEBT.

## Next phase handoff

There is no next phase handoff while this report is BLOCKED. Resume Phase 5
from `docs/reports/DOGFOOD_LOG.md`, then read the Phase 3 scheduler report and
this report before changing runtime code.

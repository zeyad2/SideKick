# Sidekick Android Dogfood Log

Use one copy of the session section for each dogfood run. Record observed
results; do not infer a pass from an automated test.

## Emulator preflight - 2026-08-25

This is diagnostic preflight evidence only. It does not satisfy the physical-
device acceptance gate.

- Date/time and timezone: 2026-08-25, Africa/Cairo
- Tester: Codex emulator preflight
- App commit/build: dirty workspace debug APK built with
  `--dart-define-from-file=.env`
- Device manufacturer/model: Google Pixel 10 AVD
  (`sdk_gphone16k_x86_64`)
- Android version/API level: Android 17 / API 37
- Sidekick notification permission: denied
- Microphone permission: denied
- Precise foreground location: denied
- Background location: denied
- Accessibility shortcut service: enabled; persisted across emulator reboot
- Battery optimization: optimized (not found in device-idle whitelist)
- Network at start: AndroidWifi; later validated with public DNS/ICMP
- OEM power-saving mode: emulator default

| Emulator check | Result | Evidence / notes |
| --- | --- | --- |
| Configured APK install and signed-out launch | PASS | Login semantic tree exposed `Welcome back.` with no crash. |
| Signed-out scheduler lifecycle | FAIL, FIXED | Initial configured build threw `No signed-in user; repository read while signed out`; auth-gated scheduler fix and regression now pass. |
| Notification/microphone/location denied launch | PASS | All four runtime permissions denied; post-reboot launch had no Flutter/native fatal error. |
| Account creation | BLOCKED | App safely displayed `No connection`; configured Supabase hostname returns DNS `NXDOMAIN` on host and AVD. |
| Android reboot and signed-out relaunch | PASS | `sys.boot_completed=1`, `ro.boot.bootreason=reboot,shell`, then login semantics returned. |
| Accessibility service survives reboot | PASS | Service remained in Android's enabled-services set. |
| Triple-volume shortcut | NOT RUN | High-level ADB key events bypass accessibility filtering; raw events require root unavailable on the Play image. |
| Authenticated reminders/geofences/actions/sync | BLOCKED | Authentication cannot complete until the Supabase endpoint is corrected. |

Artifacts: `build/dogfood-post-reboot.xml`, `build/dogfood-sidekick-login.xml`,
and the configured debug APK at `build/app/outputs/flutter-apk/app-debug.apk`.

---

## Device baseline

- Date/time and timezone:
- Tester:
- App commit/build:
- Device manufacturer/model:
- Android version/API level:
- Sidekick notification permission: granted / denied / limited
- Microphone permission: granted / denied
- Precise foreground location: granted / denied
- Background location: granted / denied
- Accessibility shortcut service: enabled / disabled
- Battery optimization: exempt / optimized / unknown
- Network at start: Wi-Fi / mobile / offline
- OEM power-saving mode:

## Acceptance session

| Check | Result | Evidence / timestamp / notes |
| --- | --- | --- |
| Shortcut capture from lock screen | NOT RUN | |
| Shortcut capture while Sidekick is backgrounded | NOT RUN | |
| Shortcut capture inside another app | NOT RUN | |
| Typed reminder creation | NOT RUN | |
| Audio reminder creation | NOT RUN | |
| Multi-task audio capture | NOT RUN | |
| Time reminder delivery | NOT RUN | |
| Enter-geofence reminder delivery | NOT RUN | |
| Exit-geofence reminder delivery | NOT RUN | |
| Dwell delay and early-transition cancellation | NOT RUN | |
| Done notification action | NOT RUN | |
| Later notification action and two-hour reschedule | NOT RUN | |
| Dismiss action without deletion | NOT RUN | |
| Wrong Place opens the correct edit flow | NOT RUN | |
| App restart restores active reminders | NOT RUN | |
| Device reboot restores active reminders | NOT RUN | |
| Offline audio capture drafts after connectivity returns | NOT RUN | |
| Removed features absent from navigation/settings | NOT RUN | |

Allowed results: `PASS`, `FAIL`, `NOT RUN`, or `BLOCKED`. For geofence checks,
record the test coordinates/radius, transition time, notification time, and
whether the screen was locked.

## Defect

- ID:
- Severity: blocker / high / medium / low
- Acceptance check:
- Expected:
- Observed:
- Reproduction steps:
- Frequency:
- App state: foreground / background / killed / locked
- Network and permission state:
- Relevant logcat excerpt or screenshot:
- Resolution: fixed / deferred / cannot reproduce
- Fix verification build:

## Session recommendation

- Continue dogfood / build iOS proof / revisit product scope:
- Blocking defects:
- Deferred non-POC requests added to `docs/FUTURE_PLANS.md`:
- Next device/session:

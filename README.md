# Sidekick

Sidekick is an Android-first POC for smart task reminders.

The active product loop is intentionally small:

1. Type or capture a reminder once.
2. Let Sidekick infer the task, time, and place trigger.
3. Show a short correction window before activation.
4. Remind at the right moment and learn from Done, Later, Dismiss, and Wrong place actions.

Everything outside that loop is future work and belongs in
[docs/FUTURE_PLANS.md](docs/FUTURE_PLANS.md).

## Current Truth

- [Agent operating manual](AGENTS.md) — start here before changing code
- [POC spec](docs/POC_SPEC.md)
- [POC phases](docs/POC_PHASES.md)
- [Future plans](docs/FUTURE_PLANS.md)
- [Technical debt ledger](TECH_DEBT.md)
- [Legacy companion v1 archive](docs/archive/legacy-companion-v1/)

## Engineering Docs

- [Architecture](docs/ARCHITECTURE.md) — layers, the four runtimes, the reminder
  loop end to end
- [Code map](docs/CODE_MAP.md) — what lives where, and what to add where
- [Conventions](docs/CONVENTIONS.md) — the rules that keep this from breaking
- [Runtime contracts](docs/RUNTIME_CONTRACTS.md) — Dart↔Kotlin, Dart↔Postgres,
  Dart↔Gemini
- [Testing](docs/TESTING.md) — commands, layering, and known coverage gaps
- [Code review 2026-08-29](docs/reports/CODE_REVIEW_2026-08-29.md) — current
  open findings

## POC Scope

Active:

- Auth/profile and onboarding gate
- Theme and app shell
- Local-first sync foundation
- Android hardware/audio capture shortcut
- Gemini transport
- Captures
- Task reminders
- Places
- Settings
- Events

Deferred:

- Habits and Fresh Start
- Done list as a product surface
- Goals
- Notes
- Focus sessions and body double
- App blocking
- Vibe checks
- Persona chat, TTS, and talk-back
- Insights
- iOS proof
- Additional themes
- Broad non-reminder capture decomposition

## Toolchain

- Flutter 3.44.6 stable
- Dart 3.12.2 with sound null safety
- Android minimum SDK 26

Dependencies are resolved in `pubspec.lock`.

## Run

```text
flutter pub get
flutter run --dart-define-from-file=.env
```

Runtime config is read from a gitignored `.env` at the repo root. See
`.env.example` for required keys.

## Verify

```text
dart analyze
flutter analyze
flutter test test/app_shell_test.dart test/static/poc_cleanup_test.dart test/router/app_gate_test.dart
```

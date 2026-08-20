# Phase 0 Repo Reset

## Status

PASS-WITH-DEBT

## Summary

Reset the active repo story around the Android reminder POC. The README now
points to current POC docs, legacy planning/review docs live under the archive,
and the app shell/router expose only POC destinations. The active capture screen
no longer presents habit/goal/note triage; it shows typed reminder entry, audio
capture, and saved audio capture status until Phase 2 builds the real drafting
loop.

Automated verification uses the machine Flutter SDK at
`C:\src\flutter\bin\flutter.bat` because neither `dart` nor `flutter` is on
PATH and `.tooling/flutter` does not contain `bin/flutter.bat`.

## Deliverables completed

- [x] Created `docs/POC_SPEC.md`.
- [x] Kept `docs/POC_PHASES.md` as the phase source of truth.
- [x] Created `docs/FUTURE_PLANS.md`.
- [x] Moved legacy planning/review docs into
  `docs/archive/legacy-companion-v1/`.
- [x] Rewrote `README.md` around the reminder POC.
- [x] Removed active routes for habits, Fresh Start, Done list, goals, notes,
  focus sessions, app blocking, vibe checks, and old multi-kind capture review.
- [x] Removed removed-feature repositories from the active repository provider
  registry.
- [x] Restricted the active sync registry to POC tables only.
- [x] Kept active references to auth/profile, theme/shell, local-first sync,
  Android capture shortcut, Gemini transport, captures, task reminders, places,
  settings, and events.
- [x] Added future-plan entries for removed product directions.

## Tests run

- `dart analyze`: PASS via `C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze`.
- `flutter analyze`: PASS via `cmd /c C:\src\flutter\bin\flutter.bat analyze`.
- `flutter test test\app_shell_test.dart test\static\poc_cleanup_test.dart test\router\app_gate_test.dart`:
  PASS via `cmd /c C:\src\flutter\bin\flutter.bat test ...`.
- `dart analyze`: FAIL when run without an explicit SDK path. `dart` command
  is not available in this shell.
- `flutter analyze`: FAIL when run without an explicit SDK path. `flutter`
  command is not available in this shell.
- `.\.tooling\flutter\bin\dart.bat analyze`: FAIL. The repo tooling checkout
  does not contain `bin/dart.bat`.
- `.\.tooling\flutter\bin\flutter.bat analyze`: FAIL. The repo tooling checkout
  does not contain `bin/flutter.bat`.
- `where.exe dart`: FAIL. No Dart executable found on PATH.
- `where.exe flutter`: FAIL. No Flutter executable found on PATH.
- `rg "features/(habits|goals|notes|focus)/" lib/core/router lib/app.dart lib/features/shell lib/features/inbox/presentation lib/features/inbox/application/inbox_providers.dart -n`:
  PASS. No active router/shell/capture-screen imports from removed feature
  packages.
- `rg "label: '(Habits|Fresh Start|Done|Goals|Notes|Focus|App blocking|Vibe)'" lib/features/shell/presentation/app_shell.dart -n`:
  PASS. No removed destinations remain in the app shell labels.
- `rg "\[[^\]]+\]\(([^)]*\.md)\)" README.md -n`: PASS. README markdown links
  point only to POC docs.

## Manual acceptance

- Needs Android launch check to confirm navigation is POC-only.
- Needs human check that archived docs are findable under
  `docs/archive/legacy-companion-v1/` and not presented as current truth.

## Changed contracts

- Active route destinations are now:
  - `Capture` at `/capture`
  - `Reminders` at `/reminders`
  - `Places` at `/places`
  - `Settings` at `/settings`
- Auth routes remain:
  - `/splash`
  - `/login`
  - `/forgot-password`
  - `/onboarding`
- `README.md` current docs contract now links to:
  - `docs/POC_SPEC.md`
  - `docs/POC_PHASES.md`
  - `docs/FUTURE_PLANS.md`
  - `docs/archive/legacy-companion-v1/`
- `docs/FUTURE_PLANS.md` is the required home for non-POC ideas.
- Active repository provider registry now exposes:
  - `capturesRepositoryProvider`
  - `placesRepositoryProvider`
  - `taskRemindersRepositoryProvider`
  - `reminderEventsRepositoryProvider`
  - `conversationRepositoryProvider`
  - `profileRepositoryProvider`
- Active sync registry now includes:
  - `profiles`
  - `captures`
  - `places`
  - `task_reminders`
  - `reminder_events`
  - `conversations`
  - `messages`
  - `events`

## Archived docs

- `CAPTURE_DECOMPOSITION.md`
- `CONVENTIONS.md`
- `DATA_CONTRACT.md`
- `ERD.md`
- `EVENTS.md`
- `PHASE_1_REVIEW.md`
- `PHASE_2_REVIEW.md`
- `PHASE_3_REVIEW.md`
- `PHASE_4_REVIEW.md`
- `PHASE_5_REVIEW.md`
- `project_audit_poc_reset.html`
- `rubrics.md`
- `SCHEMA.md`
- `SCREENS.md`
- `SIDEKICK_BUILD_PLAN.md`
- `STITCH_PROMPTS.md`
- `techdebt.md`

## Known debt

- Phase 1 owns completing and reporting the fresh POC schema/repository reset
  that is now in progress in the working tree.
- Phase 2 owns replacing the placeholder typed reminder action with the shared
  typed/audio drafting pipeline.
- Phase 2 owns removing the legacy multi-kind capture processing path or
  converting it to task-reminder-only drafting.
- Local verification should keep using `C:\src\flutter\bin\flutter.bat` or add
  that SDK to PATH.

## Removed feature folders that still have references

- Phase 1 has removed the legacy habits, goals, notes, focus, task, app-blocking
  repository/data implementations from `lib/`.
- Phase 1 has removed the legacy multi-kind capture triage implementation from
  `lib/features/inbox/application/`.

## Deliberately retained legacy code

- No legacy feature implementation remains active in `lib/`.
- Archived legacy docs remain under `docs/archive/legacy-companion-v1/`.

## Next phase handoff

Read first:

- `docs/POC_SPEC.md`
- `docs/POC_PHASES.md`
- `docs/FUTURE_PLANS.md`
- `docs/reports/PHASE_0_repo_reset.md`

Phase 1 can depend on the active route set being POC-only and should verify the
fresh POC schema/repository reset now present in the working tree:
`AppDatabase.schemaVersion == 1`, `supabase/migrations/0001_poc_baseline.sql`,
and repository providers for captures, places, task reminders, reminder events,
conversations, and profile.

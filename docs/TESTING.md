# Testing

## Commands

```
C:\src\flutter\bin\dart.bat analyze
C:\src\flutter\bin\flutter.bat test
C:\src\flutter\bin\flutter.bat run --dart-define-from-file=.env     # or phone.cmd
```

The Flutter SDK is at `C:\src\flutter` and is not on `PATH`. `--dart-define-from-file=.env`
is mandatory — without it `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and
`GEMINI_API_KEY` are empty strings, the app silently runs with no backend, and
drafting silently falls back to the heuristic service.

Kotlin unit tests (Robolectric) live in `android/app/src/test/kotlin/` and are
**not** run by `flutter test`. Run them through Gradle when you touch native code.

pgTAP suites in `supabase/tests/` need a database and are run against the
Supabase project, not locally by default.

Status as of 2026-08-29: `dart analyze` clean, 119 Flutter tests passing.

## Where a test belongs

| What you changed | Test it here |
|---|---|
| A repository query or mutation | `test/data/repositories_test.dart` — real in-memory drift |
| Drift schema / a migration | `test/schema/column_parity_test.dart` |
| RLS, policies, constraints | `supabase/tests/*.sql` **and** `test/schema/supabase_policy_test.dart` (which asserts the migration text) |
| Sync engine behaviour | `test/sync/sync_engine_test.dart` — real drift + `FakeSyncGateway` |
| Creation / auto-commit / review flow | `test/reminders/reminder_creation_service_test.dart` |
| Scheduling, notification actions, dwell | `test/reminders/reminder_scheduler_test.dart` |
| AI context bounding and redaction | `test/reminders/assistant_context_builder_test.dart` |
| Prompt/response validation | `reminder_creation_service_test.dart` (uses the `@visibleForTesting` hooks `validateDraftJson`, `parseGeminiResponseForTesting`, `promptForTesting`) |
| A screen | `test/inbox/inbox_ui_test.dart`, `test/reminders/reminders_ui_test.dart`, `test/app_shell_test.dart` |
| Routing / the gate | `test/router/app_gate_test.dart` |
| Native Kotlin | `android/app/src/test/kotlin/…` |
| Scope (nav, imports, sync registry) | `test/static/poc_cleanup_test.dart` |

`test/support/fakes.dart` holds the shared in-memory doubles. Prefer them over a
mocking framework; there is no mocking package in `pubspec.yaml` and there should
not be one.

## How the layers are tested

- **Repositories and sync** run against a real in-memory drift database
  (`AppDatabase.forTesting(NativeDatabase.memory())`). Do not fake drift.
- **Application services** take interfaces, so they are tested with fakes plus,
  where transactional behaviour matters, a real database and
  `atomically: db.transaction`.
- **The platform boundary** (`ReminderSchedulePlatform`,
  `NativeCaptureApi`) is faked. Nothing in `test/` talks to a MethodChannel.
- **The AI boundary** is tested through `HeuristicReminderDraftService` and the
  visible-for-testing validators. No test issues an HTTP request.

## Known gaps — do not assume coverage here

These are real holes, listed so nobody reads a green suite as broader assurance
than it is:

1. **No test round-trips a payload against real Postgres types.** The schema tests
   assert the *text* of the migration, not that a pushed row is accepted.
2. **`handleGeofenceTrigger` and its dwell logic are tested but dead.** Production
   dwell lives in `ReminderRuntimeBridge.recordDwellTransition` / `isDwellReady`
   with different semantics. The passing test proves nothing about shipped
   behaviour — the most dangerous kind of coverage.
3. **Place deletion is untested.** Nothing asserts what happens to a reminder or a
   registered geofence when its place is soft-deleted.
4. **`poc_cleanup_test.dart:92` matches Windows path separators only**
   (`'features\\conversations\\data'`). That guard silently no-ops on macOS/Linux
   or in CI.
5. **No coverage of the sign-out failure path** — whether the local wipe happens
   when `_auth.signOut()` throws.

## Harness notes

- `flutter test` prints a drift warning about `AppDatabase` being created more
  than once. It comes from tests that build several databases in one process; the
  executors are distinct so it is benign, but do not let a real duplicate hide
  behind it.
- Widget tests must supply a theme via `AppThemeRegistry` and override the
  user-scoped providers; `requireUserIdProvider` throws when signed out.
- Anything time-dependent takes an injected `clock` (`clockProvider`,
  `LocalFirstRepository.clock`). Never call `DateTime.now()` in code you intend
  to test.

## Before opening a PR

1. `dart analyze` — clean.
2. `flutter test` — all pass.
3. Kotlin tests if you touched `android/`.
4. A test that fails without your fix, for anything you fixed.
5. `TECH_DEBT.md` updated if you left debt; a `docs/reports/` entry if you closed
   a phase.

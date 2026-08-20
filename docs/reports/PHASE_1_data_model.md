# Phase 1 Data Model

## Status

PASS-WITH-DEBT

## Summary

Replaced the broad companion data model with a fresh reminder-first POC model.
Drift is reset to schema version 1, Supabase migrations are reset to one POC
baseline, active sync is limited to POC tables, and active repositories now map
to captures, places, task reminders, reminder events, conversations/messages,
and profile.

## Deliverables completed

- [x] Reset Drift schema to version 1.
- [x] Replaced Supabase migrations with `0001_poc_baseline.sql`.
- [x] Added POC tables: `profiles`, `places`, `captures`, `task_reminders`,
  `reminder_events`, `conversations`, `messages`, and `events`.
- [x] Added local-only Drift sync columns: `dirty`, `synced_at`.
- [x] Added POC repositories:
  `TaskRemindersRepository`, `PlacesRepository`, `CapturesRepository`,
  `ReminderEventsRepository`, `ConversationRepository`, `ProfileRepository`.
- [x] Removed active repositories and data code for tasks, notes, goals, habits,
  habit completions, focus sessions, vibe checks, and app blocking.
- [x] Updated sync table registry to POC syncable tables only.
- [x] Restored server-side LWW/clock-skew guard in the POC Supabase baseline.
- [x] Expanded Supabase SQL isolation scripts to cover all POC tables.
- [x] Kept `events` and `reminder_events` append-only from repository/sync
  perspective.
- [x] Kept `conversations` and `messages` stored but unused by UI.

## Tests run

- `C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze`: PASS.
- `cmd /c C:\src\flutter\bin\flutter.bat analyze`: PASS.
- `cmd /c C:\src\flutter\bin\flutter.bat test`: PASS, 73 tests.
- `cmd /c C:\src\flutter\bin\flutter.bat test test\schema\column_parity_test.dart test\data\repositories_test.dart test\sync\sync_engine_test.dart test\events\events_contract_test.dart test\capture\capture_event_contract_test.dart test\data\preferences_test.dart test\data\wipe_on_logout_test.dart test\app_shell_test.dart test\static\poc_cleanup_test.dart test\router\app_gate_test.dart test\inbox\inbox_ui_test.dart`:
  PASS, 39 tests.
- `cmd /c supabase start`: PASS on 2026-08-20 with Supabase CLI `2.109.1`;
  applied `supabase/migrations/0001_poc_baseline.sql` to the local stack.
- `cmd /c supabase db reset`: PASS on 2026-08-20.
- `docker exec supabase_db_SideKick psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /tmp/sidekick-tests/10_rls_isolation.sql -f /tmp/sidekick-tests/20_fk_ownership.sql -f /tmp/sidekick-tests/30_sync_guards.sql`:
  PASS on 2026-08-20. Output included `ALL POC RLS TESTS PASSED`,
  `ALL POC FK TESTS PASSED`, and `ALL POC SYNC-GUARD TESTS PASSED`.

Verification notes:

- `supabase/tests/00_bootstrap_auth.sql` is a plain-Postgres bootstrap helper,
  not needed on local Supabase, where `auth` already exists.
- `cmd /c supabase test db` is not the correct harness for these raw `psql`
  scripts because it expects pgTAP output and reports `No plan found in TAP
  output`.
- A 2026-08-20 re-run of
  `cmd /c C:\src\flutter\bin\flutter.bat test ...` did not emit runner output
  after two minutes in this shell and was stopped; no Dart/Flutter source changed
  during the SQL fixture fix. `C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe
  analyze` still passed.

## Manual acceptance

- Existing local DB can be wiped/recreated with the fresh schema. Covered by
  `test/data/wipe_on_logout_test.dart`; still needs a real installed app DB
  wipe on device.
- App sign-in/profile/shell path is covered by auth gate and shell tests; still
  needs Android device sign-in smoke test.

## Changed contracts

- Drift schema version: `1`.
- Drift schema source: `lib/core/db/tables.dart`.
- Drift generated mirror: `lib/core/db/app_database.g.dart`.
- Supabase baseline migration: `supabase/migrations/0001_poc_baseline.sql`.
- Normal synced cloud tables use `public.sync_lww_guard()` for stale-write
  rejection and future timestamp clamping.
- `events` and `reminder_events` have owner read/insert policies only.
- Active sync tables:
  - `profiles`
  - `places`
  - `captures`
  - `task_reminders`
  - `reminder_events`
  - `conversations`
  - `messages`
  - `events`
- Active repository providers:
  - `capturesRepositoryProvider`
  - `placesRepositoryProvider`
  - `taskRemindersRepositoryProvider`
  - `reminderEventsRepositoryProvider`
  - `conversationRepositoryProvider`
  - `profileRepositoryProvider`

## Final table list

- `profiles`
- `places`
- `captures`
- `task_reminders`
- `reminder_events`
- `conversations`
- `messages`
- `events`
- `sync_meta` local-only Drift table

## Final repository list

- `CapturesRepository` / `CapturesRepositoryImpl`
- `PlacesRepository` / `PlacesRepositoryImpl`
- `TaskRemindersRepository` / `TaskRemindersRepositoryImpl`
- `ReminderEventsRepository` / `ReminderEventsRepositoryImpl`
- `ConversationRepository` / `ConversationRepositoryImpl`
- `ProfileRepository` / `ProfileRepositoryImpl`
- `EventsRepository` / `DriftEventsRepository`

## Old tables/repositories intentionally left behind

- None in active `lib/` code.
- Legacy review/planning docs remain archived in
  `docs/archive/legacy-companion-v1/`.

## Migration reset notes

- Removed legacy migration files `0001_initial_schema.sql`,
  `0002_events_log.sql`, `0003_sync_guards.sql`, and
  `0004_capture_decomposition.sql`.
- Added `0001_poc_baseline.sql`.
- No data preservation path is included; the POC reset allows a fresh schema.

## Supabase dashboard/manual steps required

- Reset the Supabase project/database before applying
  `supabase/migrations/0001_poc_baseline.sql`.
- On a real Supabase project, apply the baseline and run
  `supabase/tests/10_rls_isolation.sql`,
  `supabase/tests/20_fk_ownership.sql`, and
  `supabase/tests/30_sync_guards.sql` through `psql -v ON_ERROR_STOP=1`.
  Use `supabase/tests/00_bootstrap_auth.sql` only for a plain Postgres runner
  that does not already provide Supabase's `auth` schema.
- Confirm RLS policies are present for every POC table in the Supabase
  dashboard.

## Known debt

- None blocking Phase 2.

## Next phase handoff

Read first:

- `docs/POC_SPEC.md`
- `docs/POC_PHASES.md`
- `docs/reports/PHASE_1_data_model.md`
- `lib/features/reminders/domain/task_reminder.dart`
- `lib/features/inbox/domain/capture.dart`
- `lib/core/sync/syncable_tables.dart`

Phase 2 should build typed/audio reminder drafting on top of
`CapturesRepository` and `TaskRemindersRepository`. It should not revive
habit/goal/note classification; every extracted item must become a
`task_reminders` draft or review item.

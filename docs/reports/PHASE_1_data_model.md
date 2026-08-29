# Phase 1 Data Model

## Status

PASS

## Summary

Replaced the broad companion data model with a fresh reminder-first POC model.
Drift is on POC schema version 2, Supabase migrations are the POC baseline plus
an idempotent reviewed-draft approval migration, active sync is limited to POC
tables, and active repositories now map to captures, places, task reminders,
reminder events, conversations/messages, and profile.

## Deliverables completed

- [x] Reset Drift schema to POC version 2.
- [x] Replaced Supabase migrations with `0001_poc_baseline.sql` and added
  idempotent `0002_task_reminder_draft_ids.sql`.
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
- [x] Added `task_reminders.draft_id` and a unique owner/capture/draft index
  so reviewed-draft approval is idempotent at the database boundary.

## Tests run

- `C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze`: PASS.
- `cmd /c C:\src\flutter\bin\flutter.bat analyze`: PASS.
- `C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze`: PASS, no issues.
- `C:\src\flutter\bin\flutter.bat analyze`: PASS, no issues, run outside
  sandbox after in-sandbox Flutter commands hung silently.
- `C:\src\flutter\bin\flutter.bat test`: PASS, 91 tests, run outside sandbox.
- `C:\src\flutter\bin\flutter.bat test`: PASS, 104 tests, run outside sandbox
  after the final Phase 1-4 remediation pass.
- `cmd /c C:\src\flutter\bin\flutter.bat test test\schema\column_parity_test.dart test\data\repositories_test.dart test\sync\sync_engine_test.dart test\events\events_contract_test.dart test\capture\capture_event_contract_test.dart test\data\preferences_test.dart test\data\wipe_on_logout_test.dart test\app_shell_test.dart test\static\poc_cleanup_test.dart test\router\app_gate_test.dart test\inbox\inbox_ui_test.dart`:
  PASS, 39 tests.
- `supabase migration up`: PASS, applied
  `0002_task_reminder_draft_ids.sql` to the existing local stack without a
  destructive database reset.
- `supabase test db`: PASS, 4 files / 10 pgTAP tests, first run.
- `supabase test db`: PASS, 4 files / 10 pgTAP tests, second consecutive run
  against the same local stack.

Verification notes:

- Supabase tests are now pgTAP-compatible and clean up fixed fixture IDs inside
  each transactional script, so `supabase test db` is repeatable. The
  `00_bootstrap_auth.sql` file now asserts the real Supabase `auth` schema is
  present instead of attempting to create platform-owned auth tables.
- Sync regression coverage now includes stale server-rejected LWW pushes,
  newer local edits that land while a push is in flight, server clock-skew
  clamping convergence, and overlapping pull cursors for rows sharing the same
  `updated_at` timestamp.

## Manual acceptance

- Existing local DB can be wiped/recreated with the fresh schema. Covered by
  `test/data/wipe_on_logout_test.dart`; still needs a real installed app DB
  wipe on device.
- App sign-in/profile/shell path is covered by auth gate and shell tests; still
  needs Android device sign-in smoke test.

## Changed contracts

- Drift schema version: `2`.
- Drift schema source: `lib/core/db/tables.dart`.
- Drift generated mirror: `lib/core/db/app_database.g.dart`.
- Supabase migrations: `supabase/migrations/0001_poc_baseline.sql` and
  `supabase/migrations/0002_task_reminder_draft_ids.sql`.
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
- Added `0002_task_reminder_draft_ids.sql` as an idempotent non-reset migration
  for existing local/CI databases.
- No data preservation path is included; the POC reset allows a fresh schema.

## Supabase dashboard/manual steps required

- Reset the Supabase project/database before applying
  `supabase/migrations/0001_poc_baseline.sql`.
- On a real Supabase project, apply the baseline and run `supabase test db`
  against a local/CI Supabase stack. The scripts under `supabase/tests/` are
  pgTAP tests and are expected to pass on consecutive runs.
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

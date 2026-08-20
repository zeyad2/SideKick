# Phase 2 Review - BLOCK

## What I verified (reproduced, with output)
- Static analysis -> `$env:PUB_CACHE=(Resolve-Path '.tooling\pub-cache'); & '.\.tooling\flutter\bin\flutter.bat' analyze` -> `No issues found! (ran in 11.5s)`.
- Full test suite -> `$env:PUB_CACHE=(Resolve-Path '.tooling\pub-cache'); & '.\.tooling\flutter\bin\flutter.bat' test` -> `00:02 +23: All tests passed!`.
- Drift/migration column-name parity for all 13 cloud tables plus local `dirty` / `synced_at` -> covered by the full suite (`test/schema/column_parity_test.dart`) -> both parity tests passed.
- Local-first task create, dirty marking, immediate local stream, soft-delete visibility, structural events, and local user scoping -> covered by the full suite (`test/data/repositories_test.dart`) -> all five repository tests passed.
- Preferences write path -> covered by the full suite (`test/data/preferences_test.dart`) -> persona language, onboarding completion, preference merge, and live profile tests passed.
- Pull-side LWW and connectivity trigger -> covered by the full suite (`test/sync/sync_engine_test.dart`) -> the six existing sync tests passed. These tests use a fake gateway and do not exercise production PostgREST upsert semantics, retry-after-commit, concurrent writes, user switching, or restart persistence.
- P0 theme integration -> full suite theme-swap widget test passed. Code inspection also confirms login and onboarding use `context.appTheme`, themed text, `PillButton`, and `SurfaceCard` (`lib/features/auth/presentation/login_screen.dart:77-171`, `lib/features/onboarding/presentation/onboarding_screen.dart:47-114`).
- Theme-token boundary -> `rg -n -g 'lib/**' -g '!lib/core/theme/**' "#[0-9A-Fa-f]{6,8}|Color\(0x|EdgeInsets\.(all|symmetric|only|fromLTRB)\([^\n]*[0-9]|SizedBox\([^\n]*(width|height):\s*[0-9]|BorderRadius\.[^(]+\([^\n]*[0-9]|Radius\.circular\([0-9]"` -> no matches.
- Repository boundary -> `rg -n "package:(drift|supabase)|SupabaseClient|AppDatabase|\.select\(|customSelect|customInsert|customUpdate|from\(" lib/features --glob '!**/data/**'` -> no feature/domain/presentation leak found.
- Events app read surface -> full suite `no events READ surface exists in lib` test passed; production grep found only the test-only `getSince` implementation and sync plumbing, with no UI/analytics reader.
- Pending-audio queue -> full suite passed both filesystem-backed queue tests.
- Repo-provided migration/RLS harness -> `& 'C:\Program Files\Git\bin\bash.exe' scripts/test_migration.sh` -> **failed** at the RLS step with `ERROR: relation "public.events" does not exist`; the script applies only `0001` at `scripts/test_migration.sh:31` although its RLS fixture now inserts into `events`.
- Independent migration + RLS reproduction -> started throwaway `postgres:16-alpine`, applied `00_bootstrap_auth.sql`, `0001_initial_schema.sql`, and `0002_events_log.sql`, then ran `10_rls_isolation.sql` and `20_fk_ownership.sql` -> `ALL RLS TESTS PASSED` and `ALL FK-OWNERSHIP + CHECK TESTS PASSED`. User A saw one own task/event and zero of user B's; cross-user insert and cross-tenant FK attacks were rejected.
- Cached-session/offline restart acceptance -> **not reproducible**. The code reads `GoTrueClient.currentSession` synchronously after initialization (`lib/core/auth/auth_repository.dart:62-66`) and the router performs no network auth call (`lib/core/router/app_router.dart:27`), but there is no test with a persisted Supabase session, offline startup, kill/reopen, or an expired cached token. All auth coverage is a fake in `test/support/fakes.dart:61-99`.
- Task kill/reopen persistence acceptance -> **not reproducible**. Repository tests use `NativeDatabase.memory()` (`test/data/repositories_test.dart:16`) and never close/reopen a file-backed database. Production selects a persistent drift database (`lib/core/db/app_database.dart:45-46`), but the required airplane-mode create -> kill -> reopen -> dirty-row proof is absent.

## Attacks attempted
- Two-device stale write -> seeded a cloud task at `updated_at=2026-07-12T15:00:00Z`, then executed the plain conflict update equivalent of the production `.upsert` with a stale `09:00:00Z` row -> **broke**: query returned `STALE | 2026-07-12 09:00:00+00`. Production calls unguarded `.upsert(payload)` at `lib/core/sync/sync_gateway.dart:76`; neither locked migration defines the conditional LWW write or clock-skew guard required by `docs/SCHEMA.md:68-95`.
- Edit while a flush is in flight -> traced select/push/clear ordering -> **broke by construction**: dirty rows are snapshotted, the network is awaited, then every matching id is unconditionally cleared (`lib/core/sync/sync_engine.dart:123-150`). A newer local update during that await is marked clean even though its payload was never sent.
- User switch with unsynced data -> traced the flush predicate against the shared persistent DB -> **broke by construction**: every table is queried with only `WHERE dirty = 1` (`lib/core/sync/sync_engine.dart:123-126`), not the engine's `userId`. User B therefore sends user A's dirty rows under B's JWT; RLS rejects the batch and also prevents B's rows in that batch from syncing.
- Event retry after remote commit / app kill before local acknowledgement -> inserted the same client-generated event id twice into the real migrated schema -> **broke**: second insert exited 3 with `duplicate key value violates unique constraint "events_pkey"`. Production uses a non-idempotent pure `.insert(payload)` (`lib/core/sync/sync_gateway.dart:73-74`) and only clears dirty after it returns (`lib/core/sync/sync_engine.dart:142-143`), so this crash window retries forever.
- Event immutability at the Supabase boundary -> authenticated as the event owner under the migration's real RLS policy, then ran UPDATE and DELETE -> **broke**: output was `UPDATE 1`, `DELETE 1`, `remaining 0`. `events_owner` is `FOR ALL` (`supabase/migrations/0002_events_log.sql:104-107`), so the database does not enforce the stated append-only/immutable contract.
- Forced gateway failure before commit -> code path **held partially**: `_markSynced` is after `gateway.push`, so a thrown push leaves rows dirty and per-table error handling continues (`lib/core/sync/sync_engine.dart:102-143`). No automated test covers the failure, and the after-commit ambiguity above does not hold.
- Cross-user repository read -> existing task repository test returned an empty list for user B, and all product watch queries inspected include their bound `userId` plus tombstone filtering -> **held for current read APIs**. The independent RLS test also held for tasks and events.
- Events update/delete through current app repositories -> production grep found no update/delete method on `EventsRepository`, and no production `getSince` caller -> **held at the Dart API boundary**, but the direct Supabase/RLS attack above broke server immutability.
- P4 filter pressure -> `CapturesRepository.watchByStatuses(Set<CaptureStatus>)` exists (`lib/features/inbox/domain/capture.dart:70-93`) -> **held**.
- P9 stale/avoidance pressure -> `Task` exposes `lastActivityAt`, but the frozen repository offers only `watchAll` and one exact-status filter (`lib/features/tasks/domain/task.dart:61-77`) -> **weak**: P9 can filter `watchAll` in memory without raw drift, but cannot express the indexed stale cutoff promised by `idx_tasks_stale`; see forward-risk ledger.
- Login/onboarding raw styling and theme swap -> no raw visual tokens outside `core/theme`, shared widgets are used, and the theme-swap test passed -> **held**.

## Findings
### BLOCKERS (must fix before Phase 3)
- [critical] Cloud push is not last-write-wins and has no clock-skew guard - the production gateway uses a plain PostgREST upsert, so arrival order overwrites timestamp order; the reproduced stale-write attack destroyed the newer value. This directly violates the locked sync contract - `lib/core/sync/sync_gateway.dart:63-76`, `docs/SCHEMA.md:68-95` - implement a server-side conditional write/RPC (plus future-timestamp clamp), return whether each row was accepted, and clear local dirty state only for confirmed rows.
- [critical] A local edit made during an in-flight flush can be silently lost - `_markSynced` clears by id only after the await, with no comparison to the exact `updated_at` that was sent. The newer unsent edit becomes clean and will never retry - `lib/core/sync/sync_engine.dart:123-150` - snapshot `(id, updated_at)`, and clear only where the current row is still dirty and its version equals the pushed version; add a deterministic concurrent-edit test.
- [critical] Flush is not scoped to the signed-in user - the shared local database is user-filtered at repository reads but sync selects every dirty row on the device. A prior user's dirty row causes RLS to reject a later user's whole batch, stranding valid writes and attempting cross-user transmission - `lib/core/sync/sync_engine.dart:45-47`, `lib/core/sync/sync_engine.dart:123-143` - add owner predicates (`id = userId` for profiles, `user_id = userId` otherwise) to selection and acknowledgement, and add a two-user switch test.
- [high] Event insert retry is not idempotent across the remote-commit/local-ack crash window - a duplicate primary key makes every later pure INSERT fail, leaving the event permanently dirty and blocking subsequent events in that batch - `lib/core/sync/sync_gateway.dart:73-74`, `lib/core/sync/sync_engine.dart:142-143` - use an insert-only idempotency mechanism (ignore an identical existing id or verify it), never overwrite event data, then acknowledge locally; add kill-between-push-and-mark coverage.
- [high] The cloud events table is not immutable - authenticated owners can UPDATE and DELETE events because the policy is `FOR ALL`; the direct attack changed and removed a row. This violates D9 even though the Dart repository itself is append-only - `supabase/migrations/0002_events_log.sql:104-107`, `docs/EVENTS.md:14-16` - add a new migration (do not edit the locked `0002`) that revokes owner update/delete and/or installs an immutable-row trigger, reserving tombstoning for a privileged future reaper.
- [high] Required restart/offline acceptance is unverified - there is no persisted-session offline startup test and no file-backed database kill/reopen test; current tests use fake auth and in-memory drift only - `test/support/fakes.dart:61-99`, `test/data/repositories_test.dart:16`, `test/data/preferences_test.dart:12` - add integration coverage proving cached session + preference + dirty task survive close/reopen with network unavailable, then sync after connectivity returns.
- [medium] The repository's advertised migration/RLS command is broken for Phase 2 - it applies only `0001`, while the RLS fixture requires `events`; therefore the claimed scripted `0001` + `0002` parity/RLS check cannot be reproduced with the documented command - `scripts/test_migration.sh:28-34`, `supabase/tests/10_rls_isolation.sql:25-28` - apply `0002_events_log.sql` before the RLS fixture and keep this command in CI.

### DEBT (proceed OK, but logged)
- None is eligible to defer while the phase is blocked. `TECH_DEBT.md` was intentionally left untouched.

### NITS (optional)
- `ConnectivityService.isConnected()` is implemented but unused (`lib/core/sync/connectivity_service.dart:8-28`). `start()` only subscribes to future connectivity changes (`lib/core/sync/sync_engine.dart:69-78`), so a cold start already online has no explicit initial sync trigger. Call `syncNow()` when constructing/starting the signed-in engine or prove lifecycle delivery deterministically.

## Contract integrity
- CONVENTIONS: **upheld** for theme access, folder boundaries, and feature presentation/data separation.
- SCHEMA: **violated** by the missing conditional server-side LWW write and missing clock-skew clamp. Column-name parity itself passed.
- DATA_CONTRACT: **violated** by unsafe dirty acknowledgement, cross-user flush selection, and non-idempotent event retry. The document's assertion that the server rejects stale upserts is not implemented (`docs/DATA_CONTRACT.md:79-85` versus `lib/core/sync/sync_gateway.dart:63-76`).
- EVENTS: **upheld at the Dart repository/read-surface boundary**, but **violated at the cloud authorization boundary** because owners can mutate/delete events.

## Forward-risk ledger
- Plain cloud upsert -> P4/P5/P9 concurrent edits and P12 stress testing -> replace with a real conditional timestamp write before any feature relies on sync.
- Ack-by-id after await -> every later repository mutation -> version-guard acknowledgement now; later repair requires finding already-lost edits, which is impossible.
- Unscoped dirty flush -> account switching and any shared-device use -> owner-scope every push/ack and test two cached users.
- Non-idempotent event INSERT -> all D9 feature events from P3 onward -> make duplicate-id retry safe before history begins accumulating.
- Mutable cloud events policy -> future insights history can be tampered with or erased -> enforce immutability in a new migration before collecting real history.
- `TasksRepository` has no stale cutoff query -> P9 avoidance/next-action scans cannot use `idx_tasks_stale` through the frozen interface -> add a domain-level `watchStale({required DateTime before})`/equivalent now, or explicitly accept and measure in-memory filtering before P9.
- No cold-start sync trigger -> returning users/new devices may wait for a later connectivity/lifecycle transition -> initiate one best-effort sync when the signed-in engine starts.

## Verdict + required actions
**BLOCK.** Before Phase 3:

1. Implement and test genuine server-arbitrated LWW with clock-skew handling.
2. Make flush acknowledgement version-safe and owner-scoped.
3. Make event insert retry idempotent without permitting overwrite, and enforce event immutability in a new migration.
4. Add persistent restart/offline-session, concurrent-edit, two-user, failure-after-commit, and production-gateway tests.
5. Repair `scripts/test_migration.sh` to apply both migrations and rerun the full Phase 2 gate.


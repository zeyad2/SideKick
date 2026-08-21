# Technical Debt

## [Phase 1] Supabase SQL tests need a reachable database
- Incurred: Phase 1, 2026-08-18
- What: POC Supabase RLS/FK/sync-guard SQL scripts were expanded, and `supabase` CLI 2.109.1 is installed, but `supabase test db` cannot connect because the local Postgres/Docker environment is not running.
- Risk: Phase 1 cloud isolation could drift from local/static expectations without CI or a local Postgres runner.
- Trigger to fix: Before merging the POC schema reset to a shared branch or applying it to a Supabase project.
- Estimated cost if deferred: One CI/local runner setup now; harder cloud debugging later.

## [Phase 2] Review drafts are in-memory
- Incurred: Phase 2, 2026-08-21
- What: Low-confidence and incomplete reminder drafts open an on-screen review card, but the review card state is not persisted across app restart.
- Risk: If Android kills the app while a draft is under review, the capture remains retryable but the transient edited review state is lost. Phase 3 is not blocked because active and pending reminders are persisted.
- Trigger to fix: Before dogfood hardening or before adding longer review/edit sessions.
- Estimated cost if deferred: Small local table or capture metadata update now; more UI recovery work later.

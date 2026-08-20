# Technical Debt

## [Phase 1] Supabase SQL tests need a reachable database
- Incurred: Phase 1, 2026-08-18
- What: POC Supabase RLS/FK/sync-guard SQL scripts were expanded, and `supabase` CLI 2.109.1 is installed, but `supabase test db` cannot connect because the local Postgres/Docker environment is not running.
- Risk: Phase 1 cloud isolation could drift from local/static expectations without CI or a local Postgres runner.
- Trigger to fix: Before merging the POC schema reset to a shared branch or applying it to a Supabase project.
- Estimated cost if deferred: One CI/local runner setup now; harder cloud debugging later.

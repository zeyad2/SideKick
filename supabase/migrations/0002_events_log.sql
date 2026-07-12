-- =============================================================================
-- Sidekick — Behavioural event log (P-future insights groundwork)
-- Target: Postgres 15+ / Supabase (auth schema + auth.uid()).
--
-- WHY THIS EXISTS (read before touching):
--   The insights feature (behavioural analysis, tips, energy-over-time) is a
--   FUTURE plan, deliberately NOT built now. But its data cannot be backfilled:
--   whatever we fail to record as it happens is gone forever. The state tables in
--   0001 store the CURRENT state of things (a task's status, a habit's last
--   completion) — not the HISTORY of how they got there, nor the ephemeral
--   selected energy mode. So we start an append-only event log NOW (write-only),
--   and defer everything that READS it to the insights phase.
--
--   This is a deliberate cross-cutting decision (call it D9): every repository
--   mutation MAY emit a domain event to this log. See docs/EVENTS.md for the
--   event-type taxonomy, metadata shapes, and the "write-now / read-later /
--   no-shame" contract.
--
-- CONTRACT — this table is APPEND-ONLY and IMMUTABLE:
--   * Rows are INSERTed, never UPDATEd. An event is a fact that happened.
--   * The only mutation the system ever performs is a future reaper setting
--     `deleted_at` on very old rows (tombstone), never a value edit.
--   * Because ids are client-generated UUIDs and rows are never updated, sync
--     push is a pure insert — there is NO last-write-wins conflict to resolve
--     (the conditional-upsert from SCHEMA.md §Sync is trivially satisfied).
--
-- CONVENTIONS (identical to 0001 — see docs/SCHEMA.md):
--   * user_id denormalised so RLS is a single-column `auth.uid() = user_id`.
--   * RLS enabled; owner-only.
--   * `updated_at` (client-owned LWW clock; == created_at for immutable rows) +
--     `deleted_at` (tombstone) so the sync engine treats this like every other
--     syncable table. `dirty` / `synced_at` are drift-local only (R0).
--
-- Post-lock changes require a NEW migration file, never an edit to this one.
-- =============================================================================

-- ============================ 13. events =====================================
-- One immutable row per meaningful thing the user did. The read side (insights)
-- is intentionally unbuilt; this is the write-only groundwork so history accrues.
create table public.events (
    id            uuid        primary key default gen_random_uuid(),
    user_id       uuid        not null references public.profiles (id) on delete cascade,

    -- WHAT happened. Deliberately NO check constraint: the taxonomy grows often
    -- (like `theme` in 0001), and a CHECK would force a migration per new event
    -- type — defeating the point. The client validates against docs/EVENTS.md.
    -- e.g. 'capture_created', 'task_status_changed', 'energy_mode_changed',
    --      'habit_completed', 'fresh_start_entered', 'reminder_actioned'.
    event_type    text        not null,

    -- WHAT it was about (optional — some events, e.g. energy_mode_changed, are not
    -- tied to a single entity). A DELIBERATELY LOOSE polymorphic link, exactly like
    -- captures.resulting_type / resulting_id: entity_id points into one of several
    -- tables depending on entity_type, so a real FK is not expressible. The typed
    -- row is the source of truth; this pair is a breadcrumb for analysis only.
    entity_type   text,       -- e.g. 'task','habit','capture','focus_session','reminder'
    entity_id     uuid,

    -- The evolving payload: the event's details as one opaque blob the analysis
    -- code reads whole and never filters in SQL (same rule as suggested_schedule /
    -- frequency_config in 0001). Grows without a migration per new field.
    -- e.g. {"from":"todo","to":"done"} for task_status_changed
    --      {"from":"normal","to":"low"} for energy_mode_changed
    --      {"reason":"too_big"} for avoidance_triaged
    metadata      jsonb       not null default '{}'::jsonb,

    -- WHEN it happened (device wall-clock, client-owned — like captures.captured_at).
    occurred_at   timestamptz not null default now(),

    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),  -- LWW clock; == created_at (immutable)
    deleted_at    timestamptz                          -- reaper tombstone only
);
comment on table  public.events is 'Append-only, immutable behavioural event log. Write-only groundwork for the future insights feature (D9). RLS: auth.uid() = user_id. See docs/EVENTS.md.';
comment on column public.events.event_type is 'Free-text (no CHECK): taxonomy grows without a migration; validated client-side against docs/EVENTS.md.';
comment on column public.events.entity_id  is 'Loose polymorphic link (no FK), disambiguated by entity_type — like captures.resulting_id.';
comment on column public.events.metadata   is 'Opaque per-event payload, read whole by the analysis code, never filtered in SQL.';

-- =============================================================================
-- INDEXES
-- The read side is unbuilt, so we index ONLY the two access patterns the insights
-- feature is certain to need, both partial on `deleted_at is null` (analysis never
-- reads tombstones). Richer read-path indexes ship WITH the insights migration,
-- when the exact queries are known — not speculatively now (each index taxes the
-- per-mutation write this table receives).
-- =============================================================================

-- Per-type time series — THE core analysis query:
--   WHERE user_id=? AND event_type=? ORDER BY occurred_at.
-- Also serves a plain user timeline as a (user_id, ...) prefix scan.
create index idx_events_user_type_time
    on public.events (user_id, event_type, occurred_at desc)
    where deleted_at is null;

-- "Everything that happened to this entity" — task/habit history reconstruction:
--   WHERE entity_type=? AND entity_id=? ORDER BY occurred_at.
create index idx_events_entity
    on public.events (entity_type, entity_id, occurred_at desc)
    where entity_id is not null and deleted_at is null;

-- =============================================================================
-- ROW LEVEL SECURITY — owner-only, identical shape to every table in 0001.
-- =============================================================================
alter table public.events enable row level security;

create policy events_owner on public.events
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

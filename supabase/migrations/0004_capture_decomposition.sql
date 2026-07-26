-- =============================================================================
-- Sidekick — Capture decomposition (rant → many items)
-- Target: Postgres 15+ / Supabase (auth schema + auth.uid()).
--
-- WHY THIS EXISTS (read docs/CAPTURE_DECOMPOSITION.md §8 — FROZEN design):
--   The pipeline moves from ONE capture → ONE typed record to ONE rant → N
--   proposed items. Drafts live as an ordered JSON array on the capture until
--   the user approves (or auto-commit materialises them); each approved draft
--   becomes a real child row carrying `capture_id`. The single-result fields on
--   `captures` (llm_type/title/details/suggested_schedule/resulting_type/
--   resulting_id) are RETIRED — kept as columns (0001 is LOCKED) but no longer
--   the triage source of truth.
--
--   Migrations 0001/0002/0003 are LOCKED — do not edit them. This file is
--   additive and idempotent-safe (IF EXISTS / IF NOT EXISTS) where Postgres
--   allows it.
-- =============================================================================

-- ============================ 1. captures.proposed_items =====================
-- Ordered JSONB array of draft objects (the §4 draft contract). Read whole by
-- the client, never queried in SQL — mirrors the suggested_schedule /
-- focus_sessions.captures_during JSON-blob precedent, so no index.
alter table public.captures
    add column if not exists proposed_items jsonb;
alter table public.captures
    add column if not exists dispositioned_item_ids jsonb not null default '[]'::jsonb;
alter table public.captures
    add column if not exists auto_committed_at timestamptz;
comment on column public.captures.proposed_items is
    'Ordered array of draft items (rant decomposition). Read whole; never queried. See CAPTURE_DECOMPOSITION.md §4.';

-- ============================ 2. goals.capture_id ============================
-- The one link gap: goals had no capture provenance. Composite SET NULL FK to
-- captures(id, user_id), matching tasks.capture_id (same-user ownership; the
-- goal outlives the capture it came from). PG15 column-list SET NULL nulls ONLY
-- capture_id, never the NOT NULL user_id.
alter table public.goals
    add column if not exists capture_id uuid;

alter table public.goals
    drop constraint if exists goals_capture_fk;
alter table public.goals
    add constraint goals_capture_fk
        foreign key (capture_id, user_id) references public.captures (id, user_id)
        on delete set null (capture_id);

-- Items laddering back to their originating capture (mirrors tasks/notes/habits).
create index if not exists idx_goals_capture
    on public.goals (capture_id)
    where capture_id is not null and deleted_at is null;

-- ==================== 3. Drop the 1:1 capture CHECKs =========================
-- The terminal state is now "all proposed items dispositioned", not "exactly one
-- resulting_type + resulting_id set". Both named 1:1 CHECKs from 0001 are dropped
-- so a capture can reach `triaged` via the N-item / auto-commit path with the
-- retired resulting_* fields left null.
alter table public.captures
    drop constraint if exists captures_resulting_only_when_triaged;
alter table public.captures
    drop constraint if exists captures_triaged_needs_resulting;

-- ==================== 4. ResultingType gains `goal` =========================
-- ResultingType is a DOMAIN routing enum (drives draft materialisation), not a
-- DB gate — the retired resulting_type value CHECK is widened to include 'goal'
-- so any legacy single-result write of a goal cannot trip the column CHECK.
-- (The client no longer writes resulting_* for the multi-item flow; this keeps
-- the column honest if it ever is written.)
alter table public.captures
    drop constraint if exists captures_resulting_type_check;
alter table public.captures
    add constraint captures_resulting_type_check
        check (resulting_type is null
               or resulting_type in ('task', 'note', 'habit', 'goal'));

-- Decomposition-aware terminal invariants replace the retired one-result pair.
create or replace function public.capture_disposition_valid(
    proposed jsonb,
    disposed jsonb,
    require_complete boolean
) returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
    proposed_count integer;
    distinct_proposed_count integer;
    disposed_count integer;
    distinct_disposed_count integer;
begin
    if jsonb_typeof(disposed) <> 'array' then return false; end if;
    if proposed is null then
        return jsonb_array_length(disposed) = 0 and not require_complete;
    end if;
    if jsonb_typeof(proposed) <> 'array' then return false; end if;
    if exists (
        select 1 from jsonb_array_elements(disposed) as d(value)
        where jsonb_typeof(value) <> 'string'
    ) or exists (
        select 1 from jsonb_array_elements(proposed) as p(item)
        where jsonb_typeof(item) <> 'object'
           or jsonb_typeof(item -> 'id') <> 'string'
           or item ->> 'id' = ''
    ) then return false; end if;

    select count(*), count(distinct value)
      into disposed_count, distinct_disposed_count
      from jsonb_array_elements_text(disposed) as d(value);
    if disposed_count <> distinct_disposed_count then return false; end if;

    select count(*), count(distinct item ->> 'id')
      into proposed_count, distinct_proposed_count
      from jsonb_array_elements(proposed) as p(item);
    if proposed_count <> distinct_proposed_count then return false; end if;

    if exists (
        select 1 from jsonb_array_elements_text(disposed) as d(value)
        where not exists (
            select 1 from jsonb_array_elements(proposed) as p(item)
            where item ->> 'id' = value
        )
    ) then return false; end if;

    if require_complete then
        return jsonb_array_length(proposed) = disposed_count;
    end if;
    return true;
end;
$$;

alter table public.captures
    add constraint captures_disposition_ids_array
        check (public.capture_disposition_valid(
            proposed_items, dispositioned_item_ids, false));
alter table public.captures
    add constraint captures_legacy_result_only_when_triaged
        check (status = 'triaged'
               or (resulting_type is null and resulting_id is null));
alter table public.captures
    add constraint captures_legacy_result_pair
        check ((resulting_type is null) = (resulting_id is null));
alter table public.captures
    add constraint captures_triaged_decomposition_complete
        check (status <> 'triaged'
          or public.capture_disposition_valid(
              proposed_items, dispositioned_item_ids, true)
          or (resulting_type is not null and resulting_id is not null));
alter table public.captures
    add constraint captures_auto_commit_is_triaged
        check (auto_committed_at is null or status = 'triaged');

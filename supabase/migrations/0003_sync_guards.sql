-- =============================================================================
-- Sidekick — Server-side sync guards (P2 gate fixes)
-- Target: Postgres 15+ / Supabase (auth schema + auth.uid()).
--
-- WHY THIS EXISTS (read before touching):
--   The locked sync contract (docs/SCHEMA.md §Sync) requires the SERVER, not the
--   client, to arbitrate last-write-wins on push. A plain PostgREST upsert
--   overwrites by ARRIVAL order, so a late-arriving stale edit clobbers a newer
--   one. This migration installs the server-side conditional-write behaviour and
--   the clock-skew clamp the contract mandates, and it hardens the append-only
--   events table so its immutability is enforced by the database, not merely by
--   the Dart repository shape.
--
--   Migrations 0001/0002 are LOCKED — do not edit them. This file is additive.
-- =============================================================================

-- =============================================================================
-- 1. LAST-WRITE-WINS GUARD + CLOCK-SKEW CLAMP (SCHEMA.md §Sync)
--
-- PostgREST cannot express a conditional `on conflict do update ... where`, so
-- we enforce the same rule with a BEFORE INSERT OR UPDATE trigger:
--
--   * Clock-skew clamp: a pushed `updated_at` more than 5 minutes in the future
--     is clamped to now(). `updated_at` is device wall-clock, so a fast clock
--     could otherwise win every race permanently; this bounds the damage.
--   * Conditional LWW: on UPDATE, if the incoming row is STRICTLY OLDER than the
--     stored row, keep the stored row unchanged (return OLD). A stale device can
--     therefore never overwrite a newer edit. On an exact tie the incoming row
--     is applied (idempotent — same id, same version, same data).
-- =============================================================================
create or replace function public.sync_lww_guard()
returns trigger
language plpgsql
as $$
begin
    -- Clock-skew clamp: reject a pushed timestamp from the future.
    if new.updated_at > now() + interval '5 minutes' then
        new.updated_at := now();
    end if;

    -- Conditional LWW: on conflict, reject a strictly-stale write.
    if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
        return old;
    end if;

    return new;
end;
$$;

-- Apply to every mutable syncable table (all of 0001 — NOT `events`, which is
-- insert-only and immutable, handled in section 2).
create trigger profiles_lww_guard
    before insert or update on public.profiles
    for each row execute function public.sync_lww_guard();

create trigger captures_lww_guard
    before insert or update on public.captures
    for each row execute function public.sync_lww_guard();

create trigger goals_lww_guard
    before insert or update on public.goals
    for each row execute function public.sync_lww_guard();

create trigger tasks_lww_guard
    before insert or update on public.tasks
    for each row execute function public.sync_lww_guard();

create trigger notes_lww_guard
    before insert or update on public.notes
    for each row execute function public.sync_lww_guard();

create trigger habits_lww_guard
    before insert or update on public.habits
    for each row execute function public.sync_lww_guard();

create trigger habit_completions_lww_guard
    before insert or update on public.habit_completions
    for each row execute function public.sync_lww_guard();

create trigger places_lww_guard
    before insert or update on public.places
    for each row execute function public.sync_lww_guard();

create trigger focus_sessions_lww_guard
    before insert or update on public.focus_sessions
    for each row execute function public.sync_lww_guard();

create trigger vibe_checks_lww_guard
    before insert or update on public.vibe_checks
    for each row execute function public.sync_lww_guard();

create trigger reminders_lww_guard
    before insert or update on public.reminders
    for each row execute function public.sync_lww_guard();

create trigger block_list_lww_guard
    before insert or update on public.block_list
    for each row execute function public.sync_lww_guard();

-- =============================================================================
-- 2. EVENTS IMMUTABILITY AT THE AUTHORIZATION BOUNDARY (D9 / docs/EVENTS.md)
--
-- 0002 created a single `for all` owner policy, which permits an authenticated
-- owner to UPDATE or DELETE their own events — violating the append-only/
-- immutable contract at the database boundary even though the Dart repository
-- exposes no mutator. Replace it with SELECT + INSERT only: RLS now denies
-- UPDATE and DELETE for every ordinary (non-service-role) session. A future
-- privileged reaper/tombstoner runs with the service role, which bypasses RLS.
-- =============================================================================
drop policy events_owner on public.events;

create policy events_select on public.events
    for select using (auth.uid() = user_id);

create policy events_insert on public.events
    for insert with check (auth.uid() = user_id);

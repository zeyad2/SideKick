-- =============================================================================
-- Sidekick — Initial schema (P1, LOCKED once approved)
-- Target: Postgres 15+ / Supabase (auth schema + auth.uid()).
--
-- Design tenets (see docs/SCHEMA.md for full rationale):
--   * Local-first, cloud-synced (D5). Every write hits local drift first; this
--     cloud schema is the sync target, not the primary store.
--   * Last-write-wins: every syncable table carries `updated_at` (the LWW clock,
--     owned by the CLIENT) and `deleted_at` (soft-delete tombstone so deletes
--     propagate through a pull-since cursor).
--   * `dirty` / `synced_at` / `last_pull` are CLIENT-LOCAL sync bookkeeping and
--     deliberately DO NOT exist in this cloud schema — they are dead columns on
--     the server. They live only in the drift mirror (P2). See SCHEMA.md §Sync.
--     >>> This is a deliberate deviation from a literal reading of the P1 brief;
--         it is called out as review item R0. <<<
--   * user_id is denormalised onto EVERY table (even where derivable via FK) so
--     RLS is a single-column `auth.uid() = user_id` policy with no subquery.
--   * RLS is enabled on EVERY table. A user can only ever see their own rows.
--
-- Post-lock changes require a NEW migration file, never an edit to this one.
-- =============================================================================

-- gen_random_uuid() is built into Postgres 13+. pgcrypto not required.

-- ============================ 1. profiles ====================================
-- One row per auth user. Holds user-level preferences.
--
-- PREFERENCES STORAGE DECISION (hybrid — see SCHEMA.md §Preferences):
--   * Discrete columns for prefs that (a) drive core behaviour, (b) are
--     server-validated via CHECK, or (c) might ever be queried:
--       persona_response_language, theme.
--   * A single `prefs` JSONB blob for additive, client-only, never-queried UI
--     config that must grow WITHOUT a migration per toggle:
--       capture_trigger {key, press_count}, energy_time_rules[], and the
--       onboarding flags. Shape is owned/validated by the client.
create table public.profiles (
    id                        uuid primary key references auth.users (id) on delete cascade,

    persona_response_language text        not null default 'en'
                                  check (persona_response_language in ('en', 'ar-EG')),
    theme                     text        not null default 'analog_companion',
                                  -- intentionally NO check: themes grow (D8); the
                                  -- client validates against its theme registry.

    prefs                     jsonb       not null default '{}'::jsonb,
                                  -- e.g. {"capture_trigger":{"key":"volume_up","press_count":3},
                                  --       "energy_time_rules":[{"from":"06:00","to":"12:00","mode":"charged"}],
                                  --       "onboarding_completed":true}

    created_at                timestamptz not null default now(),
    updated_at                timestamptz not null default now(),  -- LWW clock (client-owned)
    deleted_at                timestamptz                          -- tombstone (soft delete)
);
comment on table  public.profiles is 'One row per auth user; user-level preferences. RLS: auth.uid() = id.';
comment on column public.profiles.prefs is 'Additive client-only UI config; grows without migration. See SCHEMA.md.';

-- ============================ 2. captures ====================================
-- The raw brain-dump event: audio + transcript. Kept SEPARATE from
-- tasks/notes/habits because a capture is an immutable inbox event that gets
-- triaged INTO a typed record; separation preserves the raw transcript, allows
-- re-triage, and decouples native capture (P3, offline) from Gemini
-- categorisation (P4). See SCHEMA.md §"Why captures is separate".
create table public.captures (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid        not null references public.profiles (id) on delete cascade,

    audio_path        text,                     -- device-local file path (may be null once cleaned up)
    raw_transcript    text,                     -- filled by Gemini in P4

    llm_type          text        not null default 'uncategorized'
                          check (llm_type in ('task', 'note', 'habit', 'uncategorized')),
    title             text,
    details           text,
    suggested_schedule jsonb,                   -- Gemini's proposed schedule for task-type captures (heterogeneous shape)

    status            text        not null default 'pending'
                          check (status in ('pending','processing','ready','triaged','failed','discarded')),
                          -- pending:    audio on disk, awaiting transcription (offline queue)
                          -- processing: transcription in flight
                          -- ready:      transcribed, shown in inbox awaiting triage
                          -- triaged:    converted to a task/note/habit (see resulting_*)
                          -- failed:     transcription failed after retries (stays in inbox, retryable)
                          -- discarded:  user dismissed

    resulting_type    text        check (resulting_type in ('task','note','habit')),
    resulting_id      uuid,                     -- id of the record this capture became (loose link; no FK: cross-table)

    captured_at       timestamptz not null default now(),  -- when the human hit the trigger

    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);
comment on table public.captures is 'Raw capture events (audio+transcript) triaged into typed records. RLS: auth.uid() = user_id.';

-- ============================ 3. tasks =======================================
create table public.tasks (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid        not null references public.profiles (id) on delete cascade,
    capture_id        uuid        references public.captures (id) on delete set null,
                          -- task outlives the capture it came from -> SET NULL, not cascade.

    title             text        not null,
    details           text,
    status            text        not null default 'todo'
                          check (status in ('todo', 'done', 'archived')),

    next_action       text,                     -- P9 next-action extractor (single physical action)
    scheduled_at      timestamptz,              -- optional schedule chip
    completed_at      timestamptz,
    last_activity_at  timestamptz not null default now(),
                          -- semantic "user touched this" clock for the 48h-untouched /
                          -- avoidance-triage scans (P9). Distinct from updated_at, which
                          -- also moves on sync-driven writes.

    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);
comment on table public.tasks is 'Actionable items. RLS: auth.uid() = user_id.';

-- ============================ 4. notes =======================================
create table public.notes (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid        not null references public.profiles (id) on delete cascade,
    capture_id        uuid        references public.captures (id) on delete set null,

    title             text,
    body              text,

    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);
comment on table public.notes is 'Reference notes (non-actionable). RLS: auth.uid() = user_id.';

-- ============================ 5. habits ======================================
create table public.habits (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid        not null references public.profiles (id) on delete cascade,
    capture_id        uuid        references public.captures (id) on delete set null,

    title             text        not null,
    frequency_config  jsonb,                    -- recurrence rule (daily / N-per-week / specific days); heterogeneous -> JSONB
    level_config      jsonb,                    -- optional per-level (mini/normal/mega) descriptions
    anchor_description text,                    -- habit stacking (P9): "what you already do every day"

    -- Fresh Start (P5): missed habit enters a shame-free 3-day Mini reset run.
    reset_active      boolean     not null default false,
    reset_started_at  timestamptz,

    archived          boolean     not null default false,

    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);
comment on table public.habits is 'Elastic habits (mini/normal/mega). RLS: auth.uid() = user_id.';

-- ====================== 6. habit_completions =================================
create table public.habit_completions (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid        not null references public.profiles (id) on delete cascade,
    habit_id          uuid        not null references public.habits (id) on delete cascade,
                          -- completions are meaningless without their habit -> CASCADE.

    level             text        not null check (level in ('mini', 'normal', 'mega')),
    energy_mode       text        check (energy_mode in ('low', 'normal', 'charged')),
    completed_at      timestamptz not null default now(),

    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);
comment on table public.habit_completions is 'Immutable habit-completion log (any level = a full win). RLS: auth.uid() = user_id.';

-- ============================ 7. places ======================================
create table public.places (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid        not null references public.profiles (id) on delete cascade,

    name              text        not null,
    lat               double precision not null,
    lng               double precision not null,
    radius_m          integer     not null default 150,

    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);
comment on table public.places is 'Geofence anchor points. RLS: auth.uid() = user_id.';

-- ====================== 8. focus_sessions ====================================
-- Declared before reminders is not required (no FK from reminders to sessions),
-- but vibe_checks FKs into it, so it must precede vibe_checks.
create table public.focus_sessions (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid        not null references public.profiles (id) on delete cascade,
    task_id           uuid        references public.tasks (id) on delete set null,
                          -- session may anchor a real task OR a freeform label; keep history if task deleted -> SET NULL.
    task_label        text,                     -- freeform declared task when not a tasks row

    duration_minutes  integer     not null,     -- planned duration
    started_at        timestamptz not null default now(),
    ended_at          timestamptz,
    status            text        not null default 'active'
                          check (status in ('active', 'completed', 'abandoned')),

    blocking_enabled  boolean     not null default false,
    blocking_mode     text        not null default 'soft'
                          check (blocking_mode in ('soft', 'hard')),
    block_attempts    integer     not null default 0,

    captures_during   jsonb       not null default '[]'::jsonb,
                          -- ordered JSONB array of capture ids captured mid-session,
                          -- surfaced AFTER the session. Read wholesale with the row,
                          -- never queried across sessions -> array beats a join table.

    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);
comment on table public.focus_sessions is 'Body-double focus sessions + blocking counters. RLS: auth.uid() = user_id.';

-- ============================ 9. vibe_checks =================================
create table public.vibe_checks (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid        not null references public.profiles (id) on delete cascade,
    focus_session_id  uuid        references public.focus_sessions (id) on delete cascade,
                          -- ~30% post-session 3-tap check; tied to its session -> CASCADE.
                          -- nullable so standalone vibe checks are possible.

    value             smallint    not null check (value between 1 and 3),  -- 3-tap scale
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);
comment on table public.vibe_checks is 'Post-session mood signal (3-tap). RLS: auth.uid() = user_id.';

-- ============================ 10. reminders ==================================
create table public.reminders (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid        not null references public.profiles (id) on delete cascade,

    reminder_type     text        not null check (reminder_type in ('time', 'geofence')),

    -- Target: a task or a habit (or neither, for a freestanding reminder).
    task_id           uuid        references public.tasks (id)  on delete cascade,
    habit_id          uuid        references public.habits (id) on delete cascade,
                          -- reminder is meaningless if its target is gone -> CASCADE.

    -- Time reminders:
    scheduled_at      timestamptz,
    recurrence        jsonb,
    snooze_until      timestamptz,              -- "Later" -> +2h

    -- Geofence reminders:
    place_id          uuid        references public.places (id) on delete cascade,
    geofence_transition text      check (geofence_transition in ('enter', 'exit')),
    dwell_seconds     integer     default 60,   -- dwell filter before firing

    copy              text,                     -- question-framed copy (may be generated at fire time)
    status            text        not null default 'scheduled'
                          check (status in ('scheduled', 'fired', 'done', 'cancelled')),

    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz,

    -- Structural integrity: each type has the fields it needs.
    constraint reminders_time_needs_schedule
        check (reminder_type <> 'time' or scheduled_at is not null),
    constraint reminders_geofence_needs_place
        check (reminder_type <> 'geofence'
               or (place_id is not null and geofence_transition is not null))
);
comment on table public.reminders is 'Time + geofence reminders. RLS: auth.uid() = user_id.';

-- ============================ 11. block_list =================================
-- One row per app to block during focus sessions.
-- app_identifier holds an Android package name (e.g. "com.instagram.android")
-- OR an iOS FamilyControls opaque token (base64), disambiguated by `platform`.
-- iOS tokens are device-scoped and may not port across devices — see SCHEMA.md.
create table public.block_list (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid        not null references public.profiles (id) on delete cascade,

    platform          text        not null check (platform in ('android', 'ios')),
    app_identifier    text        not null,     -- Android package name | iOS opaque token
    app_label         text,                     -- display name for the picker/overlay

    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);
comment on table public.block_list is 'Apps blocked during focus sessions. RLS: auth.uid() = user_id.';

-- =============================================================================
-- INDEXES — each maps to a concrete query pattern (see SCHEMA.md §Indexes).
-- Partial (deleted_at is null) where the app never lists tombstones.
-- =============================================================================

-- Inbox list: WHERE user_id=? AND status IN (...) ORDER BY captured_at DESC.
create index idx_captures_inbox
    on public.captures (user_id, status, captured_at desc)
    where deleted_at is null;

-- Habit completion history / Done list per habit: WHERE habit_id=? ORDER BY completed_at DESC.
create index idx_habit_completions_habit
    on public.habit_completions (habit_id, completed_at desc)
    where deleted_at is null;

-- Focus session history: WHERE user_id=? ORDER BY started_at DESC.
create index idx_focus_sessions_user_started
    on public.focus_sessions (user_id, started_at desc)
    where deleted_at is null;

-- Task lists by status: WHERE user_id=? AND status=?.
create index idx_tasks_user_status
    on public.tasks (user_id, status)
    where deleted_at is null;

-- Stale/avoidance scan (P9): open tasks untouched for 48h+.
create index idx_tasks_stale
    on public.tasks (user_id, last_activity_at)
    where status = 'todo' and deleted_at is null;

-- Reminder lookups by target (P6/P9 fire + cancel-on-delete paths).
create index idx_reminders_place on public.reminders (place_id) where place_id is not null;
create index idx_reminders_task  on public.reminders (task_id)  where task_id  is not null;
create index idx_reminders_habit on public.reminders (habit_id) where habit_id is not null;

-- =============================================================================
-- ROW LEVEL SECURITY — enabled on EVERY table; owner-only access.
-- One FOR ALL policy per table (USING + WITH CHECK) keeps it single-column.
-- =============================================================================
alter table public.profiles          enable row level security;
alter table public.captures          enable row level security;
alter table public.tasks             enable row level security;
alter table public.notes             enable row level security;
alter table public.habits            enable row level security;
alter table public.habit_completions enable row level security;
alter table public.places            enable row level security;
alter table public.focus_sessions    enable row level security;
alter table public.vibe_checks       enable row level security;
alter table public.reminders         enable row level security;
alter table public.block_list        enable row level security;

create policy profiles_owner on public.profiles
    for all using (auth.uid() = id) with check (auth.uid() = id);

create policy captures_owner on public.captures
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy tasks_owner on public.tasks
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy notes_owner on public.notes
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy habits_owner on public.habits
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy habit_completions_owner on public.habit_completions
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy places_owner on public.places
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy focus_sessions_owner on public.focus_sessions
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy vibe_checks_owner on public.vibe_checks
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy reminders_owner on public.reminders
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy block_list_owner on public.block_list
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- =============================================================================
-- Auto-provision a profile row when an auth user is created (Supabase pattern).
-- =============================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    insert into public.profiles (id) values (new.id)
    on conflict (id) do nothing;
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

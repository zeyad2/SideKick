-- Sidekick POC baseline schema.
-- Fresh reset: no legacy companion data is preserved.

create table public.profiles (
    id                        uuid primary key references auth.users (id) on delete cascade,
    persona_response_language text        not null default 'en'
                                  check (persona_response_language in ('en', 'ar-EG')),
    theme                     text        not null default 'analog_companion',
    prefs                     jsonb       not null default '{}'::jsonb,
    created_at                timestamptz not null default now(),
    updated_at                timestamptz not null default now(),
    deleted_at                timestamptz
);

create table public.places (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid        not null references public.profiles (id) on delete cascade,
    name       text        not null,
    lat        double precision not null check (lat between -90 and 90),
    lng        double precision not null check (lng between -180 and 180),
    radius_m   integer     not null default 150 check (radius_m > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint places_id_user_key unique (id, user_id)
);

create table public.captures (
    id             uuid primary key default gen_random_uuid(),
    user_id        uuid        not null references public.profiles (id) on delete cascade,
    source         text        not null check (source in ('typed', 'audio', 'shortcut')),
    input_text     text,
    audio_path     text,
    raw_transcript text,
    status         text        not null default 'pending'
                              check (status in ('pending','processing','ready','triaged','failed','discarded')),
    error          text,
    captured_at    timestamptz not null default now(),
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now(),
    deleted_at     timestamptz,
    constraint captures_id_user_key unique (id, user_id),
    constraint captures_has_input check (input_text is not null or audio_path is not null)
);

create table public.task_reminders (
    id                      uuid primary key default gen_random_uuid(),
    user_id                 uuid        not null references public.profiles (id) on delete cascade,
    title                   text        not null,
    details                 text,
    status                  text        not null default 'active'
                                      check (status in ('pending_auto_commit','active','done','dismissed','cancelled')),
    source                  text        not null check (source in ('typed','audio','manual')),
    confidence              double precision not null default 0 check (confidence >= 0 and confidence <= 1),
    trigger_type            text        not null check (trigger_type in ('time','place')),
    scheduled_at            timestamptz,
    place_id                uuid,
    geofence_transition     text        check (geofence_transition in ('enter','exit')),
    dwell_seconds           integer     check (dwell_seconds is null or dwell_seconds >= 0),
    auto_commit_deadline_at timestamptz,
    capture_id              uuid,
    draft_id                text,
    ai_explanation          text,
    ai_context              jsonb,
    created_at              timestamptz not null default now(),
    updated_at              timestamptz not null default now(),
    deleted_at              timestamptz,
    constraint task_reminders_id_user_key unique (id, user_id),
    constraint task_reminders_capture_fk
        foreign key (capture_id, user_id) references public.captures (id, user_id)
        on delete set null (capture_id),
    constraint task_reminders_place_fk
        foreign key (place_id, user_id) references public.places (id, user_id)
        on delete set null (place_id),
    constraint task_reminders_time_needs_schedule
        check (trigger_type <> 'time' or scheduled_at is not null),
    constraint task_reminders_place_needs_place
        check (trigger_type <> 'place'
               or (place_id is not null and geofence_transition is not null))
);

create table public.reminder_events (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid        not null references public.profiles (id) on delete cascade,
    reminder_id uuid        not null,
    event_type  text        not null,
    metadata    jsonb       not null default '{}'::jsonb,
    occurred_at timestamptz not null default now(),
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    deleted_at  timestamptz,
    constraint reminder_events_reminder_fk
        foreign key (reminder_id, user_id) references public.task_reminders (id, user_id)
        on delete cascade
);

create table public.conversations (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid        not null references public.profiles (id) on delete cascade,
    title      text,
    status     text        not null default 'open' check (status in ('open','archived')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint conversations_id_user_key unique (id, user_id)
);

create table public.messages (
    id              uuid primary key default gen_random_uuid(),
    user_id         uuid        not null references public.profiles (id) on delete cascade,
    conversation_id uuid        not null,
    role            text        not null check (role in ('user','assistant','system')),
    content         text        not null,
    metadata        jsonb       not null default '{}'::jsonb,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    deleted_at      timestamptz,
    constraint messages_conversation_fk
        foreign key (conversation_id, user_id) references public.conversations (id, user_id)
        on delete cascade
);

create table public.events (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid        not null references public.profiles (id) on delete cascade,
    event_type  text        not null,
    entity_type text,
    entity_id   uuid,
    metadata    jsonb       not null default '{}'::jsonb,
    occurred_at timestamptz not null default now(),
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    deleted_at  timestamptz
);

create index idx_places_user on public.places (user_id) where deleted_at is null;
create index idx_captures_user_status on public.captures (user_id, status, captured_at desc) where deleted_at is null;
create index idx_task_reminders_active on public.task_reminders (user_id, status, scheduled_at) where deleted_at is null;
create index idx_task_reminders_place on public.task_reminders (place_id) where place_id is not null and deleted_at is null;
create unique index task_reminders_capture_draft_uidx
    on public.task_reminders (user_id, capture_id, draft_id)
    where capture_id is not null and draft_id is not null and deleted_at is null;
create index idx_reminder_events_reminder on public.reminder_events (reminder_id, occurred_at);
create index idx_messages_conversation on public.messages (conversation_id, created_at) where deleted_at is null;

alter table public.profiles       enable row level security;
alter table public.places         enable row level security;
alter table public.captures       enable row level security;
alter table public.task_reminders enable row level security;
alter table public.reminder_events enable row level security;
alter table public.conversations  enable row level security;
alter table public.messages       enable row level security;
alter table public.events         enable row level security;

create policy profiles_owner on public.profiles
    for all using (auth.uid() = id) with check (auth.uid() = id);
create policy places_owner on public.places
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy captures_owner on public.captures
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy task_reminders_owner on public.task_reminders
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy conversations_owner on public.conversations
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy messages_owner on public.messages
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy reminder_events_owner_read on public.reminder_events
    for select using (auth.uid() = user_id);
create policy reminder_events_owner_insert on public.reminder_events
    for insert with check (auth.uid() = user_id);
create policy events_owner_read on public.events
    for select using (auth.uid() = user_id);
create policy events_owner_insert on public.events
    for insert with check (auth.uid() = user_id);

create or replace function public.sync_lww_guard()
returns trigger
language plpgsql
as $$
begin
    if new.updated_at > now() + interval '5 minutes' then
        new.updated_at := now();
    end if;

    if tg_op = 'UPDATE' and old.updated_at > new.updated_at then
        return old;
    end if;

    return new;
end;
$$;

create trigger profiles_sync_lww_guard
    before insert or update on public.profiles
    for each row execute function public.sync_lww_guard();
create trigger places_sync_lww_guard
    before insert or update on public.places
    for each row execute function public.sync_lww_guard();
create trigger captures_sync_lww_guard
    before insert or update on public.captures
    for each row execute function public.sync_lww_guard();
create trigger task_reminders_sync_lww_guard
    before insert or update on public.task_reminders
    for each row execute function public.sync_lww_guard();
create trigger conversations_sync_lww_guard
    before insert or update on public.conversations
    for each row execute function public.sync_lww_guard();
create trigger messages_sync_lww_guard
    before insert or update on public.messages
    for each row execute function public.sync_lww_guard();

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

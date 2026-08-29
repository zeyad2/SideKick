-- POC sync-guard test. Run after 0001_poc_baseline.sql.

begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

delete from public.task_reminders where id = '33333333-0000-0000-0000-000000000001';
delete from public.task_reminders where id in (
    '33333333-0000-0000-0000-000000000011',
    '33333333-0000-0000-0000-000000000012'
);
delete from public.captures where id = '33333333-0000-0000-0000-000000000002';
delete from public.captures where id = '33333333-0000-0000-0000-0000000000ca';

do $$
declare bad_cols int;
begin
    select count(*) into bad_cols
    from information_schema.columns
    where table_schema = 'public'
      and column_name in ('dirty', 'synced_at')
      and table_name in (
        'profiles','places','captures','task_reminders','reminder_events',
        'conversations','messages','events'
      );

    if bad_cols <> 0 then
        raise exception 'FAIL: cloud schema contains local-only sync columns';
    end if;
end$$;

select pass('cloud schema omits local-only sync columns');

insert into auth.users (id, email) values
    ('44444444-4444-4444-4444-444444444444', 'sync@test')
on conflict (id) do nothing;

insert into public.task_reminders (
    id, user_id, title, source, confidence, trigger_type, scheduled_at, updated_at
) values (
    '33333333-0000-0000-0000-000000000001',
    '44444444-4444-4444-4444-444444444444',
    'Newer value',
    'typed',
    1,
    'time',
    now(),
    '2026-08-18T15:00:00Z'
);

insert into public.task_reminders (
    id, user_id, title, source, confidence, trigger_type, scheduled_at, updated_at
) values (
    '33333333-0000-0000-0000-000000000001',
    '44444444-4444-4444-4444-444444444444',
    'Stale value',
    'typed',
    1,
    'time',
    now(),
    '2026-08-18T09:00:00Z'
)
on conflict (id) do update set
    title = excluded.title,
    updated_at = excluded.updated_at;

do $$
declare t text;
begin
    select title into t from public.task_reminders
    where id = '33333333-0000-0000-0000-000000000001';
    if t <> 'Newer value' then
        raise exception 'FAIL: stale push overwrote newer reminder (title=%)', t;
    end if;
end$$;

select pass('stale LWW upsert does not overwrite newer reminder');

insert into public.captures (
    id, user_id, source, input_text
) values (
    '33333333-0000-0000-0000-0000000000ca',
    '44444444-4444-4444-4444-444444444444',
    'typed',
    'review drafts'
);

insert into public.task_reminders (
    id, user_id, title, source, confidence, trigger_type, scheduled_at, capture_id, draft_id
) values (
    '33333333-0000-0000-0000-000000000011',
    '44444444-4444-4444-4444-444444444444',
    'Approved draft',
    'typed',
    1,
    'time',
    now(),
    '33333333-0000-0000-0000-0000000000ca',
    'draft_same'
);

do $$
begin
    begin
        insert into public.task_reminders (
            id, user_id, title, source, confidence, trigger_type, scheduled_at, capture_id, draft_id
        ) values (
            '33333333-0000-0000-0000-000000000012',
            '44444444-4444-4444-4444-444444444444',
            'Duplicate approved draft',
            'typed',
            1,
            'time',
            now(),
            '33333333-0000-0000-0000-0000000000ca',
            'draft_same'
        );
        raise exception 'FAIL: duplicate capture draft approval accepted';
    exception when unique_violation then null; end;
end$$;

select pass('task_reminders enforces one approved row per owner/capture/draft');

insert into public.captures (
    id, user_id, source, input_text, updated_at
) values (
    '33333333-0000-0000-0000-000000000002',
    '44444444-4444-4444-4444-444444444444',
    'typed',
    'fast clock',
    now() + interval '1 hour'
);

do $$
declare u timestamptz;
begin
    select updated_at into u from public.captures
    where id = '33333333-0000-0000-0000-000000000002';
    if u > now() + interval '5 minutes' then
        raise exception 'FAIL: future updated_at not clamped (%)', u;
    end if;
end$$;

select pass('future updated_at is clamped by sync guard');
select * from finish();
rollback;

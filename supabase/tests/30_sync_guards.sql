-- POC sync-guard test. Run after 0001_poc_baseline.sql.

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

insert into auth.users (id, email) values
    ('44444444-4444-4444-4444-444444444444', 'sync@test');

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

select 'ALL POC SYNC-GUARD TESTS PASSED' as result;

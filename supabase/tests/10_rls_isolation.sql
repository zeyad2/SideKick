-- POC RLS isolation test. Run after 0001_poc_baseline.sql.

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users (id, email) values
    ('11111111-1111-1111-1111-111111111111', 'a@test'),
    ('22222222-2222-2222-2222-222222222222', 'b@test'),
    ('33333333-3333-3333-3333-333333333333', 'c@test');

delete from public.profiles where id = '33333333-3333-3333-3333-333333333333';

insert into public.places (id, user_id, name, lat, lng) values
    ('aaaaaaaa-0000-0000-0000-0000000000a1', '11111111-1111-1111-1111-111111111111', 'A place', 30, 31),
    ('bbbbbbbb-0000-0000-0000-0000000000b2', '22222222-2222-2222-2222-222222222222', 'B place', 30, 31);

insert into public.captures (id, user_id, source, input_text) values
    ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'typed', 'A capture'),
    ('bbbbbbbb-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'typed', 'B capture');

insert into public.task_reminders (
    id, user_id, title, source, confidence, trigger_type, scheduled_at, capture_id
) values
    ('aaaaaaaa-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111',
     'A reminder', 'typed', 0.9, 'time', now(), 'aaaaaaaa-0000-0000-0000-000000000001'),
    ('bbbbbbbb-0000-0000-0000-000000000012', '22222222-2222-2222-2222-222222222222',
     'B reminder', 'typed', 0.9, 'time', now(), 'bbbbbbbb-0000-0000-0000-000000000002');

insert into public.reminder_events (id, user_id, reminder_id, event_type) values
    ('aaaaaaaa-0000-0000-0000-000000000021', '11111111-1111-1111-1111-111111111111',
     'aaaaaaaa-0000-0000-0000-000000000011', 'created'),
    ('bbbbbbbb-0000-0000-0000-000000000022', '22222222-2222-2222-2222-222222222222',
     'bbbbbbbb-0000-0000-0000-000000000012', 'created');

insert into public.conversations (id, user_id, title) values
    ('aaaaaaaa-0000-0000-0000-000000000031', '11111111-1111-1111-1111-111111111111', 'A conversation'),
    ('bbbbbbbb-0000-0000-0000-000000000032', '22222222-2222-2222-2222-222222222222', 'B conversation');

insert into public.messages (id, user_id, conversation_id, role, content) values
    ('aaaaaaaa-0000-0000-0000-000000000041', '11111111-1111-1111-1111-111111111111',
     'aaaaaaaa-0000-0000-0000-000000000031', 'user', 'A message'),
    ('bbbbbbbb-0000-0000-0000-000000000042', '22222222-2222-2222-2222-222222222222',
     'bbbbbbbb-0000-0000-0000-000000000032', 'user', 'B message');

insert into public.events (id, user_id, event_type) values
    ('aaaaaaaa-0000-0000-0000-0000000000e1', '11111111-1111-1111-1111-111111111111', 'task_reminder_created'),
    ('bbbbbbbb-0000-0000-0000-0000000000e2', '22222222-2222-2222-2222-222222222222', 'task_reminder_created');

set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';

do $$
declare
    own_cnt int;
    other_cnt int;
    checked_table text;
    owner_col text;
begin
    foreach checked_table in array array[
      'profiles','places','captures','task_reminders','reminder_events',
      'conversations','messages','events'
    ]
    loop
      owner_col := case when checked_table = 'profiles' then 'id' else 'user_id' end;
      execute format(
        'select count(*) from public.%I where %I = $1',
        checked_table,
        owner_col
      ) into own_cnt using '11111111-1111-1111-1111-111111111111'::uuid;
      execute format(
        'select count(*) from public.%I where %I = $1',
        checked_table,
        owner_col
      ) into other_cnt using '22222222-2222-2222-2222-222222222222'::uuid;

      if own_cnt <> 1 then
        raise exception 'FAIL: user A should see 1 own % row, saw %', checked_table, own_cnt;
      end if;
      if other_cnt <> 0 then
        raise exception 'FAIL: user A must not see user B % rows, saw %', checked_table, other_cnt;
      end if;
    end loop;
end$$;

do $$
begin
    begin
        insert into public.profiles (id)
        values ('33333333-3333-3333-3333-333333333333');
        raise exception 'FAIL: profiles cross-user insert accepted';
    exception when insufficient_privilege then null; end;

    begin
        insert into public.places (user_id, name, lat, lng)
        values ('22222222-2222-2222-2222-222222222222', 'spoofed', 30, 31);
        raise exception 'FAIL: places cross-user insert accepted';
    exception when insufficient_privilege then null; end;

    begin
        insert into public.captures (user_id, source, input_text)
        values ('22222222-2222-2222-2222-222222222222', 'typed', 'spoofed');
        raise exception 'FAIL: captures cross-user insert accepted';
    exception when insufficient_privilege then null; end;

    begin
        insert into public.task_reminders (
            user_id, title, source, confidence, trigger_type, scheduled_at
        ) values (
            '22222222-2222-2222-2222-222222222222',
            'spoofed', 'typed', 1, 'time', now()
        );
        raise exception 'FAIL: task_reminders cross-user insert accepted';
    exception when insufficient_privilege then null; end;

    begin
        insert into public.reminder_events (user_id, reminder_id, event_type)
        values (
            '22222222-2222-2222-2222-222222222222',
            'bbbbbbbb-0000-0000-0000-000000000012',
            'spoofed'
        );
        raise exception 'FAIL: reminder_events cross-user insert accepted';
    exception when insufficient_privilege then null; end;

    begin
        insert into public.conversations (user_id, title)
        values ('22222222-2222-2222-2222-222222222222', 'spoofed');
        raise exception 'FAIL: conversations cross-user insert accepted';
    exception when insufficient_privilege then null; end;

    begin
        insert into public.messages (user_id, conversation_id, role, content)
        values (
            '22222222-2222-2222-2222-222222222222',
            'bbbbbbbb-0000-0000-0000-000000000032',
            'user',
            'spoofed'
        );
        raise exception 'FAIL: messages cross-user insert accepted';
    exception when insufficient_privilege then null; end;

    begin
        insert into public.events (user_id, event_type)
        values ('22222222-2222-2222-2222-222222222222', 'spoofed');
        raise exception 'FAIL: events cross-user insert accepted';
    exception when insufficient_privilege then null; end;
end$$;

do $$
declare
    n int;
    checked_table text;
    owner_col text;
begin
    foreach checked_table in array array[
      'profiles','places','captures','task_reminders','reminder_events',
      'conversations','messages','events'
    ]
    loop
      owner_col := case when checked_table = 'profiles' then 'id' else 'user_id' end;

      execute format(
        'update public.%I set updated_at = now() where %I = $1',
        checked_table,
        owner_col
      ) using '22222222-2222-2222-2222-222222222222'::uuid;
      get diagnostics n = row_count;
      if n <> 0 then
        raise exception 'FAIL: cross-user update affected % % rows', n, checked_table;
      end if;

      execute format(
        'delete from public.%I where %I = $1',
        checked_table,
        owner_col
      ) using '22222222-2222-2222-2222-222222222222'::uuid;
      get diagnostics n = row_count;
      if n <> 0 then
        raise exception 'FAIL: cross-user delete affected % % rows', n, checked_table;
      end if;
    end loop;

    update public.reminder_events
    set metadata = '{"tampered":true}'::jsonb
    where id = 'aaaaaaaa-0000-0000-0000-000000000021';
    get diagnostics n = row_count;
    if n <> 0 then
      raise exception 'FAIL: owner update affected % immutable reminder_event rows', n;
    end if;

    delete from public.reminder_events
    where id = 'aaaaaaaa-0000-0000-0000-000000000021';
    get diagnostics n = row_count;
    if n <> 0 then
      raise exception 'FAIL: owner delete affected % immutable reminder_event rows', n;
    end if;

    update public.events
    set metadata = '{"tampered":true}'::jsonb
    where id = 'aaaaaaaa-0000-0000-0000-0000000000e1';
    get diagnostics n = row_count;
    if n <> 0 then
      raise exception 'FAIL: owner update affected % immutable event rows', n;
    end if;

    delete from public.events
    where id = 'aaaaaaaa-0000-0000-0000-0000000000e1';
    get diagnostics n = row_count;
    if n <> 0 then
      raise exception 'FAIL: owner delete affected % immutable event rows', n;
    end if;
end$$;

reset request.jwt.claims;
reset role;

select 'ALL POC RLS TESTS PASSED' as result;

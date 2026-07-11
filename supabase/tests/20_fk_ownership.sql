-- Same-user FK ownership + domain CHECK tests. Run AFTER bootstrap + migration.
-- Reproduces the P1-review attacks and proves they now FAIL:
--   (1) a user CANNOT attach a child row to another user's parent (composite FK);
--   (2) one tenant's delete therefore cannot mutate another tenant's rows;
--   (3) SET NULL nulls ONLY the FK column, never the NOT NULL user_id;
--   (4) domain CHECKs reject nonsensical values.
--
-- Exits non-zero (RAISE EXCEPTION) on any failure so CI can gate on it.

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- Two fresh users (distinct from the RLS test's) + a task & capture owned by C.
insert into auth.users (id, email) values
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'c@test'),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'd@test');

insert into public.tasks (id, user_id, title) values
    ('cccc0000-0000-0000-0000-000000000001', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'C task');
insert into public.captures (id, user_id, status) values
    ('cccc0000-0000-0000-0000-0000000000ca', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'ready');

-- ============================================================================
-- Act as user D (attacker). D must NOT be able to bind children to C's rows.
-- ============================================================================
set role authenticated;
set request.jwt.claims = '{"sub":"dddddddd-dddd-dddd-dddd-dddddddddddd"}';

-- ATTACK 1: focus_session referencing C's task -> composite FK must reject.
do $$
begin
    begin
        insert into public.focus_sessions (user_id, task_id, duration_minutes)
        values ('dddddddd-dddd-dddd-dddd-dddddddddddd',
                'cccc0000-0000-0000-0000-000000000001', 25);
        raise exception 'FAIL: D attached a focus_session to C''s task';
    exception when foreign_key_violation then
        raise notice 'PASS: cross-tenant focus_session FK rejected';
    end;
end$$;

-- ATTACK 2: reminder referencing C's task -> composite FK must reject.
do $$
begin
    begin
        insert into public.reminders (user_id, reminder_type, task_id, scheduled_at)
        values ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'time',
                'cccc0000-0000-0000-0000-000000000001', now());
        raise exception 'FAIL: D attached a reminder to C''s task';
    exception when foreign_key_violation then
        raise notice 'PASS: cross-tenant reminder FK rejected';
    end;
end$$;

-- ATTACK 3: task referencing C's capture -> composite FK must reject.
do $$
begin
    begin
        insert into public.tasks (user_id, capture_id, title)
        values ('dddddddd-dddd-dddd-dddd-dddddddddddd',
                'cccc0000-0000-0000-0000-0000000000ca', 'stolen capture');
        raise exception 'FAIL: D attached a task to C''s capture';
    exception when foreign_key_violation then
        raise notice 'PASS: cross-tenant capture FK rejected';
    end;
end$$;

reset request.jwt.claims;
reset role;

-- ============================================================================
-- Positive + cascade-isolation: as owner, C attaches its own child, then the
-- attack being impossible means C's delete can only touch C's own rows.
-- ============================================================================
insert into public.focus_sessions (id, user_id, task_id, duration_minutes)
values ('cccc0000-0000-0000-0000-0000000000f5',
        'cccccccc-cccc-cccc-cccc-cccccccccccc',
        'cccc0000-0000-0000-0000-000000000001', 25);

-- Delete C's task; its own session must SET NULL only task_id (user_id survives).
delete from public.tasks where id = 'cccc0000-0000-0000-0000-000000000001';
do $$
declare tid uuid; uid uuid;
begin
    select task_id, user_id into tid, uid
    from public.focus_sessions where id = 'cccc0000-0000-0000-0000-0000000000f5';
    if tid is not null then
        raise exception 'FAIL: task_id should be NULL after parent delete, got %', tid;
    end if;
    if uid is distinct from 'cccccccc-cccc-cccc-cccc-cccccccccccc' then
        raise exception 'FAIL: SET NULL clobbered user_id (got %)', uid;
    end if;
    raise notice 'PASS: SET NULL nulled task_id only; user_id intact';
end$$;

-- ============================================================================
-- Domain CHECKs (as owner; these are table constraints, not RLS).
-- ============================================================================
do $$
declare
    C constant uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
begin
    -- negative planned duration
    begin
        insert into public.focus_sessions (user_id, duration_minutes) values (C, -5);
        raise exception 'FAIL: negative duration_minutes accepted';
    exception when check_violation then null; end;

    -- negative block_attempts
    begin
        insert into public.focus_sessions (user_id, duration_minutes, block_attempts)
        values (C, 25, -2);
        raise exception 'FAIL: negative block_attempts accepted';
    exception when check_violation then null; end;

    -- out-of-range lat/lng + non-positive radius
    begin
        insert into public.places (user_id, name, lat, lng) values (C, 'bad', 999, -999);
        raise exception 'FAIL: out-of-range lat/lng accepted';
    exception when check_violation then null; end;
    begin
        insert into public.places (user_id, name, lat, lng, radius_m)
        values (C, 'bad', 0, 0, -10);
        raise exception 'FAIL: non-positive radius_m accepted';
    exception when check_violation then null; end;

    -- negative dwell_seconds
    begin
        insert into public.reminders (user_id, reminder_type, scheduled_at, dwell_seconds)
        values (C, 'time', now(), -60);
        raise exception 'FAIL: negative dwell_seconds accepted';
    exception when check_violation then null; end;

    -- resulting_* set while status <> 'triaged'
    begin
        insert into public.captures (user_id, status, resulting_type)
        values (C, 'ready', 'task');
        raise exception 'FAIL: resulting_type set on non-triaged capture accepted';
    exception when check_violation then null; end;

    -- triaged capture with NO resulting_* (the other half of the constraint)
    begin
        insert into public.captures (user_id, status) values (C, 'triaged');
        raise exception 'FAIL: triaged capture without resulting_* accepted';
    exception when check_violation then null; end;

    raise notice 'PASS: all domain CHECKs rejected bad values';
end$$;

select 'ALL FK-OWNERSHIP + CHECK TESTS PASSED' as result;

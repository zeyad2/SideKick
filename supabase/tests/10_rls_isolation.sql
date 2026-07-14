-- RLS isolation test. Run AFTER bootstrap + migration.
-- Proves: (1) migration applied (tables exist), (2) a user sees only their own
-- rows, (3) a user CANNOT read another user's rows, (4) WITH CHECK blocks
-- inserting rows owned by someone else.
--
-- Exits non-zero (via RAISE EXCEPTION) on any failure so CI can gate on it.

-- Grant the authenticated role table privileges (Supabase grants these; RLS then
-- narrows row visibility on top of the grant).
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- Seed two users + one task each, as the table OWNER (RLS bypassed for setup).
insert into auth.users (id, email) values
    ('11111111-1111-1111-1111-111111111111', 'a@test'),
    ('22222222-2222-2222-2222-222222222222', 'b@test');
-- profiles are auto-created by the on_auth_user_created trigger.

insert into public.tasks (id, user_id, title) values
    ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'A task'),
    ('bbbbbbbb-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'B task');

-- One event each (D9 append-only log) — RLS must isolate it like every table.
insert into public.events (id, user_id, event_type) values
    ('aaaaaaaa-0000-0000-0000-0000000000e1', '11111111-1111-1111-1111-111111111111', 'task_created'),
    ('bbbbbbbb-0000-0000-0000-0000000000e2', '22222222-2222-2222-2222-222222222222', 'task_created');

-- ---- Become user A (authenticated role + A's JWT) ----
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';

do $$
declare
    own_cnt   int;
    other_cnt int;
begin
    select count(*) into own_cnt   from public.tasks where user_id = '11111111-1111-1111-1111-111111111111';
    select count(*) into other_cnt from public.tasks where user_id = '22222222-2222-2222-2222-222222222222';

    if own_cnt <> 1 then
        raise exception 'FAIL: user A should see 1 own task, saw %', own_cnt;
    end if;
    if other_cnt <> 0 then
        raise exception 'FAIL: user A must NOT see user B rows, saw %', other_cnt;
    end if;
    raise notice 'PASS: user A sees own row only (own=%, other=%)', own_cnt, other_cnt;
end$$;

-- Same isolation must hold for the events log (D9).
do $$
declare
    own_cnt   int;
    other_cnt int;
begin
    select count(*) into own_cnt   from public.events where user_id = '11111111-1111-1111-1111-111111111111';
    select count(*) into other_cnt from public.events where user_id = '22222222-2222-2222-2222-222222222222';

    if own_cnt <> 1 then
        raise exception 'FAIL: user A should see 1 own event, saw %', own_cnt;
    end if;
    if other_cnt <> 0 then
        raise exception 'FAIL: user A must NOT see user B events, saw %', other_cnt;
    end if;
    raise notice 'PASS: events RLS isolates users (own=%, other=%)', own_cnt, other_cnt;
end$$;

-- A cannot INSERT a row owned by B (WITH CHECK must reject).
do $$
begin
    begin
        insert into public.tasks (user_id, title)
        values ('22222222-2222-2222-2222-222222222222', 'spoofed');
        raise exception 'FAIL: user A was allowed to insert a row owned by B';
    exception when insufficient_privilege then
        raise notice 'PASS: WITH CHECK blocked cross-user insert';
    end;
end$$;

reset request.jwt.claims;
reset role;

-- Total row count as owner confirms B's row still exists (A never deleted/saw it).
do $$
declare total int;
begin
    select count(*) into total from public.tasks;
    if total <> 2 then
        raise exception 'FAIL: expected 2 total tasks as owner, got %', total;
    end if;
    raise notice 'PASS: both users'' rows intact (total=%)', total;
end$$;

select 'ALL RLS TESTS PASSED' as result;

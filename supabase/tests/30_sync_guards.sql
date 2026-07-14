-- Server-side sync-guard test. Run AFTER bootstrap + all migrations (needs 0003).
-- Proves the three attacks the P2 review reproduced are now defended:
--   (1) a stale push CANNOT overwrite a newer row (conditional LWW trigger),
--   (2) a future-dated push is clamped to now() (clock-skew guard),
--   (3) an authenticated owner CANNOT UPDATE or DELETE their own events
--       (append-only immutability at the authorization boundary).
--
-- Exits non-zero (via RAISE EXCEPTION) on any failure so CI can gate on it.

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users (id, email) values
    ('33333333-3333-3333-3333-333333333333', 'g@test');

-- ============================================================================
-- (1) Conditional LWW: a stale write must NOT clobber a newer stored row.
-- ============================================================================
insert into public.tasks (id, user_id, title, updated_at) values
    ('cccccccc-0000-0000-0000-000000000001',
     '33333333-3333-3333-3333-333333333333',
     'Newer value',
     '2026-07-12T15:00:00Z');

set role authenticated;
set request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333"}';

-- Simulate a PostgREST upsert of an OLDER version of the same row.
insert into public.tasks (id, user_id, title, updated_at) values
    ('cccccccc-0000-0000-0000-000000000001',
     '33333333-3333-3333-3333-333333333333',
     'Stale value',
     '2026-07-12T09:00:00Z')
on conflict (id) do update set
    title = excluded.title,
    updated_at = excluded.updated_at;

do $$
declare t text;
begin
    select title into t from public.tasks
        where id = 'cccccccc-0000-0000-0000-000000000001';
    if t <> 'Newer value' then
        raise exception 'FAIL: stale push overwrote newer row (title=%)', t;
    end if;
    raise notice 'PASS: conditional LWW rejected the stale write';
end$$;

-- ============================================================================
-- (2) Clock-skew clamp: a far-future updated_at is clamped to ~now().
-- ============================================================================
insert into public.tasks (id, user_id, title, updated_at) values
    ('cccccccc-0000-0000-0000-000000000002',
     '33333333-3333-3333-3333-333333333333',
     'From a fast clock',
     now() + interval '1 hour');

do $$
declare u timestamptz;
begin
    select updated_at into u from public.tasks
        where id = 'cccccccc-0000-0000-0000-000000000002';
    if u > now() + interval '5 minutes' then
        raise exception 'FAIL: future updated_at not clamped (%)', u;
    end if;
    raise notice 'PASS: clock-skew guard clamped a future timestamp';
end$$;

-- ============================================================================
-- (3) Events immutability: owner UPDATE/DELETE must be denied by RLS.
-- ============================================================================
reset request.jwt.claims;
reset role;

insert into public.events (id, user_id, event_type) values
    ('cccccccc-0000-0000-0000-0000000000e3',
     '33333333-3333-3333-3333-333333333333',
     'task_created');

set role authenticated;
set request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333"}';

-- UPDATE must affect zero rows (no UPDATE policy → row invisible to the write).
do $$
declare n int;
begin
    update public.events set event_type = 'tampered'
        where id = 'cccccccc-0000-0000-0000-0000000000e3';
    get diagnostics n = row_count;
    if n <> 0 then
        raise exception 'FAIL: owner was able to UPDATE % event row(s)', n;
    end if;
    raise notice 'PASS: owner UPDATE of an event affected 0 rows';
end$$;

-- DELETE must likewise affect zero rows.
do $$
declare n int;
begin
    delete from public.events
        where id = 'cccccccc-0000-0000-0000-0000000000e3';
    get diagnostics n = row_count;
    if n <> 0 then
        raise exception 'FAIL: owner was able to DELETE % event row(s)', n;
    end if;
    raise notice 'PASS: owner DELETE of an event affected 0 rows';
end$$;

reset request.jwt.claims;
reset role;

-- Confirm the event survived, unchanged, as owner.
do $$
declare t text;
begin
    select event_type into t from public.events
        where id = 'cccccccc-0000-0000-0000-0000000000e3';
    if t <> 'task_created' then
        raise exception 'FAIL: event was mutated (event_type=%)', t;
    end if;
    raise notice 'PASS: event row intact and immutable';
end$$;

select 'ALL SYNC-GUARD TESTS PASSED' as result;

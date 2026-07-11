-- Test-only bootstrap: reproduce the pieces of Supabase's platform that the
-- migration depends on, so 0001_initial_schema.sql applies to a *plain* Postgres.
-- NOT part of the shipped schema. Supabase provides all of this in production.

create schema if not exists auth;

create table if not exists auth.users (
    id    uuid primary key default gen_random_uuid(),
    email text
);

-- auth.uid() reads the current request's JWT 'sub' claim, exactly like Supabase.
-- In tests we set request.jwt.claims via SET to simulate different users.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
    select nullif(
        current_setting('request.jwt.claims', true)::json ->> 'sub',
        ''
    )::uuid;
$$;

-- The role RLS is evaluated as. A non-superuser so policies are actually enforced
-- (superusers and table owners BYPASS RLS).
do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end$$;

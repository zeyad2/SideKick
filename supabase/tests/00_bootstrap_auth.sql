create extension if not exists pgtap with schema extensions;
select plan(1);

select ok(
    exists (select 1 from information_schema.schemata where schema_name = 'auth'),
    'Supabase auth schema is present for db tests'
);
select * from finish();

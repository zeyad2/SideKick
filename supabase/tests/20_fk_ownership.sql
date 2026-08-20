-- POC same-user FK ownership test. Run after 0001_poc_baseline.sql.

insert into auth.users (id, email) values
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'c-fk@test'),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'd-fk@test');

insert into public.places (id, user_id, name, lat, lng) values
    ('cccc0000-0000-0000-0000-000000000001', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'C place', 30, 31);
insert into public.captures (id, user_id, source, input_text) values
    ('cccc0000-0000-0000-0000-0000000000ca', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'typed', 'C capture');

do $$
begin
    begin
        insert into public.task_reminders (
            user_id, title, source, confidence, trigger_type, scheduled_at, capture_id
        ) values (
            'dddddddd-dddd-dddd-dddd-dddddddddddd',
            'stolen capture', 'typed', 1, 'time', now(),
            'cccc0000-0000-0000-0000-0000000000ca'
        );
        raise exception 'FAIL: cross-user capture FK was accepted';
    exception when foreign_key_violation then null; end;

    begin
        insert into public.task_reminders (
            user_id, title, source, confidence, trigger_type, place_id, geofence_transition
        ) values (
            'dddddddd-dddd-dddd-dddd-dddddddddddd',
            'stolen place', 'typed', 1, 'place',
            'cccc0000-0000-0000-0000-000000000001', 'enter'
        );
        raise exception 'FAIL: cross-user place FK was accepted';
    exception when foreign_key_violation then null; end;
end$$;

select 'ALL POC FK TESTS PASSED' as result;

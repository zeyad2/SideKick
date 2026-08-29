-- Make reviewed-draft approval idempotent at the database boundary.
-- Safe on fresh databases where 0001 already contains these objects and on
-- existing local test databases created before draft_id was introduced.

alter table public.task_reminders
    add column if not exists draft_id text;

create unique index if not exists task_reminders_capture_draft_uidx
    on public.task_reminders (user_id, capture_id, draft_id)
    where capture_id is not null and draft_id is not null and deleted_at is null;

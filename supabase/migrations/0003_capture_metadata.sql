-- Keep capture workflow state separate from the human-readable error field.
alter table public.captures
    add column if not exists metadata jsonb not null default '{}'::jsonb;

# Sidekick — Entity Relationship Diagram

Generated from `supabase/migrations/0001_initial_schema.sql` plus the additive
`0002_events_log.sql` and `0004_capture_decomposition.sql` (post-P1-lock migrations).
This diagram matches those migrations exactly (every table and relationship). Sync/audit columns
(`created_at`, `updated_at`, `deleted_at`) are present on every syncable table and
omitted from the boxes below only to keep the diagram readable — they are called
out in `SCHEMA.md`.

Every parent→child FK below is **composite** — `(parent_id, user_id) REFERENCES
parent(id, user_id)` — so a child can only attach to a parent owned by the same
user (see `SCHEMA.md §Same-user FK ownership`). Cardinality `o|--o{` marks a
nullable/optional parent link; `||--o{` a mandatory one.

```mermaid
erDiagram
    auth_users ||--|| profiles : "1:1 (id)"

    profiles ||--o{ captures          : owns
    profiles ||--o{ goals             : owns
    profiles ||--o{ tasks             : owns
    profiles ||--o{ notes             : owns
    profiles ||--o{ habits            : owns
    profiles ||--o{ habit_completions : owns
    profiles ||--o{ places            : owns
    profiles ||--o{ focus_sessions    : owns
    profiles ||--o{ vibe_checks       : owns
    profiles ||--o{ reminders         : owns
    profiles ||--o{ block_list        : owns
    profiles ||--o{ events            : "owns (0002, additive)"

    captures  o|--o{ tasks  : "triaged into (SET NULL)"
    captures  o|--o{ notes  : "triaged into (SET NULL)"
    captures  o|--o{ habits : "triaged into (SET NULL)"
    captures  o|--o{ goals  : "triaged into (SET NULL)"

    goals o|--o{ tasks  : "ladders up (SET NULL)"
    goals o|--o{ habits : "ladders up (SET NULL)"

    habits         ||--o{ habit_completions : "logged (CASCADE)"
    tasks          o|--o{ focus_sessions    : "anchors (SET NULL)"
    focus_sessions o|--o{ vibe_checks       : "prompts (CASCADE, nullable)"

    tasks  o|--o{ reminders : "targets (CASCADE, nullable)"
    habits o|--o{ reminders : "targets (CASCADE, nullable)"
    places o|--o{ reminders : "geofence (CASCADE, nullable)"

    profiles {
        uuid id PK "= auth.users.id"
        text persona_response_language "CHECK en|ar-EG, default en"
        text theme "default analog_companion"
        jsonb prefs "additive UI config"
    }

    captures {
        uuid id PK
        uuid user_id FK
        text audio_path
        text raw_transcript
        text llm_type "CHECK task|note|habit|uncategorized"
        text title
        text details
        jsonb suggested_schedule
        text status "CHECK pending|processing|ready|triaged|failed|discarded"
        text resulting_type "legacy loose link; task|note|habit|goal"
        uuid resulting_id "legacy loose link"
        jsonb proposed_items "ordered decomposition drafts"
        jsonb dispositioned_item_ids "saved or dropped draft ids"
        timestamptz auto_committed_at "durable recovery marker"
        timestamptz captured_at
    }

    goals {
        uuid id PK
        uuid user_id FK
        uuid capture_id FK "SET NULL"
        text title
        text why "motivation / north-star"
        text status "CHECK active|achieved|paused|dropped"
        date target_date "optional"
    }

    tasks {
        uuid id PK
        uuid user_id FK
        uuid capture_id FK "SET NULL"
        uuid goal_id FK "SET NULL"
        text title
        text details
        text status "CHECK todo|done|archived"
        text next_action
        timestamptz scheduled_at
        timestamptz completed_at
        timestamptz last_activity_at
    }

    notes {
        uuid id PK
        uuid user_id FK
        uuid capture_id FK "SET NULL"
        text title
        text body
    }

    habits {
        uuid id PK
        uuid user_id FK
        uuid capture_id FK "SET NULL"
        uuid goal_id FK "SET NULL"
        text title
        jsonb frequency_config
        jsonb level_config
        text anchor_description
        bool reset_active
        timestamptz reset_started_at
        bool archived
    }

    habit_completions {
        uuid id PK
        uuid user_id FK
        uuid habit_id FK "CASCADE"
        text level "CHECK mini|normal|mega"
        text energy_mode "CHECK low|normal|charged"
        timestamptz completed_at
    }

    places {
        uuid id PK
        uuid user_id FK
        text name
        float8 lat "CHECK -90..90"
        float8 lng "CHECK -180..180"
        int radius_m "default 150, CHECK > 0"
    }

    focus_sessions {
        uuid id PK
        uuid user_id FK
        uuid task_id FK "SET NULL"
        text task_label
        int duration_minutes "CHECK > 0"
        timestamptz started_at
        timestamptz ended_at
        text status "CHECK active|completed|abandoned"
        bool blocking_enabled
        text blocking_mode "CHECK soft|hard"
        int block_attempts "CHECK >= 0"
        jsonb captures_during "array of capture ids"
    }

    vibe_checks {
        uuid id PK
        uuid user_id FK
        uuid focus_session_id FK "CASCADE, nullable"
        smallint value "CHECK 1..3"
    }

    reminders {
        uuid id PK
        uuid user_id FK
        text reminder_type "CHECK time|geofence"
        uuid task_id FK "CASCADE"
        uuid habit_id FK "CASCADE"
        timestamptz scheduled_at
        jsonb recurrence
        timestamptz snooze_until
        uuid place_id FK "CASCADE"
        text geofence_transition "CHECK enter|exit"
        int dwell_seconds "default 60, CHECK >= 0"
        text copy
        text status "CHECK scheduled|fired|done|cancelled"
    }

    block_list {
        uuid id PK
        uuid user_id FK
        text platform "CHECK android|ios"
        text app_identifier "pkg name | iOS token"
        text app_label
    }

    events {
        uuid id PK
        uuid user_id FK "CASCADE"
        text event_type "free-text; no CHECK (taxonomy grows)"
        text entity_type "loose polymorphic link; no FK"
        uuid entity_id "loose link; nullable"
        jsonb metadata "opaque per-event payload"
        timestamptz occurred_at
    }
```

> `events` (additive migration `0002`, post-P1-lock) has only the `profiles` ownership edge:
> its `entity_type` / `entity_id` is a **loose polymorphic link with no FK** (like
> `captures.resulting_id`), so no edge is drawn to tasks/habits/etc. Append-only + immutable —
> see [`EVENTS.md`](./EVENTS.md).

## Relationship / ON DELETE summary

All child FKs are composite `(fk_col, user_id) → parent(id, user_id)`. SET-NULL rows
use PG15 column-list `SET NULL (fk_col)` so only the FK column is nulled, never the
NOT NULL `user_id`.

| Parent → Child | FK | ON DELETE | Why |
|---|---|---|---|
| auth.users → profiles | profiles.id | CASCADE | profile is meaningless without the user |
| profiles → every table | *.user_id | CASCADE | deleting the account removes all their data |
| profiles → events (0002) | events.user_id | CASCADE | deleting the account removes their event log |
| captures → tasks/notes/habits/goals | (capture_id, user_id) | SET NULL (capture_id) | the typed record outlives the raw capture |
| goals → tasks/habits | (goal_id, user_id) | SET NULL (goal_id) | deleting a goal must not delete the work under it |
| habits → habit_completions | (habit_id, user_id) | CASCADE | a completion has no meaning without its habit |
| tasks → focus_sessions | (task_id, user_id) | SET NULL (task_id) | keep session history even if the task is deleted |
| focus_sessions → vibe_checks | (focus_session_id, user_id) | CASCADE | the vibe check belongs to that session |
| tasks/habits → reminders | (task_id, user_id) / (habit_id, user_id) | CASCADE | a reminder for a deleted target is noise |
| places → reminders | (place_id, user_id) | CASCADE | a geofence reminder for a deleted place is noise |

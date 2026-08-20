# Sidekick — Schema Rationale (P1)

**Status:** ✅ **LOCKED** (2026-07-11) — human review gate passed. Post-lock changes
require a *new* migration, never an edit to `0001_initial_schema.sql`. The review
checklist below is fully walked; Q1–Q4 are resolved.

Authoritative artifacts:
- Migration: [`supabase/migrations/0001_initial_schema.sql`](../supabase/migrations/0001_initial_schema.sql)
- ERD: [`docs/ERD.md`](./ERD.md)
- Apply + RLS test: `bash scripts/test_migration.sh` (throwaway Postgres via Docker)

> **Source-doc note for the reviewer.** The referenced `SIDEKICK_SPEC.md` (with
> its "Part 2 / Part 5 / Part 6") is **not present in the repo** — only
> `SIDEKICK_BUILD_PLAN.md` and `DESIGN_SYSTEN.md` exist. This schema was therefore
> derived from the build plan's phase prompts (P3–P12), which enumerate every
> screen's fields and every table by name. Where the spec's "Part 6" would have
> pinned an exact column, I inferred it from the feature that uses it and flagged
> the inference below. **If the real spec surfaces, re-check the flagged items
> before locking.**

---

## R0 — The most important review decision: where sync bookkeeping lives

> **RATIFIED at the P1 review gate (2026-07-11):** the local-only placement of
> `dirty` / `synced_at` / `last_pull` is approved. The cloud schema owns
> `updated_at` + `deleted_at`; the drift mirror (P2) owns the local bookkeeping. No
> dead columns are added to Postgres.

The P1 brief says "sync columns on every syncable table: `dirty` (bool) and
`synced_at` (nullable)". I made a **deliberate deviation** and need you to ratify it:

**`dirty`, `synced_at`, and `last_pull` are CLIENT-LOCAL only. They do NOT exist
in this cloud Postgres schema.** The cloud schema instead carries two columns that
sync genuinely needs server-side:

- **`updated_at timestamptz`** — the last-write-wins clock.
- **`deleted_at timestamptz`** — the soft-delete tombstone.

Reasoning:
- `dirty` = "this local row has un-pushed changes." On the server every row is, by
  definition, already pushed. It would be a permanently-`false` dead column.
- `synced_at` = "when this device last pushed this row." That's per-device local
  state; storing it in the shared cloud row is meaningless (which device?).
- `last_pull` = "the newest `updated_at` this device has already pulled." Also
  per-device. It lives in a **drift-only `sync_meta` table** (P2), one cursor row
  (optionally per-table). Putting it in the cloud would corrupt multi-device sync.

So the contract is: **the drift mirror (P2) adds `dirty` + `synced_at` locally; the
cloud schema owns `updated_at` + `deleted_at`.** Both sides are still "syncable
tables with sync columns" — they just carry the columns that make sense on each
side. If you'd rather I add literal dead `dirty`/`synced_at` columns to Postgres to
match the brief word-for-word, that's a one-line change per table — say so at the
gate.

### Sync-column semantics (the exact rules P2 must implement)

- **`updated_at` is client-owned.** On every local create/update the client sets
  `updated_at = now()` (device wall-clock). The server does **not** rewrite it (no
  trigger) — otherwise LWW would compare server-receipt time, not edit time.
- **`dirty` (local):** set `true` on any local mutation; set `false` after a
  successful push of that row.
- **`synced_at` (local):** set to the push time when `dirty` clears; `null` = never
  synced.
- **`last_pull` (local cursor):** after a pull, advance it to the max `updated_at`
  seen. Next pull asks the server for `updated_at > last_pull`.
- **Last-write-wins (pull side):** on pull, for each incoming row compare
  `incoming.updated_at` vs `local.updated_at`; the larger wins. On an exact tie the
  incoming row wins deterministically (see the tie rule below) — applying it is
  idempotent when the payloads are identical, and convergent when they differ
  because every device applies the *same* server-arbitrated winner.
- **Last-write-wins (push side) — a CONDITIONAL upsert, NOT a plain one.** A plain
  `on conflict do update` overwrites by *arrival order*, so a late-arriving stale
  edit clobbers a newer one. Push MUST guard the update on the timestamp:

  ```sql
  insert into public.tasks (...) values (...)
  on conflict (id) do update
     set <cols> = excluded.<cols>
   where excluded.updated_at > public.tasks.updated_at
      or (excluded.updated_at = public.tasks.updated_at
          and excluded.id > public.tasks.id);  -- deterministic tie rule
  ```

  The `WHERE` makes the server reject any push whose `updated_at` is older than the
  row it would replace, so a stale device can never overwrite a newer edit. The
  server is the single arbiter of arrival order, so both devices converge on the
  same survivor at their next pull. (For a same-`id` collision the id tiebreak is a
  no-op; it is written explicitly so the rule is total and copy-pastable to any
  future table whose conflict key is not the id.)
- **Clock-skew guard.** `updated_at` is device wall-clock (§above), so a device with
  a fast clock could otherwise win every race permanently. The server therefore
  **clamps a pushed `updated_at` to `now()` when it exceeds `now()` by more than a
  small tolerance** (e.g. 5 min), rejecting timestamps from the future. This bounds
  the damage of one skewed clock to at most the tolerance window. Deeper conflict
  resolution (field-level merge, vector clocks) remains an explicit v2 problem (D5).
- **Deletes propagate via `deleted_at`, not row removal.** A hard `DELETE` can't be
  observed by a pull-since-`last_pull` cursor, so a deleted row would resurrect on
  other devices. Repositories therefore soft-delete (set `deleted_at` + bump
  `updated_at`) and filter `deleted_at IS NULL` on reads. A later reaper may hard-
  delete old tombstones.

---

## Preferences storage decision (hybrid) — profiles

The brief asks for a *deliberate* choice: discrete columns vs a JSONB `prefs` blob.
**Decision: hybrid, with a clear rule.**

- **Discrete column** when the preference (a) drives core behaviour we branch on,
  (b) needs a server-side `CHECK`, or (c) could ever be filtered/queried:
  - `persona_response_language` (`en` / `ar-EG`) — gates every persona LLM call
    (D2); `CHECK`-constrained.
  - `theme` (default `analog_companion`) — selects the active theme (D8). Left
    free-text (no `CHECK`) precisely because themes are meant to grow.
- **`prefs jsonb`** for additive, client-only, never-queried UI config that must
  grow **without a migration per toggle**:
  - `capture_trigger` `{key, press_count}` (P3/P10 — e.g. triple-press Vol Up)
  - `energy_time_rules[]` (P10 default-energy-by-time-of-day)
  - onboarding flags (`onboarding_completed`, …)

Why not all-JSONB: the two behaviour-driving prefs deserve type safety and a
`CHECK`; burying `persona_response_language` in JSON invites an invalid value that
breaks every persona call. Why not all-columns: trigger config and time rules are
device-UX knobs no query ever touches — a column each is churn for nothing, and
D8/preferences explicitly want "room to grow." The rule above tells P2/P10 exactly
where a new preference goes.

---

## Post-lock additive migrations (NOT part of the P1 lock)

The P1 lock covers `0001_initial_schema.sql` only. Additive migrations added *after* the
lock are recorded here for traceability; they never edit `0001`.

### `0002_events_log.sql` — behavioural event log (decision D9)

A single append-only, immutable `events` table — **write-only groundwork for a FUTURE
insights feature** (behavioural analysis, tips, energy-over-time). We log behaviour as it
happens because history cannot be backfilled; the read side is deliberately unbuilt. Full
taxonomy + the write-now / read-later / no-shame contract live in
[`docs/EVENTS.md`](./EVENTS.md).

- **`event_type`** — free-text, **no CHECK** (same reasoning as `theme`: the taxonomy grows
  constantly; a CHECK would force a migration per type). Validated client-side against EVENTS.md.
- **`entity_type` / `entity_id`** — loose polymorphic link, **no FK** (same precedent as
  `captures.resulting_id`): points into different tables depending on `entity_type`.
- **`metadata jsonb`** — opaque per-event payload, read whole by the analysis code, never
  filtered in SQL (same rule as `suggested_schedule` / `frequency_config`).
- **Immutable / append-only** — rows are only ever inserted; the sole later mutation is a
  reaper setting `deleted_at`. Because ids are client-generated and rows never update, sync
  push is a pure INSERT with **no last-write-wins conflict** to resolve.
- **Indexes** — only the two the insights feature is certain to need
  (`(user_id, event_type, occurred_at desc)` and `(entity_type, entity_id, occurred_at desc)`),
  both partial on `deleted_at is null`. Richer read-path indexes ship WITH the insights
  migration, when the queries are known — not speculatively (each index taxes the frequent write).
- **RLS** — owner-only, identical shape to every `0001` table.

Emission is a **P2 repository responsibility** (write-only, non-blocking); no phase in the
current build plan builds a read/analytics surface.

### `0004_capture_decomposition.sql` — one capture to many typed records

Adds `captures.proposed_items`, `captures.dispositioned_item_ids`, and
`captures.auto_committed_at`, plus the missing `goals.capture_id` provenance FK.
The former 1:1 terminal checks are replaced by decomposition-aware invariants:
legacy triage still requires its result pair, while decomposed triage requires a
disposition for every proposed item. The durable auto-commit timestamp powers the
restart-safe inbox recovery strip.

---

## Table-by-table rationale (the non-obvious choices)

### Why `captures` is separate from typed records
A capture is an **immutable inbox event** — audio the user dumped, plus the
transcript Gemini produced. It is created by the native pipeline (P3) fully offline,
*before* any categorisation exists. Triage (P4) later decomposes it into zero or
more tasks, notes, habits, and goals. Keeping capture separate:
- preserves the raw transcript permanently (auditability, re-triage, "transcript
  always visible" in the triage sheet);
- decouples the failure domains — capture must never be lost even if Gemini is down
  (`status = pending/failed` keeps it in the inbox queue);
- lets draft kinds be corrected before approval without rewriting real records.

`resulting_type` / `resulting_id` are retained only for legacy single-result rows.
For decomposition, stable draft ids become child ids and
`dispositioned_item_ids` records every saved or dropped draft. A decomposed capture
may become `triaged` only when that disposition count matches `proposed_items`.

### Why JSONB for `suggested_schedule`, `frequency_config`, `level_config`, `recurrence`
These are **heterogeneous, evolving, read-whole** structures the app interprets
client-side and never filters on in SQL:
- `captures.suggested_schedule` — Gemini's free-form schedule proposal (a date, a
  time-of-day, "every morning"…). Its shape will change as the prompt evolves;
  columns would mean a migration each time.
- `habits.frequency_config` — recurrence is genuinely polymorphic (daily / N-per-
  week / specific weekdays / interval). Normalising it into columns buys nothing
  because we never query "all habits due Tuesday" in SQL — the client computes
  due-ness.
- `habits.level_config` — optional per-level (mini/normal/mega) descriptions.
- `reminders.recurrence` — same argument as habit frequency.

Rule of thumb applied: **JSONB when the value is read as one opaque blob by the
client and never appears in a `WHERE`/`ORDER BY`;** a real column otherwise.

### `focus_sessions.captures_during` (JSONB array of capture ids)
Mid-session captures are queued and surfaced **after** the session (P7). This is an
ordered, append-only list scoped to a single session, read wholesale when the
session ends, and **never queried across sessions**. A join table (`session_captures`)
would add a table, a second write path, and a join for zero benefit. Read path:
`SELECT captures_during FROM focus_sessions WHERE id = ?` → array of capture ids →
`CapturesRepository.getByIds(...)`. If we ever need "which session did capture X
belong to," that's the moment to normalise — not before.

### `block_list.app_identifier` — one column, two platforms
Android identifies an app by a stable **package name** (`com.instagram.android`).
iOS FamilyControls gives an **opaque `ApplicationToken`** (base64), never a bundle
id. Both are "the string that identifies a blockable app," disambiguated by the
`platform` column — so one `app_identifier TEXT` holds either. This keeps P8
(Android) and P11 (iOS) on one table/model with a `platform` discriminator.
**Caveat (documented for P11):** iOS tokens are device-scoped and opaque; they are
*not* guaranteed to resolve on a different device, so a synced iOS block_list row
may be inert on another device. That's an Apple constraint, acceptable for a
personal build, and flagged here so P11 doesn't treat it as a bug.

### `tasks.last_activity_at` vs `updated_at`
P9 needs "task untouched for 48h" and "unactioned 3+ days." `updated_at` is the LWW
clock and moves on *sync-driven* writes too, so it can't answer "the human hasn't
touched this." `last_activity_at` is bumped only on genuine user activity, giving a
clean signal for the stale/avoidance scans (served by `idx_tasks_stale`).

### `user_id` denormalised onto every table
Even child tables (`habit_completions`, `vibe_checks`, `reminders`) carry `user_id`
though it's derivable through their parent FK. This makes every RLS policy a single
`auth.uid() = user_id` with no subquery (faster, un-foot-gunnable) and lets the
sync engine filter every table the same way. The tiny denormalisation cost is worth
the uniform, subquery-free RLS.

### Same-user FK ownership (composite FKs)

RLS controls what rows a user can *see*; it does **not** stop a user from binding a
child row to a parent they can't see. With plain single-column FKs (`child.parent_id
REFERENCES parent(id)`) user A could insert `focus_sessions`/`reminders` pointing at
user B's task by id — and worse, B's later delete of that task would `SET NULL` /
`CASCADE` into A's rows: one tenant's delete silently mutating another tenant's data.

Fix: every parent carries `UNIQUE (id, user_id)` and every child FK is **composite**,
`FOREIGN KEY (parent_id, user_id) REFERENCES parent(id, user_id)`. Because the child's
`user_id` is pinned to `auth.uid()` by RLS `WITH CHECK`, the FK can only resolve to a
parent owned by the *same* user. Cross-tenant attachment is now impossible, and a
delete can only ever cascade/null within one tenant.

- **`SET NULL` children** (`tasks/notes/habits/goals.capture_id`, `tasks/habits.goal_id`,
  `focus_sessions.task_id`) use Postgres 15's **column-list** form, `ON DELETE SET
  NULL (capture_id)`, so only the FK column is nulled — the `NOT NULL user_id` is
  untouched.
- **Nullable FK children** (`reminders.*`, `vibe_checks.focus_session_id`,
  `tasks/habits.goal_id`) rely on `MATCH SIMPLE` (the default): when the FK column is
  null the composite check is skipped, so freestanding reminders, standalone vibe
  checks, and goal-less tasks/habits still work.
- Parents with a composite ownership key: `captures`, `goals`, `tasks`, `habits`,
  `places`, `focus_sessions`.

### Goals — thin now, extensible later

P9's Goal Sage is **underspecified in the source** ("keep thin, flag for a spec
pass"). Rather than defer the table entirely — which would leave `tasks`/`habits`
with no ownership-correct way to attach to a goal later — the schema models the
**minimal, high-confidence core now** and gets the *relationships* right up front,
since those are the only part that touches the already-designed child tables.

- `goals` carries just `title`, `why` (motivation / Goal Sage's context), a
  lifecycle `status` (`active|achieved|paused|dropped`), and an **optional**
  `target_date` (goals need not be time-boxed — deliberately ADHD-friendly).
- **One goal per item:** `tasks.goal_id` and `habits.goal_id` are nullable composite
  FKs — an item ladders up to **at most one** goal. No join table; widen to
  many-to-many later *only* if the spec demands it (a clean additive migration).
- **Goals don't own their work:** deleting a goal `SET NULL`s `goal_id` on its
  tasks/habits (they survive) — the same "child outlives parent" logic as
  `captures → tasks`.
- **Deliberately NOT modelled** (added by a future migration once P9 specs them):
  sub-goals / goal hierarchy, milestones, progress computation, and any
  goal-breakdown logic. Nothing downstream is locked into a guess about those.

### Domain / semantic CHECK constraints

Beyond the enum CHECKs, these guard nonsensical values that RLS and FKs don't:

- `focus_sessions.duration_minutes > 0`, `focus_sessions.block_attempts >= 0`
- `places.lat BETWEEN -90 AND 90`, `places.lng BETWEEN -180 AND 180`, `places.radius_m > 0`
- `reminders.dwell_seconds >= 0`
- `captures`: `resulting_type`/`resulting_id` must be **null unless `status='triaged'`**,
  and **both present when `status='triaged'`** (no half-triaged or pre-triaged links).

---

## Indexes — each with the query it serves

| Index | Table | Serves |
|---|---|---|
| `idx_captures_inbox (user_id, status, captured_at desc)` | captures | **Inbox list.** Fully index-ordered for a *single*-status predicate — `WHERE user_id=? AND status=? ORDER BY captured_at DESC` (verified: index scan, no sort). For a **multi-status** `status IN (…)` predicate Postgres cannot walk it in `captured_at` order and falls back to a top-N sort (measured ~4 ms at 20 k rows — fine at personal scale). If P4 makes the inbox genuinely multi-status over a large history, switch to a partial index led by `(user_id, captured_at desc)`. Partial `WHERE deleted_at IS NULL`. **[perf debt — see TECH_DEBT.md, bites P4.]** |
| `idx_habit_completions_habit (habit_id, completed_at desc)` | habit_completions | Per-habit history / **Done list** — `WHERE habit_id=? ORDER BY completed_at DESC`. |
| `idx_focus_sessions_user_started (user_id, started_at desc)` | focus_sessions | Session history — `WHERE user_id=? ORDER BY started_at DESC`. |
| `idx_tasks_user_status (user_id, status)` | tasks | Task lists by status — `WHERE user_id=? AND status=?`. |
| `idx_tasks_stale (user_id, last_activity_at) WHERE status='todo'` | tasks | P9 stale/avoidance scan for open tasks by age. |
| `idx_goals_user_status (user_id, status)` | goals | Goal lists by status — `WHERE user_id=? AND status=?`. |
| `idx_tasks_goal (goal_id) WHERE goal_id IS NOT NULL` | tasks | Tasks laddering up to a goal (P9 goal detail) — `WHERE goal_id=?`. |
| `idx_habits_goal (goal_id) WHERE goal_id IS NOT NULL` | habits | Habits laddering up to a goal — `WHERE goal_id=?`. |
| `idx_reminders_place (place_id)` | reminders | Geofence fire + cancel-on-place-delete — `WHERE place_id=?`. |
| `idx_reminders_task (task_id)` | reminders | Reminders for a task (cancel on task complete/delete). |
| `idx_reminders_habit (habit_id)` | reminders | Reminders for a habit. |

All list-serving indexes are partial on `deleted_at IS NULL` because the app never
lists tombstones. `user_id`-leading foreign keys plus these composites cover the
read paths; add more only when a real slow query appears.

---

## Complete CHECK / enum inventory (for the "are enums complete?" review line)

| Column | Allowed values |
|---|---|
| `profiles.persona_response_language` | `en`, `ar-EG` |
| `profiles.theme` | *(unconstrained — themes grow, D8)* default `analog_companion` |
| `captures.llm_type` | `task`, `note`, `habit`, `uncategorized` |
| `captures.status` | `pending`, `processing`, `ready`, `triaged`, `failed`, `discarded` |
| `captures.resulting_type` | `task`, `note`, `habit` |
| `goals.status` | `active`, `achieved`, `paused`, `dropped` |
| `tasks.status` | `todo`, `done`, `archived` |
| `habit_completions.level` | `mini`, `normal`, `mega` |
| `habit_completions.energy_mode` | `low`, `normal`, `charged` |
| `vibe_checks.value` | `1`, `2`, `3` (3-tap) |
| `reminders.reminder_type` | `time`, `geofence` |
| `reminders.geofence_transition` | `enter`, `exit` |
| `reminders.status` | `scheduled`, `fired`, `done`, `cancelled` |
| `focus_sessions.status` | `active`, `completed`, `abandoned` |
| `focus_sessions.blocking_mode` | `soft`, `hard` |
| `block_list.platform` | `android`, `ios` |

Plus structural / domain CHECKs:
- `reminders`: a `time` reminder must have `scheduled_at`; a `geofence` reminder must
  have `place_id` + `geofence_transition`.
- `captures`: `resulting_type`/`resulting_id` null unless `status='triaged'`, and both
  present when `status='triaged'`.
- Non-negative / range domain guards: `focus_sessions.duration_minutes > 0`,
  `focus_sessions.block_attempts >= 0`, `reminders.dwell_seconds >= 0`,
  `places.radius_m > 0`, `places.lat ∈ [-90,90]`, `places.lng ∈ [-180,180]`.

**Inferred (verify against the real spec before locking):** `vibe_checks.value` as
a 1–3 smallint (the plan only says "3-tap"); `tasks.status` set; `captures.status`
set; `focus_sessions.status` set. These are reasonable minimal sets but were not
pinned by an available "Part 6."

---

## Screen-field coverage (Part 5 review line)

Mapped from the build plan's screen descriptions (the real Part 5 was unavailable):

- **Screen 1/2 capture & processing** → `captures` (audio_path, status, captured_at).
- **Screen 3 Inbox** → `captures` (energy-mode selector is app state / `prefs`, not a
  capture column — see open question Q1).
- **Screen 4 habit + burst** → `habits`, `habit_completions` (level, energy_mode).
- **Screen 5 Fresh Start** → `habits.reset_active`, `habits.reset_started_at`.
- **Screen 6 Focus** → `focus_sessions` (+ `captures_during`, `vibe_checks`).
- **Screen 7 Triage** → `captures.llm_type`/`title`/`details`/`suggested_schedule`,
  routing to `tasks`/`notes`/`habits`.
- **Screen 8 Settings** → `profiles` (language, theme, `prefs.capture_trigger`,
  `prefs.energy_time_rules`), `places`, `block_list`.
- **Done list** → `habit_completions` + completed `tasks` (reverse-chron).
- **Goals (P9 Goal Sage)** → `goals` (title, why, status, target_date); `tasks`/`habits`
  ladder up via nullable `goal_id`. Thin by design — see open question Q4.

## Open questions for the reviewer

- **Q1 — energy mode persistence.** The inbox energy selector (Low/Normal/Charged)
  is recorded on `habit_completions.energy_mode` and `focus_sessions` context, but
  the *currently-selected* mode has no home. I treated it as ephemeral app state
  (optionally last-value in `prefs`). Confirm it doesn't need its own persisted
  column. confirmed, it doesnt. 
- **Q2 — reminder ↔ target cardinality.** A reminder may target a task *or* a habit
  *or* neither (freestanding time reminder). I did **not** add an exactly-one
  CHECK, to allow freestanding reminders. Confirm freestanding reminders are wanted;
  if a reminder must always target something, add `CHECK (num_nonnulls(task_id,
  habit_id) = 1)`. confirmed, good choice. 
- **Q3 — `dirty`/`synced_at` placement (R0 above). ✅ RESOLVED (2026-07-11):**
  local-only placement ratified at the P1 gate. No Postgres columns added.
- **Q4 — Goals / Goal Sage. ✅ RESOLVED (2026-07-11):** designed in now, not deferred.
  A **thin `goals` table** is included (`title`, `why`, `status`, optional
  `target_date`), with nullable composite `goal_id` FKs on `tasks`/`habits`
  (**one goal per item**, `SET NULL` on goal delete). Goal Sage's breakdown logic,
  milestones, sub-goals, and progress computation remain deliberately unmodelled —
  a clean future migration once P9 specs them. See §"Goals — thin now, extensible
  later".

---

## Human review checklist (walk this before locking)

- [x] Does every screen in Part 5 have every field it needs a home? *(see coverage
      table; note Part 5 itself was unavailable — verify against the real spec)*
- [x] Is the inbox list query indexable as written? *(single-status: yes; multi-status
      `IN (…)` degrades to a top-N sort — logged as P4 perf debt)*
- [x] Does last-write-wins have a timestamp on every syncable table? *(yes —
      `updated_at` on all 12 tables; push is a conditional upsert, see §Sync)*
- [x] Can a user attach a child to another user's parent? *(no — composite FKs,
      proven by `20_fk_ownership.sql`)*
- [x] Are all enums/CHECKs complete for the features that use them? *(see inventory;
      verify the 4 inferred sets)*
- [x] Is any preference we intend to collect missing a column/blob path? *(language +
      theme = columns; everything else = `prefs`; confirm the rule)*
- [x] Any table that should cascade-delete but doesn't (or vice-versa)? *(see ERD
      ON DELETE table; note capture→typed = SET NULL, task→session = SET NULL,
      goal→task/habit = SET NULL)*
- [x] Ratify R0 (local-only `dirty`/`synced_at`) and resolve Q1–Q4. *(all resolved:
      Q1 ephemeral, Q2 freestanding OK, Q3 local-only, Q4 thin goals table added)*

## Self-verification (agent) — results

- **Migration applies cleanly** to a fresh Postgres 16 — `scripts/test_migration.sh`
  ran green (all `CREATE`s succeeded).
- **RLS blocks cross-user access** — scripted check (`10_rls_isolation.sql`): as user
  A, sees 1 own task, 0 of user B's; a cross-user insert is rejected by `WITH CHECK`;
  both rows remain intact as owner. All assertions passed.
- **Same-user FK ownership** — scripted attack (`20_fk_ownership.sql`): user D CANNOT
  attach a focus_session / reminder / task to user C's task or capture (all rejected
  with `foreign_key_violation`); C's own SET-NULL delete nulls only `task_id` and
  leaves `user_id` intact. All assertions passed.
- **Domain CHECKs** — `20_fk_ownership.sql` also proves negative
  `duration_minutes`/`block_attempts`/`dwell_seconds`, non-positive `radius_m`,
  out-of-range `lat`/`lng`, and both half-triaged capture states are rejected.
- **ERD matches the migration** — every table/relationship in `docs/ERD.md` is drawn
  from `0001_initial_schema.sql` (composite FKs and new CHECKs reflected); no table
  or column appears in one but not the other.
- **Enum/CHECK completeness** — inventoried above against every feature P3–P12;
  4 sets are marked *inferred* because the spec's Part 6 was unavailable.
- **No implementation to regression-test** — this is a design-only phase; no drift,
  repositories, sync, auth, or UI were written (per the review gate).

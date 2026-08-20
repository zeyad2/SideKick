# Sidekick — Behavioural event log (taxonomy & contract)

**Status:** groundwork only. The `public.events` table (migration `0002_events_log.sql`)
is **write-only** today. The read side — insights, behavioural analysis, tips,
energy-over-time — is a **future plan**, deliberately unbuilt. This doc is the contract
the write side must honour so that, whenever insights ships, it has dense, correct history.

## Why it exists (the one-line version)

State tables record *current state*; they can't be backfilled. If we don't log behaviour
*as it happens*, insights launches empty. So we log now, read later. See migration header
and `SCHEMA.md` for the full rationale. This is cross-cutting decision **D9**.

## The contract (MUST)

1. **Append-only & immutable.** Events are `INSERT`ed, never `UPDATE`d. An event is a fact
   that already happened. The only ever mutation is a future reaper setting `deleted_at`.
2. **Fired from repositories, not UI.** Each domain event is emitted from the P2 repository
   mutation that causes it, so every write path is covered uniformly. Feature code does not
   hand-roll event inserts.
3. **Best-effort, never blocking.** Writing an event must never block or fail a user action.
   Local-first like every other write (drift first, sync best-effort).
4. **No-shame at the read side.** When insights is built, it frames patterns as *"the app
   noticed something that might help,"* never a score, streak, or "you failed / avoided X."
   This mirrors the app's core values (no streaks, no guilt).
5. **`event_type` is free-text**, validated against *this doc* (not a DB CHECK), so the
   taxonomy grows without a migration. New types: add them here in the same PR.

## Row shape

| Column | Meaning |
|---|---|
| `event_type` | what happened (see taxonomy) |
| `entity_type` / `entity_id` | optional loose link to the row it concerns (no FK, polymorphic) |
| `metadata` (jsonb) | per-event payload, read whole, never filtered in SQL |
| `occurred_at` | device wall-clock time the event happened |

## Structural events (P2 — emitted by the generic repository layer)

The P2 data layer emits these two generic families itself, from `EventEmitter`
(`emitCreated` / `emitStatusChanged`), for **every** entity — feature phases add
the *semantic* events below. `<entity>` is one of the [`EntityTypes`] slugs
(`task`, `capture`, `note`, `goal`, `habit`, `habit_completion`, `place`,
`focus_session`, `vibe_check`, `reminder`, `block_list`).

| `event_type` | entity | metadata | emitted when |
|---|---|---|---|
| `<entity>_created` | that entity | *(entity-specific breadcrumbs, e.g. `{source}` for capture, `{level, energy_mode}` for habit_completion)* | any repository `create` |
| `<entity>_status_changed` | that entity | `{from, to}` | a `status`-bearing entity's status changes on `update` (task, capture, goal, focus_session, reminder) |

Feature phases may emit a richer, purpose-built event *in addition* (e.g.
`habit_completed`, `capture_triaged`) where more context is needed. The
structural events are the always-on baseline.

## Taxonomy (grow this list; keep it alphabetical within a group)

### Capture / inbox
| `event_type` | entity | metadata | signal it feeds |
|---|---|---|---|
| `capture_created` | capture | `{source:"trigger"\|"fab"}` | capture volume, time-of-day |
| `capture_triaged` | capture | legacy: `{resulting_type, latency_ms}`; decomposition: `{mode:"auto"\|"bulk", item_count, kinds, latency_ms}` | inbox friction / pile-up |
| `capture_auto_commit_undone` | capture | `{item_count}` | auto-commit correction rate |
| `capture_discarded` | capture | `{}` | noise ratio |

### Tasks
| `event_type` | entity | metadata | signal |
|---|---|---|---|
| `task_status_changed` | task | `{from, to}` | completion cadence, dwell time |
| `task_snoozed` | task | `{until}` | procrastination pattern |
| `next_action_generated` | task | `{}` | which tasks need unblocking |
| `avoidance_triaged` | task | `{reason:"too_big"\|"unclear"\|"scary"\|"boring"}` | *kind* of stuck |

### Habits
| `event_type` | entity | metadata | signal |
|---|---|---|---|
| `habit_completed` | habit | `{level, energy_mode}` | elastic behaviour (also in `habit_completions`) |
| `fresh_start_entered` | habit | `{}` | struggle signal (compassionate framing) |

### Energy  *(the gap state tables can't reconstruct)*
| `event_type` | entity | metadata | signal |
|---|---|---|---|
| `energy_mode_changed` | — | `{from, to, auto:bool}` | energy trajectory across the day |

### Focus
| `event_type` | entity | metadata | signal |
|---|---|---|---|
| `session_started` | focus_session | `{planned_minutes, blocking}` | initiation ritual usage |
| `session_ended` | focus_session | `{status, actual_minutes}` | completion vs abandonment |
| `block_attempt` | focus_session | `{app_label}` | which apps pull attention (also counted on the row) |
| `vibe_check` | focus_session | `{value}` | post-session mood |

### Reminders
| `event_type` | entity | metadata | signal |
|---|---|---|---|
| `reminder_fired` | reminder | `{reminder_type}` | reminder reach |
| `reminder_actioned` | reminder | `{action:"done"\|"later"\|"dismiss", latency_ms}` | which reminders work |

> When insights is designed, add read-path indexes in *that* migration (the exact queries
> will be known then) — don't add them speculatively here.

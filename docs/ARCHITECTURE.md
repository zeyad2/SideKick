# Architecture

How Sidekick is put together, and — more importantly — where one component's
assumptions meet another's. Read this before changing anything that crosses a
runtime boundary.

## Dependency direction

```
presentation  →  application  →  domain  ←  data
      ↓               ↓                       ↓
              core (db, sync, auth, events, capture, theme)
                              ↓
        drift (local SQLite)        MethodChannel → Kotlin
                              ↓
                      SupabaseSyncGateway → Postgres
```

Rules that hold everywhere:

- `domain` depends on nothing but `core/domain/enums.dart` and `meta`. It holds
  immutable models plus the **repository interfaces**.
- `data` implements those interfaces against drift. It is the only place that
  names a drift table or a companion.
- `application` orchestrates: it takes repository interfaces and platform
  interfaces, never a concrete implementation. That is what makes it testable
  with `test/support/fakes.dart`.
- `presentation` reads providers and calls `application`. It must not contain a
  scheduling, drafting, or persistence decision.
- Wiring lives in providers (`lib/core/providers/`,
  `lib/features/*/application/*_providers.dart`), never in widgets.

## Layer by layer

### Local-first store (`lib/core/db/`)

Drift over SQLite is the source of truth for the running app. Every syncable
table carries the `SyncColumns` mixin: `created_at`, `updated_at`, `deleted_at`,
`dirty`, `synced_at`. `dirty` and `synced_at` are **local-only** and are stripped
before push; `supabase/tests/30_sync_guards.sql` asserts they never reach the
cloud schema.

Deletes are soft (`deleted_at`), so every read filters `deletedAt.isNull()`. That
has a consequence people forget: a soft-deleted row still exists and still syncs,
but disappears from `watchAll()`. Anything holding its id — a registered
geofence, a reminder's `place_id` — must be reconciled explicitly.

`AppDatabase.wipeAllData()` clears every table including `sync_meta`, because the
database is shared across accounts on one device. It runs on sign-out.

### Sync (`lib/core/sync/`)

`DriftSyncEngine` is generic over `kSyncableTables` and uses raw SQL, so there is
no per-table mapping to maintain — adding a table to that list is the whole
integration. Per cycle:

1. **flush** — select `dirty = 1 AND <owner> = :userId`, strip local-only
   columns, JSON-decode the JSONB columns, push, then clear `dirty` only for rows
   whose `(id, updated_at)` still matches what was sent. A local edit that lands
   during an in-flight push therefore stays dirty and retries, instead of being
   marked clean with an unsent payload.
2. **pull** — per-table cursor in `sync_meta`, queried with a 1 ms overlap so rows
   sharing the cursor timestamp are not missed, then LWW-applied.

Conflict resolution is last-write-wins on `updated_at`, arbitrated server-side by
the `sync_lww_guard` trigger (rejects a stale update, clamps a future timestamp).
On a tie the server row wins.

`events` and `reminder_events` are `insertOnly`: pushed with
`ON CONFLICT DO NOTHING`, because rows are immutable and client-id'd, so a retry
after a committed-but-unacknowledged push is a no-op.

**Failure model to keep in mind:** push is one batch per table, and errors are
caught per table and only `debugPrint`ed. One rejected row blocks that table
forever, and the FK chain `captures → task_reminders → reminder_events` means one
bad capture can silently stop three tables.

### Auth and the root gate (`lib/core/auth/`, `lib/core/router/app_gate.dart`)

Session state is read **synchronously** from the cached Supabase session so the
app opens offline with no spinner. `appGateProvider` collapses auth + profile +
first-sync into one of `loading | login | onboarding | ready`, and the router has
exactly one redirect that switches on it.

The subtle case it exists for: sign-out wipes the local DB, so a returning user
on a fresh install has no local profile row. Routing straight to onboarding would
write a fresh-timestamped profile that LWW then pushes over their real synced
preferences. So absence of a profile holds on `loading` until the first sync
cycle settles.

### Events (`lib/core/events/`)

Two separate logs; do not confuse them.

- `events` — generic structural/behavioural log, written fire-and-forget by
  `EventEmitter` from inside repositories. Emission can never fail a mutation.
- `reminder_events` — the correction loop's domain log (`created`, `activated`,
  `fired`, `done`, `later`, `dismissed`, `wrong_place`, `edited`). This one is
  read back: `AssistantContextBuilder` feeds recent actions to the AI.

Both are append-only in code and in RLS.

## The reminder loop, end to end

### Creation

```
InboxScreen (typed text, or audio capture from the hardware shortcut)
  → ReminderCreationService.submitText / processAudioCapture
      → CapturesRepository.create            (durable input record written first)
      → AssistantContextBuilder.build()      (bounded, redacted life context)
      → ReminderDraftService.parseText/parseAudio
            GeminiReminderDraftService     (when GEMINI_API_KEY is set)
            HeuristicReminderDraftService  (fallback, and the offline path)
      → _saveParsed: per draft, confidence ≥ 0.75 AND a concrete trigger
            → status pending_auto_commit, auto_commit_deadline_at = now + 10s
            → otherwise it goes to review, persisted against the capture
      → ReminderSchedulerService.schedule() once activated
```

Idempotency is `(user_id, capture_id, draft_id)` — unique in drift and in
Postgres (`task_reminders_capture_draft_uidx`). `draft_id` is a stable FNV hash
of the draft's identifying fields plus its index, so re-parsing the same capture
does not duplicate reminders.

### Scheduling

`ReminderSchedulerService` is platform-agnostic; `AndroidReminderSchedulePlatform`
is a thin MethodChannel adapter onto `ReminderRuntimeBridge` (Kotlin).

- **time** → `AlarmManager.setExactAndAllowWhileIdle`, falling back to
  `setAndAllowWhileIdle` when exact alarms are not permitted.
- **place** → `LocationManager.addProximityAlert` (a documented POC shortcut over
  Play Services geofencing — see `TECH_DEBT.md`), with dwell implemented as a
  follow-up alarm rather than a native dwell transition.

Both registrations are mirrored into SharedPreferences so `ReminderBootReceiver`
can restore them after reboot or app update.

### Firing and the action journal

This is the part that must survive the Flutter process being dead:

```
AlarmManager / proximity alert
  → ReminderGeofenceReceiver (Kotlin)
      time  → ReminderAlarmActivity   (full-screen, native, works over lockscreen)
      place → notification with Done / Later / Dismiss / Wrong place
  → user acts
  → ReminderRuntimeBridge.enqueueNativeAction → SharedPreferences journal
  ... later, whenever Flutter is alive ...
  → app resume → ReminderScheduler.resyncAll()
      → drainNativeActions → handleAction → repo update + reminder_event
      → ackNativeAction (removes it from the journal)
```

The journal is the durability mechanism. Nothing about a user's Done/Later/
Dismiss depends on Flutter running. `handleAction` is idempotent: it skips an
action whose id already exists as a `reminder_event`, then acks it.

### Correction

`wrong_place` records the event and asks `ReminderEditDispatcher` to open the
edit flow when a screen is available. `AssistantContextBuilder` then feeds recent
actions — including wrong-place corrections — back into the next drafting call,
which is how the loop is meant to learn.

## Cross-cutting invariants

- **A reminder row and the native registry must agree.** Any write that changes
  `status`, `trigger_type`, `scheduled_at`, `place_id`, or `geofence_transition`
  must be followed by `schedule()` if it should be live, or `cancel()` if it
  should not. `schedule()` returning early because a trigger cannot be resolved
  is *not* the same as cancelling.
- **Notification and request-code integers are allocated, not hashed.**
  `ReminderRuntimeBridge.managedIntId` mints and persists them so a PendingIntent
  can be looked up again later. Never derive one from `id.hashCode`.
- **Timestamps are UTC in storage**, converted to local only at the presentation
  edge. Wall-clock *parsing* ("tomorrow at 9") needs the user's IANA zone, which
  must be passed explicitly — `DateTime.now()` in a service or a prompt string
  saying "current UTC time" will not give it to you.
- **The AI may improve a user-requested reminder; it may never create one from
  context alone.** Enforced in the prompt and again in `validateDraftJson`, which
  rejects any `place_id` or `context_items_used` entry that was not supplied in
  the context payload.

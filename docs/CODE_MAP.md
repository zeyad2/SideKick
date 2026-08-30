# Code map — what lives where, and what to add where

For each area: what it contains, what belongs there, and what must never go
there. When a change does not obviously fit one of these, that is a signal the
change is in the wrong layer, not that the map needs an exception.

---

## `lib/main.dart`, `lib/app.dart`

Process bootstrap and the app-lifecycle wiring: Supabase init, `ProviderScope`,
`MaterialApp.router`, and the resume hook that flushes sync and re-attaches the
reminder scheduler.

**Add here:** a new app-lifecycle side effect that genuinely has no owner
elsewhere (and give it a provider, not inline logic).
**Never here:** feature logic, navigation decisions (they belong to
`appGateProvider`), or anything that can block the first frame. `main()` must not
await a network call.

---

## `lib/core/db/`

`tables.dart` is the drift schema; `app_database.dart` holds the database, the
schema version, the migration strategy, and `wipeAllData()`. `json_codec.dart` is
the encode/decode boundary for the JSONB-as-TEXT columns.

**Adding a column or table — the full checklist:**

1. Add it to `lib/core/db/tables.dart`.
2. Bump `schemaVersion` and add the `onUpgrade` branch in `app_database.dart`.
3. Regenerate: `dart run build_runner build --delete-conflicting-outputs`.
4. Add the matching Postgres migration in `supabase/migrations/` with the same
   snake_case name and a **compatible type** (see `RUNTIME_CONTRACTS.md`).
5. If the table is new and syncable, register it in `kSyncableTables`.
6. If it holds JSON, add the column name to `DriftSyncEngine._jsonColumns`.
7. Update `test/schema/column_parity_test.dart`.

**Never here:** CHECK constraints (the enums own value validation), business
defaults that belong in a repository, or a column repurposed to carry state that
does not match its name.

---

## `lib/core/sync/`

The generic engine, the `SyncGateway` network boundary, the connectivity service,
and `kSyncableTables`.

**Add here:** a new syncable table (one line), a genuinely generic sync concern
(retry policy, per-row error isolation, a dead-letter path).
**Never here:** per-table special cases. The engine is generic on purpose; the
moment it grows an `if (table == 'x')` the design is gone. If a table needs
different semantics, express it as a flag on `SyncableTable` the way `insertOnly`
does.

---

## `lib/core/auth/`, `lib/core/router/`

`AuthRepository` is the only thing that touches `GoTrueClient`. `app_gate.dart`
is the **single** source of truth for the root redirect; `app_router.dart`
switches on it and does nothing else clever.

**Add here:** a new top-level route (add to `app_routes.dart` first, then the
router, then the gate's allow-list if it should be reachable while not `ready`).
**Never here:** a second redirect rule, or a widget that decides where the user
should be. If a screen needs to gate itself, the gate is wrong.

---

## `lib/core/events/`

`EventEmitter` (fire-and-forget, swallows all errors) and `EventsRepository`
(append-only, write-only plus a test-only read).

**Add here:** a new structural event type on the generic layer.
**Never here:** a read/query/analytics API. The read side is a future plan, and
adding one now creates a product dependency on an append-only log that RLS will
not let you correct.

---

## `lib/core/capture/`

The native audio bridge: `NativeCaptureApi` (MethodChannel),
`CaptureCoordinator` (overlay state machine + de-duplication),
`CaptureIngestionService` (the only path from native capture into the data
layer), and `CaptureIngestionBarrier` (holds writes off during the sign-out
wipe).

**Add here:** anything about getting recorded audio safely into a `captures` row.
**Never here:** drafting, AI, or reminder logic. Ingestion stops at a durable
`captures` row; what happens to it afterwards belongs to
`features/reminders/application/`.

---

## `lib/core/theme/`

`AppTheme` + tokens (`app_tokens.dart`, `app_colors.dart`), the concrete
`analog_companion_theme.dart`, the registry, and shared widgets
(`PersonaOrb`, `PillButton`, `SurfaceCard`).

**Add here:** a shared visual primitive used by two or more features; a new token.
**Never here:** a raw `Color(0x...)` or a magic padding number in a feature
widget — read it from `context.appTheme`. Note that
`ReminderAlarmActivity.kt` duplicates this palette in Kotlin; if you change the
brand colours, change both.

---

## `lib/features/<feature>/domain/`

Immutable models (`@immutable`, `const` constructor, `copyWith`) and the
repository **interfaces**.

**Add here:** a field on a model (and then to `copyWith`, the data mapper, the
drift table, and Postgres — all five), or a new repository method signature.
**Never here:** drift types, Supabase types, `BuildContext`, or any I/O.

---

## `lib/features/<feature>/data/`

Repository implementations extending `LocalFirstRepository`. These own the drift
SQL and the row↔model mapping.

**Add here:** a query or a mutation.
**Every mutation must:** set `updatedAt = now()`, set `dirty = true`, scope by
`userId`, filter `deletedAt.isNull()` on reads, and soft-delete rather than
delete. Creations emit through `EventEmitter` (never awaited).
**Never here:** a product decision, a scheduling call, or a network call.

---

## `lib/features/<feature>/application/`

Where the actual product logic lives, and the largest files in the repo.

- `reminder_creation_service.dart` — capture → draft → auto-commit/review →
  approve/edit/cancel/re-enable. The state machine of the product.
- `reminder_draft_service.dart` — the AI boundary: the Gemini transport, the
  strict response validator, and the heuristic fallback used offline and in
  tests.
- `reminder_scheduler.dart` — platform-agnostic scheduling, the notification
  action handler, and the static dispatchers that bridge background callbacks
  into a live scheduler.
- `android_reminder_schedule_platform.dart` — the MethodChannel adapter. Thin by
  design.
- `assistant_context_builder.dart` — builds the bounded, redacted AI context.

**Add here:** a decision, an orchestration, a policy. Take dependencies as
interfaces so the fakes in `test/support/fakes.dart` can stand in.
**Never here:** widgets, `BuildContext`, direct drift access, or a `MethodChannel`
outside the `*_platform.dart` adapter.

**Two rules specific to this directory:**

- Anything that changes a reminder's identity or trigger must reconcile the
  native schedule in the same operation (`schedule()` or `cancel()`).
- Anything that adds a field to `TaskReminder` must be added to **every**
  hand-rolled reconstruction in `reminder_creation_service.dart` and
  `reminder_scheduler.dart`. There are currently six. See
  `CONVENTIONS.md` for the `copyWith` fix that removes them.

---

## `lib/features/<feature>/presentation/`

Screens and screen-local widgets. `reminder_formatters.dart` holds the shared
date/time/trigger label formatting — use it rather than formatting inline.

**Add here:** UI.
**Never here:** a `Timer` that drives domain state. The countdown timer in
`inbox_screen.dart` repaints only; activation belongs to the scheduler. Also no
DB query, or an `await` on a repository without error handling that reaches the
user.

---

## `android/app/src/main/kotlin/com/sidekick/sidekick/`

Everything that must work while Flutter is dead.

- `MainActivity.kt` — Flutter host; registers both MethodChannels.
- `ReminderRuntimeBridge.kt` — the reminder MethodChannel handler plus the
  durable stores: geofence records, time-reminder records, the native action
  journal, dwell state, and the allocated-integer-id table.
- `ReminderGeofenceReceiver.kt` — receives alarms, proximity alerts, dwell
  alarms, and notification action button taps.
- `ReminderAlarmActivity.kt` — the full-screen time-reminder alarm UI, written in
  Kotlin views so it can show over the lock screen without booting Flutter.
- `ReminderBootReceiver.kt` — restores registrations after reboot / update.
- `CaptureForegroundService.kt`, `NativeCaptureStore.kt`,
  `SidekickAccessibilityService.kt`, `CaptureRuntimeGuard.kt`,
  `CaptureAudioValidator.kt` — the audio capture shortcut.

**Add here:** anything the OS must be able to trigger without the app running.
**Never here:** business rules. Native code records facts (an action happened, an
alarm fired) into the journal; Dart decides what they mean. The one deliberate
exception is dwell filtering, which must run in the receiver.

**When you add a native action:** persist to the journal **first**, and only act
on the UI/notification if the persist succeeded. An action that is executed but
not journalled is a reminder that silently disappears.

---

## `supabase/`

`migrations/` is the cloud schema (types, FKs, CHECKs, RLS, LWW trigger).
`tests/` are pgTAP suites for RLS isolation, same-user FK ownership, and the sync
guards.

**Add here:** a migration for every drift schema change, and a pgTAP assertion
for any new policy or constraint you rely on.
**Never here:** the local-only `dirty` / `synced_at` columns — a test asserts
their absence.

---

## `docs/`

- `POC_SPEC.md` — scope. The arbiter of "should this exist at all".
- `POC_PHASES.md` — the phase plan and the required report format.
- `FUTURE_PLANS.md` — the parking lot. Deferred requests go here, not into `lib/`.
- `ARCHITECTURE.md`, `CODE_MAP.md`, `CONVENTIONS.md`, `RUNTIME_CONTRACTS.md`,
  `TESTING.md` — this documentation set.
- `reports/` — phase reports and review reports. Append, never rewrite history.
- `archive/legacy-companion-v1/` — the pre-reset app. Useful as reference for
  intent; **not** a source of current truth. Do not resurrect code from it.

`TECH_DEBT.md` at the repo root is the live debt ledger: what, risk, trigger to
fix, cost if deferred. Adding an entry is how you are allowed to leave debt.

# Conventions

Rules that keep this codebase from biting later. Most of them exist because the
opposite already caused a real defect — where that is true, the defect is named.

## Dart style

Enforced by `analysis_options.yaml` (`flutter_lints` plus
`always_declare_return_types`, `avoid_dynamic_calls`, `prefer_final_locals`,
`prefer_single_quotes`, `sort_constructors_first`, `unawaited_futures`,
`directives_ordering`). `dart analyze` must be clean; it currently is.

Beyond the linter:

- **Explicit types on locals and collection literals.** This codebase writes
  `final List<TaskReminder> rows = ...` and `<String, Object?>{}`, not `var`.
  Match it.
- **Named parameters for anything with more than two arguments**, and `required`
  rather than a nullable with a runtime check.
- **`@immutable` + `const` constructor** on every domain model and value object.
- **Comments are rare and short.** Global preference: at most one line, only when
  the code cannot say it. The existing long doc comments on `SyncEngine`,
  `AppGate`, and `EventEmitter` are deliberate — they document a contract, not a
  mechanism. Do not add narration.

## `copyWith` must be able to clear a field

`x ?? this.x` cannot express "set this to null". `TaskReminder.copyWith` has this
shape, which is why `reminder_creation_service.dart` and
`reminder_scheduler.dart` contain **six** hand-written full-constructor
reconstructions instead. Every new field must then be added in six places, and
missing one silently drops data on edit.

Use the pattern `Capture.copyWith` already uses:

```dart
TaskReminder copyWith({
  DateTime? scheduledAt,
  bool clearScheduledAt = false,
  // ...
}) => TaskReminder(
  scheduledAt: clearScheduledAt ? null : (scheduledAt ?? this.scheduledAt),
  // ...
);
```

Then delete the hand-rolled reconstructions. New models: get this right from the
start.

## Ids

- Client-generated UUIDv4 via `IdGenerator`, always.
- **Never** invent an id format. Postgres declares every `id` and `*_id` column
  as `uuid`; a non-UUID string passes drift's TEXT column silently and then fails
  the push forever, taking the whole table's sync with it. This has already
  happened once — the native action-journal id
  (`"<reminderId>:<action>:<seq>"`) is stored as a `reminder_events` primary key.
- Correlation identifiers from another runtime belong in a `metadata` JSON field,
  not in a primary key.

## Enums and wire values

`lib/core/domain/enums.dart` is the single inventory of allowed values. Each enum
exposes `wire` (the exact string stored in drift and Postgres) and a `fromWire`
that falls back rather than throwing, so a newer server value never crashes an
older client.

Changing a value set means changing three things together: the Dart enum, the
Postgres CHECK constraint, and any pgTAP/Dart test that asserts the inventory.

## Time

- **Store UTC.** `LocalFirstRepository.now()` returns `DateTime.now().toUtc()`.
- **Convert at the presentation edge only** (`reminder_formatters.dart`, the
  pickers).
- **Wall-clock parsing needs an explicit IANA zone.** "tomorrow at 9" is
  meaningless without one. `ReminderDraftContext.timeZoneName` exists for this;
  it is currently always `'UTC'` in production because nothing writes
  `profile.prefs['timezone']`, and the Gemini prompt does not carry it at all.
  Any new parsing path must take the zone as an argument — never read the
  ambient device zone inside a service, and never send a model only "current UTC
  time".
- Absolute scheduling (`scheduledAt.toUtc().millisecondsSinceEpoch` →
  `AlarmManager`) is correct as-is. Do not "fix" it by shifting offsets.

## Local-first writes

Every repository mutation:

```
write drift → set updated_at = now(), dirty = true → return immediately
```

- Scope by `userId` in the `where`, on reads and writes both. The DB is shared
  across accounts on a device.
- Filter `deletedAt.isNull()` on reads.
- Soft-delete; never `delete(...).go()` outside `wipeAllData()`.
- Emit domain events fire-and-forget. Never `await` `EventEmitter`; never let an
  event write fail a user mutation.
- Never `await` a network call inside a repository method.

## Reminder mutations reconcile the schedule

Any write that changes `status`, `trigger_type`, `scheduled_at`, `place_id`, or
`geofence_transition` must, in the same operation, either `schedule()` the
reminder or `cancel()` it. Two specific traps:

- `schedule()` returns early when it cannot resolve a trigger (missing place,
  null `scheduledAt`). That leaves any previous registration **live**. If the new
  state is not schedulable, call `cancel()` explicitly.
- Converting a place reminder to a time reminder (snooze, reschedule) does not
  remove the geofence. Cancel first, then schedule.

## Reads

Prefer a one-shot repository read over `watchX().first`. The latter builds and
tears down a drift query stream to answer a single question, and it is used that
way in ~8 places today (`_findReminder`, `_placeFor`, `_saveParsed`,
`AssistantContextBuilder.build`). When you add a lookup, add a `getById` /
`getAll` to the repository interface instead of reaching for the stream.

Streams belong in providers feeding UI, not inside services.

## Riverpod

- Providers are the composition root. No `new`-ing a repository or service inside
  a widget.
- User-scoped providers read `requireUserIdProvider`, which throws when signed
  out — so they must only be read from signed-in surfaces.
- `ref.onDispose` anything with a subscription, timer, or native handle.
- A provider body must not have a side effect that is not cleaned up. If you must
  kick off work, `unawaited(...)` it and register the teardown.

## Widgets

- Read design values from `context.appTheme`. No literal colours, no magic
  spacing.
- No domain logic, no `Timer.periodic` that drives persistence, no direct drift
  access.
- Every user-facing async action needs a visible failure path. A bare
  `onPressed: () => service.doThing(id)` swallows the error into an unhandled
  async exception and shows the user nothing.
- Do not trigger dialogs or state mutation from `build()`. If you need a
  post-frame effect, gate it and make it idempotent.

## The AI boundary

- The model may **improve** a reminder the user explicitly asked for. It may
  never **create** one from context alone. Both the prompt and
  `validateDraftJson` enforce this; keep both.
- Every AI response field is validated before it becomes a row: `kind` must be
  `task_reminder`, `confidence` finite in [0,1], `scheduled_at` must carry a
  timezone qualifier, and any `place_id` or `context_items_used` entry must have
  appeared in the supplied context. Do not relax these to make a prompt work.
- Context is bounded (12 KB, with a documented shed order) and redacted through
  explicit allow-lists (`allowedExternalProfilePrefs`,
  `allowedExternalReminderEventMetadata`). **Anything you add to the context
  payload must pass an allow-list, not a deny-list.**
- The heuristic service is not a toy: it is the offline path and the path used by
  every test. Keep it behaviourally consistent with the prompt contract.

## Native (Kotlin)

- **Journal first, act second.** Persist the action to the SharedPreferences
  journal, verify it committed, and only then cancel the alarm / update the
  notification. `ReminderGeofenceReceiver` does this correctly;
  `ReminderAlarmActivity.finishWithAction` does it backwards.
- **Durability must be uniform.** The journal and the id allocator use
  `commitChecked` (synchronous `commit()`, throws on failure). Geofence records,
  time-reminder records, and dwell state use `.apply()` and skip the lock. Reboot
  restoration depends on those, so they deserve the same treatment.
- All read-modify-write access to the shared prefs JSON goes inside
  `synchronized(prefsLock)`.
- PendingIntent request codes and notification ids come from
  `managedRequestCode` / `managedNotificationId`. Never hash a string.
- New MethodChannel methods must be added to `RUNTIME_CONTRACTS.md` and covered
  by a Robolectric test.

## Scope discipline

- If a request is outside `docs/POC_SPEC.md`, it goes in `docs/FUTURE_PLANS.md`.
  Do not "just add" a screen, a table, or a nav destination.
- If you must leave debt, add an entry to `TECH_DEBT.md` with what, risk, trigger
  to fix, and cost if deferred. Silent debt is the failure mode this project has
  explicitly organised against.
- Delete dead code rather than leaving it as "documentation of intent". There is
  already a set of unreferenced symbols (`EnergyModeService`, `ParticleBurst`,
  `ThemedEmptyScreen`, `personaLanguageProvider`, `pendingAudioQueueProvider`)
  and a dead Dart dwell implementation that shadows the real Kotlin one — that
  last one is actively dangerous, because its tests pass while proving nothing.

## Git

- Branch off `main`; commit or push only when asked.
- No AI/Claude authorship attribution in commit messages or PR bodies — no
  `Co-Authored-By`, no "Generated with", no equivalent.

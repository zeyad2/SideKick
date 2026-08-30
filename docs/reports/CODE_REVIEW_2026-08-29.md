# Code review — 2026-08-29

Full-repository review at the pause point after the reminder runtime and dogfood
phases. Branch `feature/poc-reset-phases-0-1`, working tree dirty.

**Baseline reproduced, not assumed:** `dart analyze` → *No issues found*.
`flutter test` → **119 passing**. Both were run for this review.

Scope: `lib/` (~7.5k lines), `android/app/src/main/kotlin/` (~1.9k),
`supabase/migrations/`, `test/`. The emphasis is on how components behave
*together*, because that is where every serious finding turned out to live. Each
finding names the file and line, the concrete failure, and a fix.

## Verdict

The architecture is genuinely good for a POC: local-first is honest, the sync
engine is generic rather than per-table, RLS and the composite FKs are real, the
AI response validator is strict, and the native action journal is the right
durability answer. Layering is consistent enough that a new agent can find things.

But **most defects sit at the seams**, and the tests are all inside the boxes.
Four findings are load-bearing enough that the "reminders work" conclusion is
narrower than it looks: it holds for manually-picked times on a device whose zone
is UTC, when the app stays foregrounded through the countdown, and while nobody
looks at the sync log.

Counts: **4 critical, 6 high, 8 medium**, plus a quality list.

---

# Critical

## C1 — Every AI/heuristic-parsed reminder time is computed in UTC, not the user's zone

`reminder_creation_service.dart:877` reads the zone from
`profile.prefs['timezone']`, and **nothing in `lib/` ever writes that key** — a
repo-wide grep finds it only in `assistant_context_builder.dart:18` (the
allow-list) and in tests. So `_timeZoneName()` always returns `'UTC'` in
production, and `reminder_draft_service.dart:329` resolves that to `tz.UTC`.

Consequences:

- **Heuristic path:** "remind me tomorrow at 9" → `TZDateTime(UTC, …, 9)`. For a
  user at UTC+3 that reminder fires at **12:00 local**. `tonight` → 20:00 UTC =
  23:00 local. `today` at least is relative (`now + 2h`) and survives.
- **Gemini path:** worse, because the zone is not even plumbed. `_prompt()`
  states only `Current UTC time: …` and asks for "UTC ISO-8601". The model has no
  way to know the user's wall clock, so its `scheduled_at` is a guess. The
  validator will happily accept it — it only checks that a timezone qualifier is
  present.

Manual reminders are unaffected: the pickers build a local `DateTime` and call
`.toUtc()`. That is almost certainly why dogfood has not surfaced this — the
tested path is the one that works. The nine timezone tests in
`reminder_creation_service_test.dart:804-870` all pass because they inject
`timeZoneName` directly, which production never does.

**Fix:** resolve the device IANA zone once at sign-in/onboarding and
`mergePrefs({'timezone': …})`; pass `timeZoneName` and a local-now string into
`_prompt()` and instruct the model to resolve wall-clock references in that zone;
add a test that goes through `submitText` with no `timezone` pref and asserts it
does not silently mean UTC.

## C2 — Native action ids permanently break `reminder_events` sync

`ReminderRuntimeBridge.enqueueNativeAction` (`ReminderRuntimeBridge.kt:349`)
mints `actionId = "$reminderId:$action:$seq"`. That value reaches Dart as
`metadata['native_action_id']`, and `reminder_scheduler.dart:307,334,365,377,394,404`
passes it as `id:` to `events.append`, which writes it as the **primary key** of
the `reminder_events` row (`reminder_events_repository_impl.dart:26`).

Drift's column is `text()` so it stores fine. Postgres declares
`reminder_events.id uuid` (`0001_poc_baseline.sql`). On the next flush the push
fails with `invalid input syntax for type uuid`. And because `_flushTable`
(`sync_engine.dart:170`) pushes **the whole table in one batch** and errors are
caught per table and only `debugPrint`ed (`sync_engine.dart:409`), the row stays
`dirty` and re-poisons every subsequent flush.

Net effect: **after the user's first notification action taken while the app was
killed, `reminder_events` stops syncing for that account, forever, silently.**
That is the correction-loop signal — the thing the POC exists to collect.

The intent is right: the id is used at `reminder_scheduler.dart:292` to make
replayed native actions idempotent. It just picked the wrong column.

**Fix:** append with a real UUID, store the journal key in
`metadata['native_action_id']` (it is already there), and change the dedup lookup
from `events.findById(nativeActionId)` to a metadata query. Add a test that
asserts every appended `reminder_events.id` parses as a UUID.

## C3 — Auto-commit only advances while the Capture tab is mounted

`ReminderCreationService.activateDueAutoCommits()` has exactly one production
caller: a `Timer.periodic(1s)` in `_InboxScreenState.initState`
(`inbox_screen.dart:47`).

So a reminder created with a 10-second countdown that is backgrounded, killed, or
left for another tab within that window stays `pending_auto_commit` **with no
alarm and no geofence registered** until the user reopens Capture. Nothing on
resume, nothing in `resyncAll()`, nothing at startup activates it —
`resyncAll()` only queries `TaskReminderStatus.active`.

The same timer also runs a DB query and a full `setState()` on an 886-line widget
tree **every second**, indefinitely, and drops the returned `Future` so any error
becomes an unhandled async exception.

**Fix:** activation belongs in the scheduler or an app-lifecycle service — call
it on resume and at the start of `resyncAll()`. Better still, schedule the
activation itself as an alarm at `auto_commit_deadline_at` so it does not depend
on Flutter running at all. Leave the UI timer responsible only for the visible
countdown, and drive it from the widget's own tick, not from a domain call.

## C4 — Raw user speech leaks into the Gemini prompt through `captures.error`

Two independently reasonable decisions combine into a privacy break.

1. `ReminderCreationService` overloads the `captures.error` column as a state
   blob: `sidekick_state:{"review_drafts":[…],"source":…,"audio_attempts":…,"message":…}`
   (`_encodeCaptureState`, ~line 918). Each review draft serializes with
   `details`, which `_draftFromText` sets to the **verbatim input**.
2. `AssistantContextBuilder._capture` (`assistant_context_builder.dart:240`)
   forwards `'error': capture.error` **unfiltered** into the AI context.

And they always meet: `_isUnclearCapture` (line 190) selects captures whose error
contains `"unclear"` — which is exactly what the blob's own message says
("Audio was unclear. Try recording again."). So every unclear capture ships its
full serialized drafts, including raw transcribed speech, to Google.

This contradicts `TECH_DEBT.md` §Phase 4 ("bounded redacted context") and
`POC_SPEC.md`'s AI-context boundary. Every other field in the builder goes
through a scalar allow-list; this one bypasses it because the payload arrived
inside a field named `error`.

**Fix:** stop overloading the column. Add `captures.metadata jsonb` (or a
`capture_drafts` table) for review state, keep `error` for error text, and
redact/drop it in `_capture` regardless. Add a test asserting the encoded context
contains no `sidekick_state:` prefix and no draft `details`.

---

# High

## H1 — Deleting a place orphans its geofence and silently disables its reminders

`PlacesRepositoryImpl.delete` (line 86) is a soft delete, and `watchAll()` (line
18) filters `deletedAt.isNull()`. `ReminderSchedulerService._placeFor`
(`reminder_scheduler.dart:438`) resolves places through `watchAll()`, so after a
delete it returns `null` and `schedule()` **returns without scheduling or
cancelling** (line 241).

Three failures at once:

- The already-registered `addProximityAlert` is never removed, so the reminder
  keeps firing at a place the user deleted.
- `ReminderBootReceiver` re-registers it from the SharedPreferences record after
  every reboot.
- The Reminders screen still shows the reminder as ACTIVE, and `resyncAll()`
  silently skips it every time.

Server-side, `on delete set null (place_id)` never fires either, because a soft
delete is an UPDATE.

**Fix:** on place delete, cancel and mark every reminder referencing it (a
`place_deleted` correction is the honest UX). Separately, make `schedule()`
`cancel()` when it cannot resolve a trigger rather than returning — an
unschedulable reminder must not leave a stale registration live.

## H2 — Snoozing a place reminder leaves the geofence armed

`handleAction`'s `later` (line 311) and `reschedule` (line 337) branches rebuild
the reminder as `triggerType: time` and drop `placeId`, `geofenceTransition`, and
`dwellSeconds` — then call `schedule(snoozed)`, which only calls `scheduleTime`.
`cancel(id)` is never invoked, so the proximity alert stays registered.

Result: the user snoozes a place reminder for two hours and still gets the place
notification the next time they walk past. Worse, the reminder row no longer has
a `place_id`, so nothing can clean it up afterwards — the alert is orphaned
permanently.

**Fix:** `await cancel(reminder.id)` before scheduling the converted reminder,
and preserve the original place fields (a snooze should not silently destroy the
trigger the user configured).

## H3 — "Wrong place" correction cannot correct the place

`handleAction(wrongPlace)` (line 381) records the event with
`'edit_route': '/capture?editReminderId=…'` and calls
`ReminderEditDispatcher.request`. That opens `_EditAutoCommitDialog`
(`inbox_screen.dart:806+`), which contains exactly two fields: **Title** and
**Details** (lines 848, 855). `_maybeOpenLinkedEdit` then calls `editReminder`
with title and details only.

So the correction loop's most important signal leads to a dialog that cannot
change the place, the transition, the dwell, or the time. The reminder stays
registered on the wrong geofence, and the user's only escape is to cancel it and
start over. The event is recorded and does feed back into future drafting
(`_hasWrongPlaceFeedback`), so the *learning* half works — the *fixing* half does
not.

**Fix:** either give the wrong-place path a real trigger editor (place picker +
transition + radius), or route it to the reminder's edit surface rather than the
auto-commit dialog.

## H4 — Nothing reads the notification-tap intent extras

`ReminderGeofenceReceiver.kt:84` attaches a `reminder_payload` extra to the
launch intent, and line 36 attaches `EXTRA_EDIT_REMINDER_ID` for wrong-place.
A repo-wide grep shows **no reader on either side** — no `onNewIntent`, no
`getIntent()` handling in `MainActivity`, no Dart consumer.

So tapping a place notification opens the app and does nothing: no `fired`/`open`
`reminder_event`, no navigation, no dismissal of the source. The
`ReminderNotificationAction.open` branch (line 398) is unreachable from a tap.

Related dead layer: `AndroidReminderSchedulePlatform._ensureInitialized`
(line 173) initializes `flutter_local_notifications` with both foreground and
`@pragma('vm:entry-point')` background response handlers and a full Darwin
category — but **notifications are posted natively**, never through that plugin.
The manifest still registers its two receivers. Two notification stacks, one of
them entirely unreachable, and `poc_cleanup_test.dart:139` guards the wrong one.

**Fix:** handle the launch intent in `MainActivity.onNewIntent`/`onCreate` and
forward it over the channel, or drop the extras and the plugin initialization.
Either is fine; carrying both is what will mislead the next agent.

## H5 — Dead Dart dwell logic shadows the real Kotlin implementation

`ReminderSchedulerService.handleGeofenceTrigger` and `_pendingDwellStarts`
(`reminder_scheduler.dart:225,413-436`) are called **only from
`reminder_scheduler_test.dart:202,209`**. Production dwell is
`ReminderRuntimeBridge.recordDwellTransition` / `isDwellReady` /
`cancelDwellAlarm`, driven by `ReminderGeofenceReceiver`.

The two implementations disagree: Dart holds dwell start times in an in-memory
map (lost on every process death) and advances only on a *second* proximity
event; Kotlin persists to SharedPreferences and schedules an explicit
`ACTION_DWELL_ELAPSED` alarm. The Dart version also appends a `fired` event; the
Kotlin path does not.

This is the most expensive kind of dead code: it has passing tests, so it reads
as verified behaviour, and the next agent asked to "fix dwell" will fix the copy
that does nothing.

**Fix:** delete the Dart implementation and its tests, and write the dwell tests
against `ReminderRuntimeBridge` in Robolectric — or make Kotlin delegate to Dart
and keep one. Do not keep two.

## H6 — Sign-out can leave the previous account's data on the device

`SupabaseAuthRepository.signOut` (`auth_repository.dart:333`) awaits
`_auth.signOut()` **then** `_db.wipeAllData()`, with only the capture barrier
reopened in `finally`. If the sign-out call throws — offline, expired refresh
token, server error — the wipe never runs.

The next account then inherits the previous user's rows and a stale `sync_meta`
cursor, which is the exact failure `wipeAllData`'s own doc comment (line 49-54)
says it exists to prevent: the new user under-pulls their own data and sees
someone else's reminders. On a shared or handed-down device this is a data-leak,
not just a bug.

`test/data/wipe_on_logout_test.dart` covers the happy path only.

**Fix:** wipe in the `finally`, or wipe first and then sign out. Add a test where
the auth client throws.

---

# Medium

## M1 — Batch push has no per-row isolation, and the failure order is chained

`_flushTable` sends every dirty row for a table as one `upsert`. One rejected row
(bad uuid, FK violation, CHECK violation) fails all of them, permanently, and
`_report` only prints in debug builds.

The FK chain makes it cascade: `kSyncableTables` order is
`captures → task_reminders → reminder_events`, and `task_reminders` has a
composite FK to `captures` while `reminder_events` has one to `task_reminders`.
A single unpushable capture therefore stops three tables. There is no retry cap,
no dead-letter, no user-visible signal, and no metric.

**Fix (POC-sized):** on a batch failure, retry row-by-row, quarantine the row
that fails (a `sync_error` column or a local table), and surface a count in
Settings so a dogfooder can see that sync is stuck.

## M2 — `TaskReminder.copyWith` cannot clear a field, so six copies of the constructor exist

`task_reminder.dart:262` uses `x ?? this.x` throughout, so
`copyWith(scheduledAt: null)` is a no-op. The workaround is six hand-written
full-constructor reconstructions: `_withStatus`, `reenableReminder`,
`rescheduleReminder`, `editAutoCommit`, `editReminder`
(`reminder_creation_service.dart`), and the `later`/`reschedule` branches
(`reminder_scheduler.dart`).

They already disagree — `_withStatus` preserves `placeId`/`dwellSeconds`, the
snooze branch drops them, `editAutoCommit` keeps `autoCommitDeadlineAt` while
`_withStatus` conditionally clears it. Every new column has to be added in all
six, and the failure mode is silent data loss on edit rather than a compile
error.

**Fix:** add `clearX` flags to `copyWith` (the pattern `Capture.copyWith` already
uses with `clearError`) and delete the reconstructions.

## M3 — Native durability is inconsistent, and the alarm screen acts before it journals

Within `ReminderRuntimeBridge`, the action journal and the id allocator use
`commitChecked` — synchronous `commit()`, throws on failure. But `saveGeofence`,
`removeGeofence`, `saveTimeReminder`, `removeTimeReminder`,
`recordDwellTransition`, and `clearDwell` all use `.apply()` and run **outside**
`synchronized(prefsLock)`, despite being read-modify-write on a shared JSON blob.
Those are precisely the records reboot restoration depends on.

Separately, the ordering contract is violated in one place.
`ReminderGeofenceReceiver.onReceive` (line 26-29) journals first and bails if the
persist failed — correct. `ReminderAlarmActivity.finishWithAction` (line 301)
**cancels the alarm first**, then journals inside a `runCatching`. A failed
journal write there means the reminder is cancelled natively and Dart never
learns: it stays `active` in the database with no alarm behind it.

**Fix:** one durability policy — `commitChecked` under `prefsLock` for everything
in this file — and journal-before-act everywhere.

## M4 — The alarm screen re-implements the design system in Kotlin

`ReminderAlarmActivity.kt:434-444` hardcodes eleven `Color.rgb(...)` constants
that duplicate `analog_companion_theme.dart`, plus its own font loading from
`flutter_assets`. It is the single most visible surface in the product (full
screen, over the lock screen) and it will silently drift the first time the
palette changes.

**Fix:** generate the palette into a Kotlin/XML resource from the Dart tokens, or
at minimum add a test asserting the two agree.

## M5 — No timeout, no size guard on the Gemini call

`_parseWithGemini` (`reminder_draft_service.dart:434`) creates a bare
`HttpClient` with no `connectionTimeout` and no timeout on `request.close()`. A
hung request leaves the capture stuck in `CaptureStatus.processing` with no
recovery path, and the user sees a spinner that never resolves.

It also `base64Encode(await audioFile.readAsBytes())` with no length check —
whole file in memory, and inline data has a request-size ceiling that a long
recording will cross, producing an opaque non-2xx.

**Fix:** a 30s timeout with a `failed` capture status and a retry affordance; a
duration/size cap on inline audio with a clear message past it.

## M6 — Fired time-reminder records are never pruned

`saveTimeReminder` writes into the `time_reminders` prefs array;
`removeTimeReminder` only runs from `cancelTimeReminder`. A reminder that fires
and is left alone (no Done/Dismiss) keeps its record forever. `restoreTimeReminders`
skips past-due entries, so it is not a correctness bug — but the JSON array grows
unbounded and is re-parsed on every save, every id allocation, and every boot.

**Fix:** prune in the receiver when the alarm fires.

## M7 — UI actions swallow their errors

`reminders_screen.dart:256,264,285` and similar call
`cancelReminder` / `approveAutoCommit` / `reenableReminder` from `onPressed`
without awaiting or catching. `reenableReminder` and `rescheduleReminder` both
`throw StateError` on a past time — that becomes an unhandled async error and the
user sees the button do nothing.

**Fix:** a shared `_runAction` helper that awaits, catches, and shows a SnackBar.

## M8 — Scope leftovers and one platform-specific test guard

- Unreferenced in `lib/`: `EnergyModeService`, `ParticleBurst`,
  `ThemedEmptyScreen`, `personaLanguageProvider`, `pendingAudioQueueProvider`
  (defined but never read). `EnergyMode` is out of POC scope entirely.
- `poc_cleanup_test.dart:92` matches `'features\\conversations\\data'` — Windows
  separators only. That guard silently passes on any other platform.
- `SCHEDULE_EXACT_ALARM` is declared in the manifest; for an alarm-clock-style
  product `USE_EXACT_ALARM` is the permission Google Play expects, and it does not
  require the user-grant dance.
- `captures.audio_path` — a device filesystem path — is synced to the server. It
  is useless on any other device and leaks the local directory layout.
- The Gemini API key travels as a URL query parameter (`?key=`), so it lands in
  any proxy or crash log that records URLs.

---

# Quality (no defect, but they will slow the next change)

- **`watchX().first` as a one-shot read**, ~8 places: `_findReminder`,
  `_placeFor`, `_findReminderByCaptureDraft`, `_saveParsed`,
  `AssistantContextBuilder.build`. Each builds and tears down a drift query
  stream, and `_findReminder` loads **every** reminder to find one by id. Add
  `getById`/`getAll` to the repository interfaces.
- **`reminder_creation_service.dart` is 1031 lines** and holds the draft state
  machine, the capture-state codec, the auto-commit policy, and the edit
  operations. The codec (`_encodeCaptureState`/`_decodeCaptureState`) is a
  separate concern and would move out cleanly — and should, as part of fixing C4.
- **`inbox_screen.dart` is 886 lines** with the manual-create form, the review
  list, the countdown, and the edit dialog in one widget. The edit dialog is the
  obvious first extraction.
- **`_encodeCaptureState`** builds its JSON on one ~400-character line.
- **`app.dart:88`** calls `_attachScheduler` from `build()`. It is guarded by an
  identity check, but a side effect in `build` is a trap for the next editor.
- **`inbox_screen.dart:350`** `_maybeOpenLinkedEdit` mutates state from `build()`
  and schedules a dialog in a post-frame callback. Guarded, but fragile.
- **Notification action strings are duplicated in three places** —
  `ReminderNotificationAction.wire`, `ReminderGeofenceReceiver`, and
  `ReminderAlarmActivity` — with no shared constant.
- **The alarm screen offers Done / Dismiss / snooze / reschedule; the place
  notification offers Done / Later / Dismiss / Wrong place.** `POC_SPEC.md`
  specifies one action set. Either reconcile them or document the divergence.

---

# Suggested order

1. **C1** (timezone) — every parsed reminder is wrong for a non-UTC user, and it
   is cheap: write the pref, thread it into the prompt.
2. **C2** (uuid) — small change, and every day it survives is a day of correction
   signal not reaching the server.
3. **H6, H1, H2** — data-integrity and stale-registration bugs, all small.
4. **C3** (auto-commit) — needs a design decision (lifecycle hook vs. alarm), so
   it wants its own slice.
5. **C4** (capture-state column) — a migration plus a refactor; do it with the
   `reminder_creation_service` split.
6. **H5** (delete the dead dwell path) before anyone touches geofencing again.
7. **H3, H4** — product gaps in the correction loop; size them against the
   dogfood plan.
8. **M-tier** as the code around each is next touched.

Before the next dogfood round, the useful additions to the harness are: a test
asserting every `reminder_events.id` is a UUID; a test that the AI context
contains no raw capture text; and a place-delete test. Those three cover C2, C4,
and H1 and would have caught all three at authoring time.

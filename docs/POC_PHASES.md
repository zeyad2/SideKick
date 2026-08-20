# Sidekick POC Reset Phases

## Summary

Reset Sidekick into an Android-first POC for smart task reminders created from
typed input or the existing audio shortcut. The active product becomes:

> Capture or type a reminder once, let Sidekick infer the task/time/place
> trigger, then remind at the right moment with a correction loop.

Everything outside that loop becomes future work. The reset should not be
implemented in one giant pass. Each phase is small enough to run in its own chat
and must end with a report that the next phase can trust.

## Global Rules

- Do not preserve existing user data. A fresh POC schema is allowed.
- Android is the proof platform.
- iOS is deferred, but scheduler/capture interfaces must not make iOS impossible.
- Keep the hardware/audio shortcut in scope from the start.
- Keep multi-item auto-commit in scope, but every extracted item is a task
  reminder. No habit/goal/note classification in the POC.
- Auto-commit uses a 10-second countdown. The user can cancel or edit before the
  reminder activates.
- Unclear audio gets 2 retry prompts. After that, fall back to typed input.
- Future talk-back/persona work gets schema and clean interfaces now, but no chat
  UI, TTS, or spoken persona responses yet.
- Every phase must run the tests it owns plus a relevant regression subset.
- Every phase must write a phase report before stopping.

## Required Phase Report Format

Each phase must create `docs/reports/PHASE_<N>_<slug>.md` with:

- `Status`: PASS, PASS-WITH-DEBT, or BLOCKED.
- `Summary`: what changed in plain English.
- `Deliverables completed`: checklist matching that phase.
- `Tests run`: exact commands and pass/fail result.
- `Manual acceptance`: what still needs a real device or human check.
- `Changed contracts`: schemas, interfaces, routes, providers, prompt contracts.
- `Known debt`: acceptable follow-up work, with owning future phase.
- `Next phase handoff`: what the next chat should read first and depend on.

If a phase is blocked, the report must list the smallest concrete fixes needed
before the next phase starts.

---

# Phase 0 — Repo Reset and Source of Truth

## Objective

Make the repository mentally and structurally about the POC, without changing
runtime behavior yet more than necessary to remove stale navigation/docs.

## Deliverables

- Create current docs:
  - `docs/POC_SPEC.md`
  - `docs/POC_PHASES.md`
  - `docs/FUTURE_PLANS.md`
- Move legacy planning/review docs into `docs/archive/legacy-companion-v1/`.
- Rewrite `README.md` around the POC only.
- Remove or disconnect active routes for:
  - habits
  - Fresh Start
  - Done list
  - goals
  - notes
  - focus sessions
  - app blocking
  - vibe checks
  - old multi-kind capture review
- Keep active references to:
  - auth/profile
  - theme/shell
  - local-first sync
  - Android capture shortcut
  - Gemini transport
  - captures
  - task reminders
  - places
  - settings
  - events
- Add `docs/FUTURE_PLANS.md` entries for every removed product direction:
  habits, goals, focus/body double, app blocking, persona chat/TTS, insights,
  iOS proof, additional themes, and broad capture decomposition.

## Tests

- `dart analyze`
- `flutter analyze`
- App shell test asserts only POC destinations are visible.
- Static cleanup test asserts no active imports from removed feature packages.
- Static docs test asserts README links point only to current POC docs or archive
  docs.
- Regression: auth gate and splash/login/onboarding route tests still pass.

## Manual Acceptance

- Launch app and confirm navigation is POC-only.
- Confirm old docs are findable in archive but not presented as current truth.

## Phase Report

Write `docs/reports/PHASE_0_repo_reset.md`.

The report must include:

- Exact list of archived docs.
- Exact active navigation destinations after reset.
- Any removed feature folders that still have references.
- Any deliberately retained legacy code and why.

---

# Phase 1 — Fresh POC Data Model

## Objective

Replace the broad companion schema with a fresh reminder-first model and a small
set of repositories that future phases can build on.

## Deliverables

- Reset Drift schema to version 1 for the POC.
- Replace Supabase migrations with a fresh POC baseline.
- POC tables:
  - `profiles`
  - `places`
  - `captures`
  - `task_reminders`
  - `reminder_events`
  - `conversations`
  - `messages`
  - `events`
- `task_reminders` supports:
  - `id`
  - `user_id`
  - `title`
  - `details`
  - `status`
  - `source`
  - `confidence`
  - `trigger_type`
  - `scheduled_at`
  - `place_id`
  - `geofence_transition`
  - `dwell_seconds`
  - `auto_commit_deadline_at`
  - `capture_id`
  - `ai_explanation`
  - `ai_context`
  - `created_at`
  - `updated_at`
  - `deleted_at`
- Local-only sync columns remain local:
  - `dirty`
  - `synced_at`
- Add repository interfaces and implementations:
  - `TaskRemindersRepository`
  - `PlacesRepository`
  - `CapturesRepository`
  - `ReminderEventsRepository`
  - `ConversationRepository`
  - `ProfileRepository`
- Remove active repositories for removed features.
- Update sync table registry to include only POC syncable tables.
- Keep events append-only.
- Keep conversations/messages unused by UI.

## Tests

- Drift/Supabase column parity test passes for the fresh POC schema.
- RLS test blocks cross-user reads and writes on all POC tables.
- Repository tests prove:
  - local-first create marks rows dirty.
  - update marks rows dirty and advances `updated_at`.
  - soft delete hides rows from watch streams.
  - tombstones remain syncable.
  - user A cannot see user B rows locally through repository streams.
- Sync tests prove:
  - dirty POC rows flush.
  - pull applies remote rows.
  - owner-scoped flush still holds.
  - event insert remains idempotent.
- Conversation/message tests prove storage works and no UI route reads it.
- Full repository regression suite passes.

## Manual Acceptance

- Existing local DB can be wiped/recreated without preserving old rows.
- App can sign in, create profile, and reach the POC shell with fresh schema.

## Phase Report

Write `docs/reports/PHASE_1_data_model.md`.

The report must include:

- Final table list.
- Final repository list.
- Any old table/repository intentionally left behind.
- Migration reset notes.
- Exact schema/version numbers.
- Any Supabase dashboard/manual steps required.

---

# Phase 2 — Typed and Audio Creation Loop

## Objective

Make typed input and Android audio shortcut feed the same reminder-drafting
pipeline.

## Deliverables

- Main screen becomes reminder creation plus active reminder list.
- Typed input path:
  - user enters natural language.
  - AI parses it into one or more task-reminder drafts.
  - high-confidence drafts enter auto-commit countdown.
  - low-confidence or incomplete drafts open review.
- Audio shortcut path:
  - volume gesture starts/stops recording.
  - audio is written to disk before AI.
  - saved audio capture feeds the same draft pipeline as typed input.
  - failed AI leaves audio/capture retryable.
- Add `ReminderDraftService`:
  - `parseText(input, context)`
  - `parseAudio(file, context)`
- Draft output is task-reminder only:
  - title
  - details
  - confidence
  - trigger type
  - scheduled time
  - place candidate
  - geofence transition
  - dwell seconds
  - explanation
- Multi-item capture remains:
  - a single text/audio rant can produce multiple task-reminder drafts.
  - no item can be habit, goal, or note.
- Auto-commit flow:
  - high-confidence draft with a clear trigger becomes `pending_auto_commit`.
  - default countdown is 10 seconds.
  - user can Cancel or Edit before deadline.
  - deadline expiry promotes reminder to `active`.
- Unclear audio flow:
  - prompt retry after unclear parse.
  - allow 2 retries.
  - after retry limit, show typed fallback message.

## Tests

- Typed high-confidence reminder enters countdown.
- Countdown expiry activates reminder.
- Cancel during countdown prevents activation.
- Edit during countdown saves edited reminder.
- Typed multi-task input creates multiple pending auto-commit reminders.
- Audio capture with multiple clear task reminders creates multiple pending
  auto-commit reminders.
- Low-confidence draft opens review instead of auto-commit.
- Missing-trigger draft opens review instead of auto-commit.
- Gemini/task-draft parser rejects habit/goal/note output.
- Unclear audio permits 2 retries and then shows typed fallback.
- Capture audio remains on disk after AI/network failure.
- Regression: native capture event contract still passes.

## Manual Acceptance

- On Android device, trigger capture from foreground app and create reminder
  draft.
- Speak a multi-task reminder and confirm all extracted items are task reminders.
- Verify wrong/unclear speech does not create vague reminders silently.

## Phase Report

Write `docs/reports/PHASE_2_creation_loop.md`.

The report must include:

- Final draft JSON contract.
- Auto-commit eligibility rules.
- Retry/fallback behavior.
- Native capture manual test results.
- Any Gemini prompt limitations.

---

# Phase 3 — Reminder Runtime

## Objective

Make active reminders actually fire and respond to user actions.

## Deliverables

- Add `ReminderScheduler` interface:
  - `schedule(TaskReminder)`
  - `cancel(id)`
  - `resyncAll()`
  - `handleAction(action)`
- Android scheduler implementation supports:
  - local time notifications
  - geofence enter reminders
  - geofence exit reminders
  - dwell filtering
  - app-start resync
  - reboot resync if feasible in this phase
- Default geofence settings:
  - radius: 150m
  - dwell: 60 seconds
- Notification actions:
  - Done
  - Later
  - Dismiss
  - Wrong place
- Action behavior:
  - Done sets reminder status to `done` and logs event.
  - Later snoozes 2 hours and logs event.
  - Dismiss logs event and leaves reminder active unless one-shot semantics say
    otherwise.
  - Wrong place logs event and opens edit flow when tapped.
- Settings supports:
  - shortcut status/config
  - notification permission
  - location permission
  - saved places
  - sync/account

## Tests

- Time reminder schedules a notification through scheduler interface.
- Done marks reminder done and logs `reminder_actioned`.
- Later sets snooze for 2 hours and reschedules.
- Dismiss logs event without deleting reminder.
- Wrong place logs event and stores correction signal.
- Geofence reminder registers expected place/radius/transition.
- Dwell filter prevents immediate noisy firing.
- `resyncAll()` restores active reminders after app restart.
- Permission-denied states are visible and non-crashing.
- Regression: auto-commit activation calls scheduler exactly once.

## Manual Acceptance

- Android device receives a time reminder.
- Android device receives enter-place reminder.
- Android device receives exit-place reminder.
- Dwell filter waits before firing.
- Notification actions work from notification shade without opening app.
- Reboot/app restart restores active reminders or reports explicit limitation.

## Phase Report

Write `docs/reports/PHASE_3_reminder_runtime.md`.

The report must include:

- Scheduler implementation details.
- Android permission behavior.
- Reboot behavior status.
- Manual geofence test notes.
- Known OEM/battery limitations.

---

# Phase 4 — Life Context AI

## Objective

Give reminder drafting enough life context to be useful without turning Sidekick
into a chat app yet.

## Deliverables

- Add `AssistantContextBuilder`.
- Context includes:
  - profile preferences
  - saved places
  - active task reminders
  - recent reminder actions
  - recent unclear captures
- Reminder draft prompt uses context only to improve user-requested reminders.
- AI must not create reminders from context alone.
- Every AI-created reminder stores:
  - selected trigger explanation
  - context items used
  - confidence
- Feedback loop writes reminder events from:
  - Done
  - Later
  - Dismiss
  - Wrong place
  - Edit
- Keep future conversational storage:
  - `conversations`
  - `messages`
- Do not build:
  - chat UI
  - TTS
  - spoken persona responses
  - proactive assistant suggestions

## Tests

- Saved places appear in AI context.
- Active reminders appear in AI context.
- Recent Wrong place feedback appears in later context.
- Recent unclear captures appear in context.
- AI-created reminder stores explanation metadata.
- AI does not create reminders without user input.
- Prompt/service tests assert output kind is always task reminder.
- Conversation/message repositories work.
- Static route test asserts no chat UI route exists.
- Context builder enforces bounded payload size.

## Manual Acceptance

- Add named places, then type/speak using place nicknames and confirm AI chooses
  the right saved place.
- Mark a reminder Wrong place, create a similar reminder, and confirm review
  shows better context/explanation.
- Confirm app does not appear to chat back or impersonate a persona.

## Phase Report

Write `docs/reports/PHASE_4_life_context_ai.md`.

The report must include:

- Final context object shape.
- Prompt contract.
- Context size limits.
- Example AI explanations.
- Future chat integration notes.

---

# Phase 5 — Android Dogfood Hardening

## Objective

Stop feature expansion and prove the POC survives real Android use.

## Deliverables

- Run real-device Android acceptance.
- Fix only:
  - capture reliability
  - reminder scheduling
  - location/geofence behavior
  - permissions
  - sync reliability
  - wrong-reminder correction bugs
- Freeze feature additions for 2 weeks.
- Record all non-POC requests in `docs/FUTURE_PLANS.md`.
- Add a dogfood log template in `docs/reports/DOGFOOD_LOG.md`.

## Automated Tests

- Full Flutter test suite passes.
- Full Dart/Flutter analysis passes.
- Android unit tests pass.
- Scheduler regression suite passes.
- Sync regression suite passes.
- Static cleanup test still proves removed features are not active.

## Manual Acceptance

- Shortcut capture works from:
  - lock screen
  - background
  - inside another app
- Typed reminder creation works.
- Audio reminder creation works.
- Multi-task audio capture works.
- Time reminder fires.
- Enter geofence reminder fires.
- Exit geofence reminder fires.
- Dwell filtering works.
- Done/Later/Dismiss/Wrong place actions work.
- Reboot/app restart restores active reminders.
- Offline capture retries AI processing when online.
- No removed feature appears in navigation or settings.

## Phase Report

Write `docs/reports/PHASE_5_android_dogfood.md`.

The report must include:

- Device model and Android version.
- Permission state.
- Battery optimization state.
- Manual acceptance checklist results.
- Bugs fixed during hardening.
- Bugs deferred after freeze.
- Recommendation: continue dogfood, build iOS proof, or revisit product scope.

---

# Public Interfaces and Types

- Replace broad entity repositories with POC repositories only.
- Use `ReminderDraftService` for all AI reminder extraction.
- Use `AssistantContextBuilder` for all AI context.
- Use `ReminderScheduler` for all notification/geofence scheduling.
- Keep `NativeCaptureApi`, but saved captures feed only reminder drafting.
- Keep future chat storage through `ConversationRepository`, but no UI depends
  on it.

# Future Plans Policy

Any idea outside the POC goes into `docs/FUTURE_PLANS.md`, not active code.

Future plans include:

- habits
- Fresh Start
- Done list
- focus/body double
- app blocking
- goals/Goal Sage
- persona chat
- TTS/talk-back
- monthly insights
- iOS implementation proof
- additional themes
- broad non-reminder capture inbox


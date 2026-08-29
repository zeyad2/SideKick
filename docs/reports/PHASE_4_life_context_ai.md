# Phase 4 Life Context AI

## Status

PASS-WITH-DEBT

## Summary

Sidekick now has a local `AssistantContextBuilder` that gathers bounded life context for reminder drafting: profile preferences, saved places, active reminders, recent reminder feedback, and recent unclear captures. The typed and audio creation loop builds that context for each user request, Gemini receives the bounded redacted context in its prompt, local heuristic drafting can use saved place names to choose place triggers, AI-created reminders persist selected trigger explanations plus context item IDs used, and edit feedback writes reminder events.

External Gemini prompts receive only the bounded Phase 4 context shape: place names without coordinates, active reminder trigger summaries without details, allowlisted recent reminder action metadata, allowlisted profile preferences, and unclear capture errors without transcripts. Gemini output is rejected if it references place IDs or context item IDs that were not supplied in that exact context.

## Deliverables completed

- [x] Added `AssistantContextBuilder`.
- [x] Context includes profile preferences.
- [x] Context includes saved places.
- [x] Context includes active task reminders.
- [x] Context includes recent reminder actions.
- [x] Context includes recent unclear captures.
- [x] Reminder drafting builds context per typed/audio request.
- [x] Gemini prompt receives bounded/redacted context.
- [x] Local drafting uses context only to improve user-requested reminders.
- [x] AI-created reminders store selected trigger explanations.
- [x] AI-created reminders store context item IDs used.
- [x] AI place IDs and `context_items_used` are validated against the exact
  supplied context before persistence.
- [x] Gemini output validates required kind/title, enums, numeric confidence,
  coherent trigger fields, timezone-qualified timestamps, and non-empty
  explanations.
- [x] Gemini output rejects malformed or non-string `context_items_used` before
  persistence.
- [x] Profile prefs and reminder-event metadata are allowlisted before external
  AI context use.
- [x] Context builder enforces a minimum byte-bound floor and bounded max size.
- [x] Static regression asserts there is no active chat route/UI import.
- [x] Recent Wrong Place feedback deterministically lowers confidence for a
  similar place draft so it goes to review instead of auto-commit.
- [x] Feedback loop writes reminder events for Done, Later, Dismiss, Wrong place, and Edit.
- [x] Conversations/messages remain storage-only.
- [x] No chat UI, TTS, spoken persona response, or proactive assistant suggestion was added.

## Tests run

- `C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze`: PASS, no issues.
- `C:\src\flutter\bin\flutter.bat analyze`: PASS, no issues, run outside
  sandbox after in-sandbox Flutter commands hung silently.
- `git diff --check`: PASS, whitespace clean. Git reported existing CRLF warnings only.
- `C:\src\flutter\bin\flutter.bat test`: PASS, 104 tests, run outside sandbox.
- `.\gradlew.bat :app:testDebugUnitTest`: PASS outside sandbox after the
  in-sandbox run failed to access `android/.gradle/.../fileHashes.lock`.
- `supabase test db`: PASS twice, 4 files / 10 pgTAP tests each run.

Added or extended tests for saved places, active reminders, Wrong place feedback, unclear captures, bounded payload size, context-backed place trigger selection, context metadata persistence, empty-input non-creation, edit feedback events, adversarial Gemini output, unknown context IDs, malformed context item lists, timezone-qualified timestamps, non-empty explanations, no-chat routes/imports, allowlisted external metadata, byte-bound floor validation, and IANA timezone conversion using Africa/Cairo plus DST transition cases.

## Manual acceptance

Not yet run. Still needed on Android:

- Add named places, then type/speak using place nicknames and confirm Sidekick chooses the right saved place.
- Mark a reminder Wrong place, create a similar reminder, and confirm review shows improved context/explanation.
- Confirm the app does not expose chat UI, spoken persona responses, or proactive assistant suggestions.

## Changed contracts

- Added `AssistantContext` and `AssistantContextBuilder` in `lib/features/reminders/application/assistant_context_builder.dart`.
- Added `RepositoryAssistantContextBuilder` with default limits: 12 KB encoded context, 20 saved places, 20 active reminders, 30 recent reminder actions, and 10 recent unclear captures.
- Added `assistantContext` to `ReminderDraftContext`.
- Added `contextItemsUsed` to `ParsedReminderDraft`.
- Added `context_items_used` to persisted reminder `aiContext` metadata.
- Added `ReminderEventsRepository.recentActions(limit:)`.
- `ReminderCreationService` now accepts optional `contextBuilder`, `events`, and scheduler dependencies.
- `editAutoCommit()` now records a `ReminderEventType.edited` feedback event.
- `GeminiReminderDraftService` rejects unsupplied context IDs and malformed
  task-reminder fields instead of defaulting them.

## Final context object shape

```json
{
  "profile": {
    "id": "user id",
    "persona_response_language": "en",
    "theme": "analog_companion",
    "prefs": {"timezone": "Africa/Cairo"}
  },
  "places": [
    {"id": "place id", "name": "Workshop", "radius_m": 150}
  ],
  "active_reminders": [
    {
      "id": "reminder id",
      "title": "Pick up meds",
      "trigger_type": "time",
      "scheduled_at": "2026-08-22T17:00:00.000Z",
      "place_id": null,
      "geofence_transition": null,
      "dwell_seconds": null
    }
  ],
  "recent_reminder_actions": [
    {
      "id": "event id",
      "reminder_id": "reminder id",
      "event_type": "wrong_place",
      "metadata": {"correction": "wrong_place", "place_id": "place id"},
      "occurred_at": "2026-08-22T09:00:00.000Z"
    }
  ],
  "recent_unclear_captures": [
    {
      "id": "capture id",
      "source": "audio",
      "error": "Audio was unclear.",
      "captured_at": "2026-08-22T09:00:00.000Z"
    }
  ],
  "truncated": false,
  "max_bytes": 12288
}
```

Coordinates, reminder details, unclear transcripts, non-allowlisted profile
prefs, and non-allowlisted reminder-event metadata are excluded from the context
object used by Phase 4 tests.

## Prompt contract

Gemini drafting still receives the Phase 2 task-reminder-only JSON contract, with these Phase 4 additions:

- the bounded/redacted assistant context JSON is included in the prompt.
- `context_items_used` is present in every draft and should include stable IDs such as `place:<id>` when the context influenced a field.
- The prompt explicitly says not to create reminders from background context.
- The prompt says to use context only to resolve ambiguity in the user's explicit typed or audio request.

Local heuristic drafting also uses the in-memory context to match saved place names and emits context item IDs such as `place:<id>`.

## Context size limits

`RepositoryAssistantContextBuilder` enforces a minimum max-bytes floor of 512
bytes, then enforces the encoded JSON payload limit by dropping lower-priority
list items in this order: recent unclear captures, recent reminder actions,
active reminders, saved places, then profile. The default limit is 12 KB. Tests
cover truncation with a smaller limit and rejection below the floor.

## Example AI explanations

- Time reminder: `Detected a time trigger from the reminder text.`
- Saved place reminder: `Matched the place trigger to a saved place from life context.`
- Wrong Place review: `Matched a saved place, but recent Wrong place feedback means this needs review.`
- Place reminder needing review: `Detected a place trigger, but it needs a saved place before activation.`

## Known debt

- Privacy/consent hardening for external AI context sharing remains logged in `TECH_DEBT.md`.
- In-sandbox Flutter commands can hang silently in this managed shell; the
  Flutter analyzer and full test suite passed when rerun outside the sandbox.

## Future chat integration notes

The `conversations` and `messages` repositories remain available as storage only. No route, shell destination, chat UI, TTS, spoken persona response, or proactive assistant suggestion was added. A future chat phase should depend on the bounded `AssistantContext` shape rather than reaching directly into repositories.

## Next phase handoff

Phase 5 should read first:

- `lib/features/reminders/application/assistant_context_builder.dart`
- `lib/features/reminders/application/reminder_draft_service.dart`
- `lib/features/reminders/application/reminder_creation_service.dart`
- `lib/features/reminders/application/reminder_scheduler.dart`
- `test/reminders/assistant_context_builder_test.dart`
- `test/reminders/reminder_creation_service_test.dart`
- `docs/reports/PHASE_3_reminder_runtime.md`

Before dogfood, rerun the focused Flutter tests in a normal shell and perform the Phase 4 manual acceptance on Android.

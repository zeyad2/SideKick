# Phase 2 Creation Loop

## Status

PASS-WITH-DEBT

## Summary

Typed input and saved audio captures now feed the same reminder-drafting
application service. The active capture screen can create task-reminder drafts,
show pending auto-commit reminders, cancel pending reminders, retry saved audio
captures, and show review cards for low-confidence or incomplete drafts.

When `GEMINI_API_KEY` is configured, `GeminiReminderDraftService` sends typed
text or saved audio bytes to Gemini and parses the strict task-reminder JSON
contract. Without a key, the app keeps a deterministic heuristic fallback so
local tests and no-network development still work.

## Deliverables completed

- [x] Main screen includes typed reminder creation.
- [x] Main screen shows active/pending task reminder rows.
- [x] Typed input feeds `ReminderCreationService.submitText`.
- [x] Audio captures feed `ReminderCreationService.processAudioCapture`.
- [x] Added `ReminderDraftService.parseText(input, context)`.
- [x] Added `ReminderDraftService.parseAudio(file, context)`.
- [x] Draft output is task-reminder-only.
- [x] Multi-item typed/audio parsing can create multiple reminder drafts.
- [x] High-confidence complete drafts enter `pending_auto_commit`.
- [x] Auto-commit countdown defaults to 10 seconds.
- [x] Cancel prevents pending auto-commit activation.
- [x] Edit saves changes before activation from the pending reminder UI and
  application-service layer.
- [x] Low-confidence and missing-trigger drafts open on-screen review cards
  instead of persisted auto-commit rows.
- [x] Review cards can approve edited drafts into active reminders.
- [x] Parser rejects habit/goal/note wording.
- [x] Unclear audio allows two attempts, then asks the user to type instead.
- [x] Audio capture file paths are preserved after parser failure.
- [x] UI timer calls auto-commit activation when deadlines pass.

## Tests run

- `C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe format ...`: PASS.
- `C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze lib\features\reminders test\reminders`:
  PASS, `No issues found!`.
- `C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze lib\features\inbox test\inbox`:
  PASS, `No issues found!`.
- `git diff --check`: PASS.
- `cmd.exe /c C:\src\flutter\bin\flutter.bat --version`: PASS outside the
  managed sandbox, Flutter 3.44.6 / Dart 3.12.2.
- `cmd.exe /c C:\src\flutter\bin\flutter.bat analyze`: PASS, `No issues
  found!`.
- `cmd.exe /c C:\src\flutter\bin\flutter.bat test test\reminders\reminder_creation_service_test.dart test\inbox\inbox_ui_test.dart`:
  PASS, 16 tests passed.
- `cmd.exe /c C:\src\flutter\bin\flutter.bat test`: PASS, 59 tests passed.

Added test coverage in `test/reminders/reminder_creation_service_test.dart` for:

- typed high-confidence reminder countdown.
- countdown expiry activation.
- cancel before activation.
- edit before activation.
- typed multi-task input.
- audio multi-task input.
- low-confidence review.
- missing-trigger review.
- reviewed draft approval.
- reviewed time drafts require a concrete schedule before activation.
- habit/goal/note rejection.
- unclear-audio retry limit.
- audio file retention after parser failure.

Added widget coverage in `test/inbox/inbox_ui_test.dart` for:

- pending auto-commit reminders expose both Edit and Cancel.

## Manual acceptance

- Needs Android device test for foreground hardware/audio shortcut capture.
- Needs spoken multi-task capture test on Android.
- Needs unclear-speech test on Android to verify the retry/fallback copy is
  visible and no vague reminder is created silently.

## Changed contracts

- Added `clockProvider` for deterministic countdown/deadline logic.
- Added `ReminderDraftService`:
  - `parseText(String input, ReminderDraftContext context)`
  - `parseAudio(File file, ReminderDraftContext context)`
- Added `GeminiReminderDraftService`:
  - typed text request through Gemini REST `generateContent`
  - saved audio request through Gemini inline audio bytes
  - strict task-reminder JSON parser
- Added `ReminderCreationService`:
  - `submitText(String input)`
  - `processAudioCapture(Capture capture)`
  - `activateDueAutoCommits()`
  - `cancelAutoCommit(String id)`
  - `editAutoCommit(String id, ...)`
  - `approveReviewedDraft(...)`
- Added Riverpod providers:
  - `inboxTaskRemindersProvider`
  - `reminderDraftServiceProvider`
  - `reminderCreationServiceProvider`

## Final draft JSON contract

```json
{
  "drafts": [
    {
      "kind": "task_reminder",
      "title": "Call the dentist",
      "details": "Remind me to call the dentist tomorrow",
      "confidence": 0.88,
      "trigger_type": "time",
      "scheduled_at": "2026-08-21T09:00:00.000Z",
      "place_candidate": null,
      "geofence_transition": null,
      "dwell_seconds": null,
      "explanation": "Detected a time trigger from the reminder text."
    }
  ],
  "raw_transcript": "Remind me to call the dentist tomorrow",
  "is_unclear": false
}
```

Allowed `trigger_type` values are `time` and `place`. Place drafts need a saved
`place_id` before auto-commit; unresolved place names stay in review.

## Auto-commit eligibility rules

- `confidence >= 0.75`.
- Time trigger requires `scheduled_at`.
- Place trigger requires `place_id`.
- Eligible drafts are saved as `task_reminders.status = pending_auto_commit`.
- `auto_commit_deadline_at = clock.now + 10 seconds`.
- Deadline expiry promotes the reminder to `active` through the capture screen's
  timer while the app is open.
- Cancel promotes the reminder to `cancelled`.
- Review drafts open an on-screen card and are not silently activated.
- Reviewed time reminders require a concrete scheduled time before activation.
- Reviewed place reminders require a concrete place and geofence transition
  before activation.

## Retry/fallback behavior

- Audio parse result with `is_unclear = true` marks the capture `failed`.
- First unclear parse shows retry copy.
- Second unclear parse shows typed fallback copy.
- Parser/network failure marks the capture `failed` and leaves `audio_path`
  unchanged for retry.

## Known debt

- Review-card state is in-memory until the user approves or dismisses it. The
  original capture remains retryable, but edited review state is lost on app
  restart. Logged in `TECH_DEBT.md`.
- Auto-commit activation runs from the capture screen while the app is open.
  Phase 3 owns scheduler/lifecycle integration for notifications and app-start
  resync.

## Next phase handoff

Read first:

- `lib/features/reminders/application/reminder_draft_service.dart`
- `lib/features/reminders/application/reminder_creation_service.dart`
- `lib/features/reminders/domain/task_reminder.dart`
- `lib/features/inbox/presentation/inbox_screen.dart`
- `test/reminders/reminder_creation_service_test.dart`

Phase 3 can depend on pending auto-commit rows becoming active through
`ReminderCreationService.activateDueAutoCommits()` while the capture screen is
alive. It should add scheduler integration and assert active reminders schedule
exactly once. Flutter analysis and the full Flutter test suite pass when run
outside the managed sandbox.

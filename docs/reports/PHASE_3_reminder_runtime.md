# Phase 3 Reminder Runtime

## Status

PASS-WITH-DEBT

## Summary

Active reminders now have a scheduler application boundary, notification action
handling, app-start/resume resync, auto-commit and reviewed-draft scheduling,
permission/status UI, Android native AlarmManager time notification scheduling, native Android
proximity geofence registration, and reboot receiver wiring for scheduled local
notifications.

The remaining risk is device acceptance: automated scheduler, Flutter, Android
unit, and Supabase gates pass, but geofence/notification/reboot behavior still
needs a real Android device pass before dogfood signoff.

## Deliverables completed

- [x] Added `ReminderScheduler` with `schedule`, `cancel`, `resyncAll`, and
  `handleAction`.
- [x] Added `ReminderSchedulerService` for repository-backed runtime behavior.
- [x] Added Android notification adapter boundary using native AlarmManager,
  BroadcastReceiver notification delivery, and a durable native action journal.
- [x] Android time/place notification actions enter the same native
  BroadcastReceiver journal; Dart foreground/background notification callbacks
  no longer dispatch time actions through isolate-local state.
- [x] Added notification actions: Done, Later, Dismiss, Wrong place.
- [x] Done marks reminders `done`, cancels scheduling, and logs a reminder
  event.
- [x] Later snoozes for 2 hours, converts the reminder to a time reminder, logs
  an event, and reschedules.
- [x] Dismiss logs an event and leaves the reminder active.
- [x] Wrong place logs a correction signal.
- [x] Geofence reminders produce scheduler requests with place, radius,
  transition, and dwell values.
- [x] Android geofence requests register through a native platform channel using
  `LocationManager.addProximityAlert`.
- [x] Native geofence registrations are persisted and restored by a boot/package
  receiver.
- [x] Default geofence settings are represented as 150m radius and 60 seconds
  dwell.
- [x] Dwell filtering prevents immediate noisy firing at the application layer
  and the native place-notification path delays delivery with a durable alarm.
- [x] `resyncAll()` restores active reminders from local storage on app start
  and app resume.
- [x] Auto-commit activation calls the scheduler for newly active reminders.
- [x] Reviewed draft approval schedules the newly active reminder immediately.
- [x] Settings shows shortcut, notification, location, saved places, sync, and
  account status surfaces.
- [x] Android manifest declares notification, foreground/background location,
  and boot receiver permissions/receivers.
- [x] Android notification actions use non-foreground actions and native place
  notification actions are queued durably for Flutter to drain on startup.
- [x] Native time/place notification actions use a durable shared action
  journal with stable action IDs; Dart drains without deletion and ACKs only
  after repository mutation plus deterministic `native_action_id` reminder-event
  persistence.
- [x] Notification/geofence/action/dwell integer IDs use persisted managed ID
  mappings instead of FNV/hash IDs.
- [x] Native dwell handling cancels opposite transitions before firing and
  verifies durable dwell state when the alarm fires.
- [x] Wrong Place logs feedback, records an edit deep-link route, launches the
  app from the native receiver for cold/warm starts, and opens the actual
  reminder edit dialog through the app dispatcher after persistence.
- [x] Location scheduling failures are caught per reminder during resync, and
  native geofence registration returns a typed denied-permission failure when
  foreground/background location is missing.

## Tests run

- `C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze`: PASS, no issues.
- `C:\src\flutter\bin\flutter.bat analyze`: PASS, no issues, run outside
  sandbox after in-sandbox Flutter commands hung silently.
- `git diff --check`: PASS.
- `C:\src\flutter\bin\flutter.bat test`: PASS, 104 tests, run outside sandbox.
- `.\gradlew.bat :app:testDebugUnitTest`: PASS outside sandbox after the
  in-sandbox run failed to access `android/.gradle/.../fileHashes.lock`.
- `supabase test db`: PASS twice, 4 files / 10 pgTAP tests each run.

Added test coverage in `test/reminders/reminder_scheduler_test.dart` for:

- time reminder scheduling through the scheduler interface.
- Done action status/event behavior.
- Later action two-hour snooze and reschedule behavior.
- Dismiss action event behavior.
- Wrong place correction event metadata.
- geofence registration request shape.
- dwell filtering.
- app-start resync.
- auto-commit activation scheduling exactly once.
- notification action payloads dispatching through the attached scheduler.
- approved review drafts scheduling immediately.
- background-location denied state is modeled separately in the permission
  snapshot/settings UI.
- durable native action drain/ACK behavior.
- native managed-ID collision regression using the reproduced UUID pair.
- native enter->early-exit and exit->early-enter dwell cancellation.
- scheduler ACK-after-persistence for native actions.
- native action replay idempotency by `native_action_id`.
- Wrong Place edit-dispatch evidence after event persistence.

## Manual acceptance

Not yet run. Still needed on Android:

- Receive a local time reminder.
- Receive enter-place and exit-place reminders.
- Verify dwell filtering waits before firing.
- Verify notification actions from the notification shade.
- Verify Wrong Place opens the edit dialog on warm and cold app starts.
- Verify reboot/app restart restoration.

## Changed contracts

- Added `ReminderScheduler` in
  `lib/features/reminders/application/reminder_scheduler.dart`.
- Added `ReminderSchedulePlatform` adapter boundary.
- Added native Android reminder channel `com.sidekick/reminders`.
- Added `ReminderNotificationAction` and `ReminderAction`.
- Added `ReminderNotificationPayload`; Android action handling is journal-first
  through the native receiver, while `ReminderNotificationDispatcher` remains
  only for non-native/legacy in-process dispatch paths.
- Added `ReminderEditDispatcher` for persisted Wrong Place feedback to open the
  edit UI after repository/event writes.
- Added `ReminderGeofenceTrigger` and `ScheduledReminderRequest`.
- Added `reminderSchedulePlatformProvider` and `reminderSchedulerProvider`.
- `ReminderCreationService.activateDueAutoCommits()` now schedules each newly
  active reminder when a scheduler is supplied.
- `ReminderCreationService.approveReviewedDraft()` now schedules each approved
  active reminder when a scheduler is supplied.
- `CapturePermissionSnapshot` now includes `location`.
- `pubspec.yaml` now directly depends on `timezone: 0.10.1`.

## Known debt

- Geofences use Android `LocationManager.addProximityAlert` for the POC instead
  of Play Services geofencing; reliability must be proven on device.
- In-sandbox Flutter/Supabase commands can fail or hang on SDK/user-cache
  access; the analyzer, full Flutter tests, Gradle tests, and Supabase tests
  passed when rerun with normal SDK/cache access.

## Next phase handoff

Phase 4 can start from the application-layer contracts, but Phase 5 must run
real-device acceptance before dogfood. Read first:

- `lib/features/reminders/application/reminder_scheduler.dart`
- `lib/features/reminders/application/android_reminder_schedule_platform.dart`
- `lib/features/reminders/application/reminder_scheduler_providers.dart`
- `lib/features/reminders/application/reminder_creation_service.dart`
- `android/app/src/main/kotlin/com/sidekick/sidekick/ReminderRuntimeBridge.kt`
- `android/app/src/main/kotlin/com/sidekick/sidekick/ReminderGeofenceReceiver.kt`
- `test/reminders/reminder_scheduler_test.dart`

Device acceptance still needed before Phase 5:

- Verify time reminders and notification actions on Android.
- Verify enter/exit place reminders on Android.
- Verify dwell behavior and OEM battery limitations.
- Verify reboot/app restart restoration on Android.

# Runtime contracts

The three boundaries the compiler does not check for you: Dart↔Kotlin,
Dart↔Postgres, and Dart↔the model. Breaking one of these produces a defect that
passes `dart analyze`, passes `flutter test`, and only shows up on a device or in
a sync log nobody is reading.

Change any table in this document and you are changing a contract: update both
sides in the same commit, and add a test.

---

## 1. Dart ↔ Kotlin

### Channel `com.sidekick/reminders`

Dart side: `AndroidReminderSchedulePlatform`, `CurrentLocationPlatform`.
Kotlin side: `ReminderRuntimeBridge.configure`.

| Method | Arguments | Returns | Error codes |
|---|---|---|---|
| `registerGeofence` | `id`, `title`, `details?`, `lat`, `lng`, `radiusM`, `transition` (`enter`\|`exit`), `dwellSeconds` | `null` | `invalid_geofence`, `geofence_register_failed` (includes the `SecurityException` for missing background location) |
| `cancelGeofence` | `id` | `null` | — |
| `scheduleTimeReminder` | `id`, `title`, `details?`, `triggerAtMs` (epoch ms, UTC), `notificationId` | `null` | `invalid_time_reminder` |
| `cancelTimeReminder` | `id`, `notificationId?` | `null` | — |
| `managedNotificationId` | `id` | `Int` | `invalid_id` |
| `managedRequestCode` | `key` | `Int` | `invalid_key` |
| `drainNativeActions` | — | `List<Map>` | — |
| `ackNativeAction` | `actionId` | `null` | — |
| `enqueueNativeAction` | `id`, `action`, `rescheduleAtMs?` | `null` | `invalid_action` |
| `currentLocation` | — | `{lat, lng}` | `location_permission_denied`, `location_disabled`, `location_unavailable` |
| `currentTimeZoneName` | — | device IANA timezone id | — |
| `getReminderSoundState` | — | selected id, local-file state, catalog download state | — |
| `downloadReminderSound` | `id` | `null` | `invalid_sound`, `sound_download_failed` |
| `selectReminderSound` | `id` | `null` | `sound_select_failed` |
| `previewReminderSound` | `id` | `null` | `sound_preview_failed` |
| `deleteReminderSound` | `id` | `null` | `sound_delete_failed` |
| `pickLocalReminderSound` | — | `null` after picker completes | `sound_picker_unavailable`, `sound_import_failed` |

**Native action journal entry** — the shape `drainNativeActions` returns:

```
{
  actionId:      String   "<reminderId>:<action>:<seq>"   // journal key, NOT a UUID
  id:            String   reminder id (uuid)
  action:        String   done | later | reschedule | dismiss | wrong_place | open
  source:        String   native_notification | native_alarm
  recordedAtMs:  Long
  rescheduleAtMs Long?    present only for reschedule
}
```

`actionId` is a **journal key**, not a database id. It maps to
`ReminderAction.metadata['native_action_id']` and is used to ack the entry and to
de-duplicate replays. It must never become a `reminder_events.id` — Postgres
declares that column `uuid`. Replay de-duplication queries this metadata value;
the event primary key remains a client-generated UUIDv4.

The `action` strings must stay in sync with `ReminderNotificationAction.wire` in
`reminder_scheduler.dart` and with the literals in `ReminderGeofenceReceiver` and
`ReminderAlarmActivity`. Three places, no shared constant.

### Channel `com.sidekick/capture`

Dart side: `MethodChannelNativeCaptureApi`. Kotlin side: `MainActivity`.

Dart → Kotlin: `configureTrigger`, `setCaptureOwner`, `startCapture`,
`stopCapture`, `cancelCapture`, `getCaptureState`, `getPendingCaptureEvents`,
`ackCaptureEvent`, `retryFailedCaptures`, `isAccessibilityEnabled`,
`openAccessibilitySettings`.

`stopCapture` finalizes the recording into the durable pending journal.
`cancelCapture` removes the active journal entry and deletes its local audio.

Kotlin → Dart (invoked on the channel): `recordingStarted`, `recordingLevel`,
`captureSaved`, `captureError`.

`ownerId` is the signed-in user id. Native capture events are owner-scoped so a
recording made under one account is never ingested under another.

### Durable native state (SharedPreferences)

`sidekick_reminder_runtime`:

| Key | Holds | Written with |
|---|---|---|
| `geofences` | registered proximity alerts, for reboot restore | `.apply()` |
| `time_reminders` | scheduled alarms, for reboot restore | `.apply()` |
| `actions` | the action journal | `commitChecked` |
| `action_seq` | journal sequence counter | `commitChecked` |
| `int_ids` / `int_seq` | allocated notification ids and request codes | `commitChecked` |
| `dwell` | in-progress dwell timers | `.apply()` |

`sidekick_capture_journal` — the native capture store.
`SidekickAccessibilityService.TRIGGER_PREFS` — the hardware trigger config.
`sidekick_reminder_sounds` — selected sound id and imported file display name;
audio bytes remain device-local under `files/reminder_sounds/`.

The `.apply()` rows are the ones reboot restoration depends on, and they are also
the ones written outside `prefsLock`. Treat that as a known inconsistency, not as
the pattern to copy.

### Intents

`ReminderGeofenceReceiver` actions:
`com.sidekick.sidekick.reminder.ACTION` (a notification button),
`…DWELL_ELAPSED`, `…TIME_ELAPSED`.

Extras: `reminder_id`, `title`, `details`, `transition`, `dwell_seconds`,
`action`, `notification_id`, `edit_reminder_id`.

Intents are disambiguated by a `sidekick://…` data URI (`geofence/<id>/<t>`,
`time/<id>`, `dwell/<id>`, `notification/<id>/<action>`) because Android matches
PendingIntents by action + data + component, **not** by extras. Two reminders
sharing a request code would otherwise overwrite each other's alarm.

**Currently unread:** the `reminder_payload` extra and `edit_reminder_id` are set
on the launch intent but nothing on either side reads them — there is no
`onNewIntent` handling. Tapping a place notification opens the app and nothing
else happens.

---

## 2. Dart ↔ Postgres

`supabase/migrations/0001_poc_baseline.sql` is the authority. Column names are
identical on both sides (snake_case); the sync engine relies on that and does no
mapping.

### Type mapping

| Postgres | Drift | Note |
|---|---|---|
| `uuid` | `text()` | **drift will not validate this.** Every `id` and `*_id` must be a real UUIDv4 |
| `timestamptz` | `dateTime()` | stored as ISO-8601 text locally; Postgres accepts it directly |
| `jsonb` | `text()` | listed in `DriftSyncEngine._jsonColumns` and decoded before push |
| `boolean` | `boolean()` | coerced to `0/1` on the way in by `_toSqlite` |
| `double precision` | `real()` | |

Local-only columns `dirty` and `synced_at` exist **only** in drift and are
stripped on push. `sync_meta` never leaves the device.

### Server-enforced rules the client must respect

- **RLS**: owner-scoped on every table. `events` and `reminder_events` have
  select+insert policies only — no update, no delete, at all.
- **Composite FKs**: `task_reminders.(capture_id, user_id)` and
  `(place_id, user_id)` reference the owner's rows, so you cannot attach another
  user's capture or place even with a valid id.
- **CHECK constraints** mirror `lib/core/domain/enums.dart`, plus:
  `captures_has_input` (`input_text` or `audio_path` must be present),
  `task_reminders_time_needs_schedule`, `task_reminders_place_needs_place`,
  `confidence` in [0,1], `radius_m > 0`, lat/lng ranges.
- **`sync_lww_guard`** rejects an update whose `updated_at` is older than the
  stored row, and clamps an `updated_at` more than 5 minutes in the future.
- **`task_reminders_capture_draft_uidx`** — one reminder per
  `(user_id, capture_id, draft_id)`.
- **`handle_new_user`** creates the `profiles` row on `auth.users` insert.

Any of these rejecting a row fails the **entire batch** for that table, and the
engine only `debugPrint`s the error. A single malformed row stops that table's
sync indefinitely.

---

## 3. Dart ↔ the model (Gemini)

Endpoint: `generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`,
key from `GEMINI_API_KEY`, model from `GEMINI_MODEL` (default
`gemini-3.5-flash`). Both are `--dart-define-from-file=.env` values, so a config
change needs a rebuild, not a restart.

### Response contract

```json
{
  "is_unclear": false,
  "raw_transcript": "verbatim transcript if audio",
  "drafts": [{
    "kind": "task_reminder",
    "title": "short action",
    "details": "optional",
    "confidence": 0.0,
    "trigger_type": "time|place",
    "scheduled_at": "ISO-8601 with an explicit timezone, or null",
    "place_id": null,
    "place_candidate": "home|work|… or null",
    "geofence_transition": "enter|exit|null",
    "dwell_seconds": 60,
    "explanation": "brief reason for the selected trigger",
    "context_items_used": []
  }]
}
```

`validateDraftJson` is a hard gate, not a parser. It rejects: a missing or
non-`task_reminder` `kind`; an empty `title` or `explanation`; a `confidence`
that is not finite in [0,1]; a `trigger_type` outside `time|place`; a
`scheduled_at` without a timezone qualifier; place fields on a time reminder or
`scheduled_at` on a place reminder; a `place_id` with no transition; a negative
`dwell_seconds`; and **any `place_id` or `context_items_used` entry that was not
present in the supplied context**. That last one is the guardrail against the
model inventing a place or hallucinating provenance — do not weaken it.

### Context contract

`AssistantContext` (12 KB budget) carries `profile`, `places`,
`active_reminders`, `recent_reminder_actions`, `recent_unclear_captures`, and a
`truncated` flag. When over budget, items are shed in that order, most recent
last: unclear captures → reminder actions → active reminders → places → profile.

Redaction is allow-list based: `allowedExternalProfilePrefs` and
`allowedExternalReminderEventMetadata`, both scalar-only. **Anything added to
this payload must go through an allow-list.** Unclear captures expose only a
categorical `reason`; neither `captures.error`, `captures.metadata`, transcript,
nor persisted review-draft details may enter model context.

### Context item id prefixes

`place:<id>`, `reminder:<id>`, `reminder_event:<id>`, `capture:<id>`. These are
what `context_items_used` is validated against, and what ends up stored in
`task_reminders.ai_context` as the provenance record the POC spec requires.

### Timezone contract

Android returns the device IANA timezone through `currentTimeZoneName`. The
creation flow persists it in `profiles.prefs['timezone']` and supplies both the
zone and current local wall clock to heuristic and Gemini parsing. Parsed
`scheduled_at` values still cross storage boundaries as UTC instants.

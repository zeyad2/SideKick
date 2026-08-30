# Technical Debt

## [Phase 3] Geofence runtime uses Android proximity alerts
- Incurred: Phase 3, 2026-08-22
- What: Place reminders register through a native `LocationManager.addProximityAlert` bridge for the Android POC instead of Google Play Services geofencing.
- Risk: OEM behavior and Android deprecation quirks may make enter/exit reliability weaker than Play Services geofencing during dogfood.
- Trigger to fix: If real-device Phase 5 testing misses enter/exit events, or before productionizing place reminders.
- Estimated cost if deferred: Swap the native bridge to Play Services geofencing and add instrumentation/manual device coverage.

## [Phase 3] Real-device runtime acceptance still pending
- Incurred: Phase 3/4 remediation, 2026-08-24
- What: Automated Flutter, Gradle/Robolectric, and Supabase gates pass, including the native action journal, managed notification IDs, dwell cancellation, and schema pgTAP repeatability checks. No Android device was available in this session to verify notification delivery, geofence delivery, dwell timing, reboot restoration, or Wrong Place warm/cold edit navigation on hardware.
- Risk: OEM notification, background-location, alarm, and boot behavior can diverge from unit tests.
- Trigger to fix: First Phase 5 Android dogfood candidate.
- Estimated cost if deferred: One focused Android device pass covering time reminder, enter/exit geofence, dwell cancellation, notification actions, Wrong Place edit flow, permission denial/revocation, and reboot restore.

## [Phase 4] External AI context sharing needs consent hardening
- Incurred: Phase 4, 2026-08-22
- What: `AssistantContextBuilder` builds a bounded redacted context and Gemini prompts receive that payload for reminder drafting, but there is not yet a user-facing privacy/consent control for external AI context sharing.
- Risk: The configured Gemini path can use saved places, recent actions, and unclear capture history, but broader dogfood still needs an explicit consent/privacy gate before this becomes a real-user behavior.
- Trigger to fix: Before broader external-AI dogfood or any non-personal build, add a settings consent gate and document the exact redacted context contract.
- Estimated cost if deferred: One consent/settings gate now; harder privacy review later after UX depends on context.

## [Review] Open defects from the 2026-08-29 code review
- Incurred: logged 2026-08-29 (defects predate the review)
- What: A full-repo review found 4 critical and 6 high findings, documented with
  evidence and fixes in `docs/reports/CODE_REVIEW_2026-08-29.md`. The
  load-bearing ones: parsed reminder times are computed in UTC rather than the
  user's zone (no code writes `profile.prefs['timezone']`); native action ids are
  stored as `reminder_events.id`, which Postgres declares `uuid`, permanently
  breaking that table's sync; auto-commit activation runs only from a timer in
  the Capture screen; and raw capture text reaches the Gemini prompt through the
  overloaded `captures.error` column.
- Risk: The reminder loop is correct only for manually-picked times, in UTC, with
  the app foregrounded through the countdown. Correction-loop signal stops
  reaching the server after the first backgrounded notification action.
- Trigger to fix: Before the next dogfood round; the timezone and uuid findings
  are small and should not wait.
- Estimated cost if deferred: Dogfood data becomes unreliable (wrong times,
  missing reminder_events), so the POC evidence the phase plan depends on cannot
  be trusted.

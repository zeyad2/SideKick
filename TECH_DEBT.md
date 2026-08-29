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

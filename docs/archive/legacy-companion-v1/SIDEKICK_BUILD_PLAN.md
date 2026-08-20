# Sidekick — Build Plan & Phase Prompts (v2)

*Execution plan for building Sidekick with an AI coding agent (Claude Code). Companion to the two source-of-truth files in the repo root:*
- `SIDEKICK_BUILD_PLAN` — the product & technical plan (referenced below as `@SIDEKICK_BUILD_PLAN`)
- `DESIGN_SYSTEM.md` — the Analog Companion token set (referenced as `@DESIGN_SYSTEM.md`)

> Rename these to whatever they're actually called in your repo and update the references.

**Revision note (v2):** persona response language is now a user preference (not English-only); theming is architected for multiple themes from day 0; database schema is its own phase (P1) with a review gate; every phase now has an agent-run self-verification section that includes integration checks against prior phases. Phases renumbered P0–P12.

**Revision note (v2.1):** a write-only behavioural **event log** is added as decision **D9** (additive migration `0002_events_log.sql`, applied *after* the P1 lock) — groundwork for a *future* insights feature. **No phase in this plan builds any analytics/insights UI.** P2 owns event emission; the taxonomy + contract live in `docs/EVENTS.md`.

---

## 0. Locked decisions (read before running any phase)

These resolve contradictions in the source docs. **Every phase prompt assumes these. Where a source doc conflicts, this section wins.**

| # | Decision | Overrides |
|---|----------|-----------|
| D1 | **Framework: Flutter + Dart.** Native Android features (AccessibilityService, mic foreground service, geofencing) are the whole app; the Expo sandbox is why. | — (baked into v3 spec) |
| D2 | **UI chrome is English-only, LTR** (labels, screens, buttons, nav — no RTL, no locale files). **BUT the persona's *generated* text follows a user preference:** English (default) or Egyptian Arabic. STT/LLM already accept Arabic / Arabizi / code-switched *input* regardless. So: chrome = always English; persona output (acknowledgments, Fresh Start copy, next-action phrasing, session lines) = user's chosen response language. Collected at onboarding, stored on `profiles`, editable in settings. | **Part 5** of `@SIDEKICK_SPEC.md` (its Arabic UI copy is illustrative of persona *tone*, not literal UI — use Part 5 for layout/structure only), and my own prior "persona responds in English" note. |
| D3 | **Fonts: DM Serif Display** (italic, identity/intent moments only) **+ DM Sans** (400/500, everything else). **Bundle the weights as assets** — do not runtime-fetch from Google Fonts (the app must work offline). | Part 5's Plus Jakarta Sans + Cairo. |
| D4 | **Colors: `@DESIGN_SYSTEM.md` frontmatter is canonical**, but consumed as the **default theme**, not hardcoded values (see D8). Warm brown base (`#161311`), amber accent (`#ffb963` on-dark / `#d4860a` filled), Fresh Start teal (`#00a68e`). Part 3 = rationale, not token source. | Part 5's navy `#0F1117`. Part 3's `#D4860A` = `primary-container`, not a conflict. |
| D5 | **Data: local-first, cloud-synced.** Every write hits local SQLite (drift) first, always. Sync = dirty flag + `synced_at` + server `last_pull`, last-write-wins. Conflict resolution is a v2 problem. | — |
| D6 | **Stack contracts:** Supabase (Postgres + Auth + Storage), drift (local), Riverpod (state), Gemini Flash 2.0 multimodal (STT **and** reasoning), `flutter_local_notifications`, `geofence_service`, `flutter_foreground_task`, native Kotlin AccessibilityService. | — |
| D7 | **iOS app-blocking is deferred (P11), but the FamilyControls entitlement request is submitted on day 0** so approval runs in parallel. | — |
| D8 | **Theming is architected for multiple themes from day 0.** The Analog Companion set is the single **registered default theme**, not a hardcoded palette. Every color/type/spacing/radius value is owned by a theme object and reached only through a theme abstraction — widgets never reference raw hex or literal sizes. We ship exactly one theme now; adding a second later must be a data swap, not a widget refactor. | — |
| D9 | **Behavioural event log — write now, read later.** Every repository mutation MAY emit an immutable domain event to an append-only `events` table (migration `0002_events_log.sql`, an additive migration applied *after* the P1 lock). The read side (insights / behavioural analysis / tips) is a **future plan, deliberately unbuilt** — we log now because history cannot be backfilled. Emission is a P2 repository responsibility; feature phases add new event types to the `docs/EVENTS.md` taxonomy but build **no** analytics UI. | — |

### Cross-cutting concerns (apply to all phases)
- **Persona language:** all persona-*generated* text respects `profiles.persona_response_language` (`en` default / `ar-EG`). The Gemini prompt for any persona output must pass the target language. UI chrome ignores this and stays English. (Applies from P4 onward.)
- **User preferences:** onboarding collects preferences (persona response language now; theme once >1 exists; room to grow). Stored on `profiles` and synced. Whether prefs are discrete columns or a JSONB blob is a **schema decision made and documented in P1.**
- **Behavioural events (D9):** from P2 onward, repository mutations emit immutable domain events to the append-only `events` log (`docs/EVENTS.md`) as a **non-blocking side effect** — never awaited, never able to fail a user action. The generic repository layer (P2) emits structural events (create / status-change); feature phases emit the *semantic* ones that need context, adding each new `event_type` to the taxonomy in the same PR. **No phase builds any read/analytics/insights UI** (deferred future plan). The one signal that is otherwise unrecoverable is the selected **energy mode** — ensure `energy_mode_changed` is emitted wherever the selector or a time-rule changes it (P4/P5/P10).
- **Secrets:** Supabase anon key client-side is fine (RLS protects data). The Gemini key client-side is acceptable **for the personal build only**; before real users, proxy Gemini through a Supabase Edge Function to hide the key and cap cost. Tech debt from P4 onward.
- **Offline is not optional.** The catastrophic failure mode is "app didn't load → capture lost." Anything that can lose a capture is a bug.
- **Agent workflow:** one phase per branch. Let the agent read `@SIDEKICK_SPEC.md` / `@DESIGN_SYSTEM.md` itself. Review the acceptance checklist before merging. Don't let it pull future-phase work forward.
- **The native phases (P3, P8) require *your* hands on a real device.** Agent self-tests can't verify a lock-screen overlay on your specific OEM.

---

## 1. Phase map

| Phase | Title | Milestone |
|-------|-------|-----------|
| **P0** | Foundations, theme architecture, app shell | App runs, themed via swappable theme, empty screens |
| **P1** | **Database schema design & review** (design-only, review gate) | Schema + ERD + rationale reviewed and **locked** |
| **P2** | Data layer, sync engine, auth, preferences | Offline write → local instant → syncs up |
| **P3** | Native capture pipeline (Kotlin) — *high risk* | Triple-press → audio on disk, from lock screen |
| **P4** | Transcription → triage → inbox | **Capture loop closes** (Tier 0 core) |
| **P5** | Elastic habits, Fresh Start, reward burst, Done list | **Dogfood-able daily driver** |
| **P6** | Time-based reminders | Notification actions work without opening app |
| **P7** | Focus session / body double | Full session lifecycle (no blocking) |
| **P8** | Focus-session app blocking — Android (Kotlin) — *high risk* | **The real ADHD intervention exists** |
| **P9** | Context intelligence (geofence, stacking, next-action, avoidance, vibe) | Environment-aware |
| **P10** | Settings & configurability | Trigger/places/persona/language/sync/block-list config |
| **P11** | Focus-session app blocking — iOS (entitlement-gated) | Cross-platform blocking |
| **P12** | Hardening + 90-day freeze | Battery/permission resilience, then *use it* |

**Mapping back to your Part 7:** P0+P1+P2 = your step 1, split three ways (scaffold+theme / schema design+review / data+sync+auth+prefs). P3=2, P4=3, P5=4 (+ Done list pulled forward from step 9). P6=5, P7=6, P8=7, P9=8+9, P10=10, P11=11, P12=12.

---

## 2. Prompt template (shape of every phase prompt)

```
# Phase N — <title>

## Context — read first
Read @SIDEKICK_SPEC.md (sections ...) and @DESIGN_SYSTEM.md.
Locked decisions D1–D8 in SIDEKICK_BUILD_PLAN.md apply. Where the spec conflicts, they win.
Prereq: Phase N-1 delivered <named frozen contract>. Depend only on that; do not reach around it.

## Objective (one sentence)

## Deliverables (numbered, concrete, each independently checkable)

## Constraints & conventions (MUST / MUST NOT)

## Self-verification — YOU (the agent) run this before declaring done
- All tests you wrote for THIS phase pass.
- INTEGRATION: named assertions proving you didn't break earlier phases' frozen contracts.
- Run the FULL suite (`flutter test`), not just this phase's — a regression = you broke a prior phase = not done.
- `flutter analyze` → 0 issues.
- Re-read every acceptance line below; list any you could not verify and exactly why.

## Acceptance — HUMAN walks this
- Manual runbook: steps in the running app → expected result.
- (Native phases) real-device checklist.

## Handoff — what this phase freezes that the next depends on

## Explicitly OUT of scope (defer to Phase M)

## Before you finish
Run self-verification. Commit in logical chunks. Report unverified items honestly.
```

The two verification blocks are deliberately separate: **self-verification is automated and the agent owns it** (and must include regression + integration against prior phases); **acceptance is what a human walks**, because some things (a lock-screen overlay, a fonts-offline check, "does the burst feel like a deep breath") can't be asserted in a test.

---

# Phase prompts

## P0 — Foundations, theme architecture, app shell  *(ready to run)*

```
# Phase 0 — Foundations, theme architecture, app shell

## Context — read first
Read @DESIGN_SYSTEM.md in full and Parts 2, 3, and 5 of @SIDEKICK_SPEC.md.
Locked decisions D1–D8 apply — pay special attention to D8 (multi-theme architecture).
Greenfield Flutter project. Nothing exists yet.

## Objective
Stand up a Flutter project whose design system is a SWAPPABLE theme (Analog Companion as
the default), plus a navigable app shell of empty themed screens.

## Deliverables
1. Flutter project (latest stable, sound null safety). Android min SDK 26+. iOS target
   added but unconfigured beyond defaults.
2. Feature-first structure:
     lib/ core/ (theme, db, sync, supabase, gemini, router, utils)
          features/<name>/ (data / domain / presentation)
          app.dart, main.dart
3. Deps added + pinned: flutter_riverpod, drift + drift_flutter + sqlite3,
   supabase_flutter, go_router OR auto_route (pick, document),
   flutter_local_notifications (add now, use later). No capture/geofence native deps yet.
4. THEME ARCHITECTURE (D8):
   - Define an AppTheme value type holding a full token set: ColorScheme + all custom
     tokens (surface stack, primary/on-primary/primary-container, secondary=teal,
     tertiary=blue, error), TextTheme (DM Serif Display italic for display/headline;
     DM Sans 400/500 for body/label), spacing (4px unit), radii (card 12 / input 8 /
     pill 999).
   - A theme registry/provider holding a MAP of named themes with exactly ONE entry:
     'analog_companion', built entirely from @DESIGN_SYSTEM.md frontmatter. The active
     theme is selectable in principle (Riverpod provider), defaulting to analog_companion.
   - Widgets access tokens ONLY through the theme abstraction (e.g. context extension or
     an InheritedWidget). No widget anywhere references a raw hex or a literal size that
     a theme should own. Adding a second theme must require zero widget changes.
   - Bundle DM Serif Display + DM Sans weights as ASSET fonts (pubspec). Do NOT use the
     google_fonts runtime fetcher (offline-first).
5. Shared widgets, styled via theme tokens only, no business logic:
   PillButton (primary amber-fill/dark-text; secondary cream-outline no-fill),
   SurfaceCard (raised surface token, 1px rgba(255,255,255,0.06) border, 12px radius,
   20px padding, NO shadow — tonal depth only), PersonaOrb (44px amber circle, isPulsing
   flag, static for now), ParticleBurst (STUB with intended API; real impl in P5).
6. App shell: bottom nav (Inbox / Habits / Focus / Settings) → empty screens each showing
   only a DM Serif Display italic title + PersonaOrb, so the theme is visibly exercised.
7. Env handling: --dart-define config class for SUPABASE_URL / SUPABASE_ANON_KEY /
   GEMINI_API_KEY. Commit .env.example, gitignore the real one. No hardcoded secrets.
8. flutter_lints (or very_good_analysis) + analysis_options.yaml, clean tree.
9. Tests: (a) a widget test that pumps the shell and asserts the themed Scaffold + nav
   render; (b) a test asserting that swapping the active theme provider to a second
   (throwaway) theme changes rendered colors WITHOUT touching any widget — this proves
   D8 holds.

## Constraints & conventions
- MUST: dark theme only; no RTL; no Arabic strings in UI chrome; LTR everywhere.
- MUST: no shadows anywhere — depth = tonal layers + 1px outlines.
- MUST: serif only for identity/intent moments; DM Sans for all functional text.
- MUST: every visual value comes from the active theme; grep the tree for raw hex → none
  outside the theme definitions.
- MUST NOT: implement any feature logic, DB tables, auth, or native code.

## Self-verification (agent)
- Both widget tests pass; the theme-swap test proves widgets are theme-agnostic.
- `flutter analyze` → 0 issues; full `flutter test` green.
- Grep confirms no raw hex/literal radii/spacing outside core/theme.
- No prior phases exist yet, so no regression surface — state this.

## Acceptance (human)
- App launches to Inbox shell; nav switches 4 empty themed screens.
- Titles are DM Serif Display italic; body/labels DM Sans. Background is warm brown, not
  navy. PersonaOrb is amber + circular.
- Fonts render in airplane mode on first launch.

## Handoff (frozen)
- Theme accessor pattern + AppTheme token API (document exact names).
- Named route constants for the 4 destinations.
- core/ layout + env/config class.
- PillButton / SurfaceCard / PersonaOrb / ParticleBurst signatures.

## Out of scope
Auth, database, sync, capture/native code, real ParticleBurst.

## Before you finish
Write docs/CONVENTIONS.md (theme accessor, routing choice, folder rules, env, D8 rule).
```

---

## P1 — Database schema design & review  *(ready to run — DESIGN ONLY, hard review gate)*

```
# Phase 1 — Database schema design & review

## Context — read first
Read Part 2 (backend / local-vs-cloud / sync strategy) and Part 6 (schema) of
@SIDEKICK_SPEC.md. Locked decisions D2, D5, D8 and the "User preferences" cross-cutting
note apply. Prereq: P0 merged.

This is a DESIGN + REVIEW phase. You produce the authoritative schema and STOP for human
review. You write ZERO implementation code (no drift, no repositories, no auth). Getting
the schema wrong fails every later phase, so it is isolated and reviewed before anything
is built on it.

## Objective
Produce the authoritative, reviewed, LOCKED database schema — Postgres/Supabase migration
+ ERD + written rationale — that all data work builds against.

## Deliverables
1. Full annotated Supabase migration (supabase/migrations/). Start from Part 6's schema,
   then adjust for:
   - profiles: persona_response_language (default 'en', CHECK IN ('en','ar-EG')),
     theme (default 'analog_companion'), + a DELIBERATE decision on how preferences grow
     (discrete columns vs a JSONB `prefs` blob) — decide and justify in SCHEMA.md.
   - Sync columns on every syncable table: `dirty` (bool) and `synced_at` (nullable),
     and decide where the client's `last_pull` cursor lives.
   - Indexes for the ACTUAL query patterns: inbox by (user_id, status, captured_at desc);
     habit_completions by (habit_id, completed_at); reminders by (place_id) and (habit_id/
     task_id); focus_sessions by (user_id, started_at); tasks by (user_id, status).
     List each index and the query it serves.
   - Explicit FK ON DELETE behavior per relationship (cascade vs set null) — chosen, not
     defaulted-by-accident.
   - Complete CHECK/enum sets (e.g. captures.llm_type includes 'uncategorized';
     focus_sessions.blocking_mode IN ('soft','hard'); reminder_type, geofence_transition).
   - RLS on EVERY table (auth.uid() = user_id).
2. ERD as mermaid or dbml, committed to docs/, showing all tables + relationships.
3. docs/SCHEMA.md — rationale for every non-obvious choice: why captures is separate from
   tasks/notes/habits; JSONB for suggested_schedule / frequency_config / captures_during;
   the prefs storage decision; cascade choices; how block_list stores Android package name
   vs iOS opaque token in one column; how focus_sessions.captures_during (JSONB array of
   capture ids) will be read; the exact sync-column semantics (when dirty is set/cleared,
   how last_pull advances, how last-write-wins is decided).
4. A migration-applies test: apply to a throwaway Supabase/Postgres, confirm clean apply +
   RLS denies cross-user reads.

## REVIEW GATE — end the phase here
After producing the migration + ERD + SCHEMA.md, STOP and present them for human review.
Do NOT write drift code, repositories, sync, auth, or UI. This phase's output is a LOCKED
schema, nothing more.

Include a human review checklist:
- Does every screen in Part 5 have every field it needs a home in the schema?
- Is the inbox list query indexable as written?
- Does last-write-wins have a timestamp on every syncable table?
- Are all enums/CHECKs complete for the features that use them?
- Is any preference we intend to collect missing a column/blob path?
- Any table that should cascade-delete but doesn't (or vice-versa)?

## Self-verification (agent)
- Migration applies cleanly to a fresh DB; a scripted check confirms RLS blocks another
  uid's SELECT.
- ERD matches the migration exactly (no table/column in one but not the other).
- Every CHECK/enum lists all values the spec's features imply.
- (No implementation to regression-test; state that this is a design phase.)

## Acceptance (human)
Schema reviewed against the checklist and approved; ERD readable; SCHEMA.md explains the
non-obvious; migration applies clean.

## Handoff (frozen)
The LOCKED schema: migration + docs/SCHEMA.md + ERD. P2 implements strictly against this.
Post-lock changes require a NEW migration, never an edit to the locked one.

## Out of scope
drift code, repositories, sync engine, auth, ANY UI. Design only.
```

---

## P2 — Data layer, sync engine, auth, preferences  *(ready to run)*

```
# Phase 2 — Data layer, sync engine, auth, preferences

## Context — read first
Read docs/SCHEMA.md + the locked P1 migration (`0001`), the additive events migration
(`0002_events_log.sql`) + docs/EVENTS.md, and Part 2 of @SIDEKICK_SPEC.md.
Locked decisions D2, D5, D6, D9 and the persona-language + preferences + behavioural-events
cross-cutting notes apply. Prereq: P1 schema is LOCKED. Implement strictly against it; if you
find a schema gap, STOP and raise it — do not silently alter the schema. (`0002` is additive
and already merged post-lock; mirror it too.)

## Objective
Build the local-first data layer, sync engine, auth, and preferences, exposing stable
repository interfaces that ALL later feature phases depend on — so no feature phase ever
touches drift or Supabase directly.

## Deliverables
1. drift schema mirroring the LOCKED P1 schema (`0001`) AND the additive `events` table
   (`0002`) — same table/column names, including the `dirty` / `synced_at` local columns.
2. Auth: Supabase email OTP (pick magic-link vs 6-digit, document). Themed login screen
   (DM Serif title). Session persists across restarts. App opens offline with a cached
   session WITHOUT blocking the UI on a network auth check.
3. Preferences / onboarding: after first login, a minimal onboarding step collecting
   persona_response_language (English default / Egyptian Arabic). Store on profiles.
   Read into a Riverpod provider available app-wide. (Theme selection UI deferred until
   >1 theme; store 'analog_companion' for now.)
4. Repository interfaces (domain), one per entity, each exposing:
   - Stream<List<T>> watchAll()/watchWhere(...) reading LOCAL drift
   - create/update/delete writing LOCAL-FIRST (write drift, mark dirty, return immediately
     — never await network)
   Interfaces: Profile, Captures, Tasks, Notes, Habits, HabitCompletions, VibeChecks,
   Places, Reminders, BlockList, FocusSessions.
   - PLUS an append-only **Events** log (D9): an `EventsRepository` exposing `append(event)`
     ONLY (immutable — no update/delete) writing LOCAL-FIRST + marking dirty like any other
     row. **No** read/query/analytics API now (the read side is a deferred future plan; a
     minimal `getSince` for tests is fine). Provide the event-emission hook the other
     repositories call — write-only, non-blocking, and unable to fail the mutation it rides
     on. The generic repository layer should emit the structural events (create /
     status-change) itself; feature phases add semantic ones later. Wire nothing that READS
     events into UI.
5. Sync engine (core/sync):
   - On connectivity regained + on app foreground: flush dirty rows to Supabase, clear
     dirty + set synced_at on success.
   - Pull rows updated since last_pull; upsert into drift; advance last_pull. LWW on
     conflict. connectivity_plus. Behind an interface (stub-able in tests). Failures
     silent + retried, never blocking UI.
   - `events` sync like any other syncable table, but push is INSERT-ONLY (immutable rows,
     client-generated ids) — so no LWW conflict arises; pull advances `last_pull` the same way.
6. Pending-audio queue: concrete impl of the device-storage queue interface (dir strategy)
   for P3/P4 to fill.
7. Riverpod providers exposing each repository + the preferences provider.

## Constraints & conventions
- MUST: every write local-first and synchronous-feeling; no UI action awaits network.
- MUST: feature code depends ONLY on repository interfaces — drift + Supabase types never
  escape data/. 
- MUST: RLS-verified isolation; a user cannot read another's rows.
- MUST: events are append-only (never updated/deleted by app code) and emitted as a
  non-blocking side effect that can never fail a user mutation (D9).
- MUST NOT: alter the locked schema (raise gaps instead); build feature UI beyond login +
  onboarding; implement conflict resolution beyond LWW; build ANY events read / analytics /
  insights surface (write-only groundwork per D9).

## Self-verification (agent)
- Repository + sync-logic tests pass (in-memory drift + stubbed sync).
- INTEGRATION with P0: login + onboarding render through the P0 theme accessor, using
  PillButton/SurfaceCard — no raw styling.
- INTEGRATION with P1: drift column names match the locked migrations exactly — `0001` AND
  the `events` table from `0002` (a test/grep diff); a scripted RLS check denies cross-user
  reads (incl. `events`).
- EVENTS (D9): an append writes a row + marks it dirty; a stubbed-sync flush pushes it
  insert-only; no code path updates/deletes an event; no events read surface exists.
- `flutter analyze` 0 issues; FULL `flutter test` green.

## Acceptance (human)
1. Log in → onboarding asks persona language → choice saved. Kill + reopen offline → still
   logged in, no spinner-lock, preference intact.
2. Create a task via a repo (debug button ok) in airplane mode → appears instantly in a
   watchAll() stream. Re-enable network → row appears in Supabase, dirty cleared,
   synced_at set.
3. RLS: a second user (or a direct SQL check as another uid) cannot read the first's rows.

## Handoff (frozen)
Repository interface signatures (THE contract — freeze). Riverpod providers. Preferences
provider (esp. persona_response_language). Pending-audio queue interface + directory.
Auth/session accessor. **`EventsRepository.append` + the event-emission hook** (D9) — the
write-only API later phases call to log domain events.

## Out of scope
Capture, transcription, feature screens beyond login/onboarding, Gemini, native code, and
ANY insights/analytics reading of the events log (future plan — write-only now).

## Before you finish
Write docs/DATA_CONTRACT.md (repository signatures + local-first + sync semantics).
```

---

## P3 — Native capture pipeline (Kotlin) — HIGH RISK

*The make-or-break feature. Isolate it: prove capture → audio-on-disk with **no** Gemini call.*

- **Objective:** Global hardware-key trigger fires a mic recording from any screen incl. locked, saves audio to device storage *before any network*, surfaces recording + processing overlays.
- **Deliverables:** Kotlin `AccessibilityService` (~50 lines) intercepting a configurable key gesture (default triple-press Vol Up) → method channel to Flutter; mic foreground service (`flutter_foreground_task`) that records and writes the audio file the instant recording stops, enqueuing via the P2 pending-audio queue + a `captures` row; Screen 1 (recording overlay: blur, pulsing 80px amber mic, live amber waveform, count-up timer, single "Done" pill, English copy); Screen 2 (processing: breathing PersonaOrb as the loading indicator, cycling status text — *simulate* the transition, no Gemini yet); permission flows (accessibility deep-link, mic, FG-service notification).
- **Key constraints:** audio persists to disk **before** any async work; capture survives an app kill mid-flow; no capture is ever lost. Note OEM battery-killer risk.
- **Self-verify (agent):** Dart-side tests for the capture-event contract (file path + `captures` row id) pass; INTEGRATION — the row is written through the P2 CapturesRepository (not raw drift); full suite green; **flag that native trigger behavior is NOT self-verifiable — see device checklist.**
- **Acceptance — real-device checklist (you):** trigger from lock screen; from inside another app; from backgrounded. Audio lands on disk each time. Force-kill mid-record → audio still saved.
- **Handoff (frozen):** the "captured audio file path + `captures` row id" event/stream contract + the method-channel name. **Out of scope:** Gemini, categorization, inbox, triage.

---

## P4 — Transcription → triage → inbox  *(SHIP milestone: capture loop closes)*

- **Objective:** Turn a captured audio file into a categorized, editable inbox item via Gemini.
- **Deliverables:** Gemini Flash 2.0 multimodal client → strict JSON `{ type, title, details, suggested_schedule, raw_transcript }`, handling Egyptian Arabic / Arabizi / code-switch input and returning English fields; robust parsing (strip fences), retry, offline-queue-with-retry (never lose a capture on API failure); Screen 3 (Inbox home: energy-mode selector Low/Normal/Charged one-tap, capture cards, FAB secondary trigger); Screen 7 (triage sheet: dimmed transcript, Task/Note/Habit pills with AI suggestion pre-selected, editable title, schedule chip for tasks, mini/normal/mega for habits, Save); save routes to the correct typed table via P2 repositories. **Events (D9):** emit `capture_created`, `capture_triaged` (resulting type + latency), `capture_discarded`, and `energy_mode_changed` when the inbox energy selector changes — via the P2 write-only hook.
- **Key constraints:** mis-sorts cheap to fix; transcript always visible; Gemini key = tech debt (proxy before real users).
- **Self-verify (agent):** client returns valid parsed JSON on a fixture audio; a malformed-response fixture is handled without crash; INTEGRATION — a save lands in the right P2 repository and survives restart; INTEGRATION — an API-failure fixture leaves the capture queued, not lost; full suite green.
- **Acceptance (human):** speak a mixed Arabic/English thought → transcript → suggested category → override + edit → saved as the right record; API failure → capture retries, not lost.
- **Handoff (frozen):** typed records stream to inbox; the Gemini client interface (reused in P9). **Out of scope:** habit completion, reminders, focus.

---

## P5 — Elastic habits, Fresh Start, reward burst, Done list  *(dogfood milestone)*

- **Objective:** Habits completable with the signature reward moment; engineer the restart; mirror progress honestly. **First persona-text phase — persona copy honors `persona_response_language` (D2 cross-cutting).**
- **Deliverables:** Mini/Normal/Mega with suggested level from energy mode; completing any level = full win → `habit_completions` (level + energy_mode); Screen 4 real **ParticleBurst** (replaces P0 stub — ~10 amber dots ~4–5px, short arcs, 400ms fade, fires *before* other UI updates; orb pulses once; rotating warm acknowledgment fades in ~1s, **in the user's persona language**; non-blocking); Screen 5 Fresh Start (missed-habit → teal, orb teal-mode, zero shame, 3-day Mini reset run; `reset_active` + `reset_started_at`; **no** missed-day notification, **no** streak-loss counter; **persona copy honors language pref**); Done list (reverse-chron, date-grouped, factual — not a streak). **Events (D9):** emit `habit_completed` (level + energy_mode) and `fresh_start_entered`; emit `energy_mode_changed` if energy is set on this surface too.
- **Key constraints:** no shame/streak/guilt framing anywhere; burst is "a deep breath, not a party"; Mini = the defined win.
- **Self-verify (agent):** completion + Fresh-Start logic tests pass; INTEGRATION — completions persist via P2 repo + honor persona language (assert the Gemini call passes the pref); full suite green.
- **Acceptance (human):** complete each level → burst + logged; skip a day → Fresh Start (never a nag); acknowledgment renders in Arabic when that pref is set; Done list accurate across restarts.
- **Handoff (frozen):** completion events (reused P7/P9); energy-mode signal app-wide. **Out of scope:** reminders, geofences, focus.

---

## P6 — Time-based reminders

- **Objective:** Gentle, dismissible, question-framed reminders actionable without opening the app. **Persona copy honors language pref.**
- **Deliverables:** `flutter_local_notifications` from `reminders` (time type); actions "Done ✓" (complete without opening) + "Later" (snooze 2h); copy always a question; one-tap dismiss. **Events (D9):** emit `reminder_fired` and `reminder_actioned` (done/later/dismiss + latency).
- **Key constraints:** no coercive/non-dismissible notifications, ever (the "won't disappear" card stays dead).
- **Self-verify (agent):** scheduling + action-handler tests pass; INTEGRATION — "Done ✓" completes via the P2/P5 completion path; full suite green.
- **Acceptance (human):** fires at time; "Done ✓" completes without launching; "Later" +2h; survives reboot.
- **Handoff (frozen):** notification-action plumbing (reused by P9 geofence reminders). **Out of scope:** geofence reminders (P9).

---

## P7 — Focus session / body double

- **Objective:** Virtual co-presence giving the initiation ritual, time-bounding, task-anchoring of body doubling. **Persona lines honor language pref.**
- **Deliverables:** declare task + duration → persona acknowledges (Screen 6); blue ring timer; PersonaOrb steady "present" pulse; midpoint check-in (vibration + soft notif, one-tap ack); mid-session capture → "captured during session" queue surfacing *after*; closing acknowledgment + completion burst; ~30% Bernoulli post-session vibe check (3-tap, `vibe_checks`); `focus_sessions` row; background slowly shifts color temperature as a time cue. **Events (D9):** emit `session_started`, `session_ended` (status + actual minutes), and `vibe_check` (value).
- **Key constraints:** "End session" available but not prominent (offer, never trap); mid-session capture must not break the session.
- **Self-verify (agent):** session lifecycle + capture-queue + Bernoulli tests pass; INTEGRATION — session + vibe rows via P2 repos; capture reuses P3 pipeline; full suite green.
- **Acceptance (human):** full start→midpoint→end; mid-session capture queued + surfaced after; vibe check ~⅓ of the time; `focus_sessions` accurate.
- **Handoff (frozen):** `focus_sessions` lifecycle + `blocking_enabled`/`blocking_mode`/`block_attempts` fields ready for P8. **Out of scope:** app blocking (P8).

---

## P8 — Focus-session app blocking — Android (Kotlin) — HIGH RISK

- **Objective:** During an active session, detect a blocked app opening and overlay a block screen in real time.
- **Deliverables:** extend the **existing** P3 AccessibilityService (~60–80 lines) with `TYPE_WINDOW_STATE_CHANGED` foreground-app matching against the active session's block list (no new permissions); `block_list` table + onboarding picker (`PackageManager`, icons, search; pre-select TikTok/IG/YouTube/X; configured at onboarding, not in-session); block overlay (session timer + task + single "Go back"); soft mode default (tap back / tap end-session-unblock), hard mode opt-in (only exit = end session); `block_attempts` counter → `focus_sessions`. **Events (D9):** emit `block_attempt` (app label) alongside incrementing the counter.
- **Key constraints:** never fully traps (hard mode still ends session); hard mode opt-in (forcing it = abandonment).
- **Self-verify (agent):** block-list CRUD + counter-increment logic tests pass; INTEGRATION — reads block_list via P2 repo, writes counter to the P7 focus_sessions row; full suite green; **flag overlay behavior is NOT self-verifiable — device checklist.**
- **Acceptance — real-device checklist (you):** session with IG blocked → overlay fires within a beat; soft returns you; hard blocks till session end; timer survives your OEM battery killer; `block_attempts` increments right.
- **Handoff (frozen):** block-list config + block semantics (P10 manages list; P11 mirrors on iOS). **Out of scope:** iOS blocking (P11).

---

## P9 — Context intelligence

- **Objective:** Put cues in the world; attack initiation blockers. **All LLM-generated text honors persona language pref.**
- **Deliverables:** **geofence reminders** via `geofence_service` (Doze-aware): `places` (name/lat/lng/radius 150m default), enter/exit, dwell filter (60s) → notification (reuse P6 plumbing); **habit stacking** (LLM asks "what do you already do every day?" → stores `anchor_description`, surfaced in reminder copy); **next-action extractor** (task untouched 48h or flagged stuck → LLM single next *physical* action → `next_action`, shown until overridden); **avoidance triage** (unactioned 3+ days → sheet: Too big / Unclear / Feels scary / Just boring → routes to next-action / clarify / body-double / Mini+reward); **vibe-check analysis** (surface accumulated signal; full monthly reports deferred); minimal **Goals** (Goal Sage) — **underspecified in source; keep thin, flag for a spec pass.** **Events (D9):** emit `next_action_generated` and `avoidance_triaged` (with the chosen reason: too_big/unclear/scary/boring).
- **Self-verify (agent):** dwell-filter + routing + extractor tests pass; INTEGRATION — reminders reuse P6 notifications, LLM calls reuse the P4 Gemini client + pass persona language; full suite green.
- **Acceptance (human):** enter/exit a place → dwell-filtered reminder; stuck task → concrete next action; 3-day-old task → avoidance triage routes correctly.
- **Handoff (frozen):** places/geofence config feeds P10. **Out of scope:** monthly AI reports, multiple personas (deferred).

---

## P10 — Settings & configurability

- **Objective:** Expose config earlier phases hardcoded (Screen 8).
- **Deliverables:** Trigger config (key, press count, "Test trigger" simulating the recording overlay); **persona response language** toggle (en / ar-EG — writes the pref P2 stored); Places management (list + map thumbnail + add); Persona (Encouraging Brother selected, others "Coming soon"); Sync status (last sync, manual sync, account); Default-energy time rules; Block-list management (reuse P8 picker). *(Theme picker only if >1 theme exists — otherwise omit.)* **Events (D9):** when a time rule auto-sets energy, emit `energy_mode_changed` with `{auto:true}`.
- **Self-verify (agent):** each setting persists via the right P2 repo/pref; INTEGRATION — changing trigger config actually changes P3 capture behavior; changing language changes persona output; full suite green.
- **Acceptance (human):** Vol Down + 2 presses respected by capture; new place available to geofences; switching persona language flips generated text; default-energy rule auto-sets energy by time.
- **Handoff (frozen):** — **Out of scope:** persona variants beyond the one warm persona (Strict Boss = shame risk, opt-in only, later).

---

## P11 — Focus-session app blocking — iOS (entitlement-gated)

- **Prereq:** FamilyControls distribution entitlement (submitted day 0, D7) approved.
- **Deliverables:** `FamilyActivityPicker` (stores opaque tokens, not package names); `DeviceActivity` extension tying the shield to session start/end; `ManagedSettings` shield. **Soft mode only** — hard mode not enforceable on iOS (Screen Time permission is user-revocable; document as an Apple constraint).
- **Self-verify (agent):** picker-token persistence + shield-toggle logic tests pass; INTEGRATION — reuses P7 session lifecycle + P8 block-list model (platform='ios'); full suite green.
- **Acceptance — device (you):** on an entitled build, blocked apps show Apple's shield during a session; picker persists; shield lifts at end.
- **Handoff (frozen):** — **Out of scope:** hard mode on iOS (impossible); engineering around the revocable-permission bypass.

---

## P12 — Hardening + 90-day freeze

- **Objective:** Survive real life, then stop building and use it.
- **Deliverables:** OEM battery-killer resilience for the FG service + AccessibilityService (verify on your device; document per-OEM allow-list steps); permission re-request flows for revoked accessibility/mic/geofence; a sync-edge-case stress pass on LWW; lightweight error/telemetry so failures are visible to you.
- **Self-verify (agent):** permission-revoked-and-restored flow tests pass; a sync stress test with simulated concurrent edits behaves per documented LWW; **full suite green across ALL phases** (this is the final regression gate).
- **Then:** freeze the feature set. Use Sidekick 90 days. `block_attempts` in `focus_sessions` is your honest signal for whether blocking works — let data decide what's added next.
- **Deferred backlog (do not build before freeze ends):** streaks/XP, monthly AI reports, multiple personas, self-hosted STT, additional themes (the D8 architecture is ready when you want them).

---

## 3. How to drive this with the agent

1. One branch per phase (`phase/0-foundations`, `phase/1-schema`, …).
2. Paste the phase prompt; let the agent read `@SIDEKICK_SPEC.md` and `@DESIGN_SYSTEM.md` itself.
3. **P1 has a hard review gate** — the agent stops at a proposed schema. Walk the review checklist yourself and lock it before P2 touches it.
4. Keep frozen contracts in the repo and point later prompts at them: `docs/CONVENTIONS.md` (P0), `docs/SCHEMA.md` + the locked migration (P1), `docs/DATA_CONTRACT.md` (P2).
5. Two verification layers per phase: the agent runs **self-verification** (automated + regression + integration) before claiming done; **you** walk **acceptance** — and for P3/P8/P11, the real-device checklist is yours alone. A green suite never substitutes for a lock-screen overlay test.
6. Fight scope creep. If the agent pulls a future phase's work forward, stop it — the boundaries exist to keep each merge verifiable.
```

# Per-phase review rubrics

The specific holes to poke, per phase. Not exhaustive — the SKILL.md prime directive still
applies (attack the highest-risk surface, think three phases ahead). These are the known
traps for each phase. For any phase, the review is BLOCKED if a listed **Blocker check** fails.

---

## P0 — Foundations, theme architecture, app shell

**Blocker checks**
- Grep the whole `lib/` tree for raw hex, literal radii, literal font sizes OUTSIDE
  `core/theme`. Any hit = the theme abstraction is fake (D8 violated).
- Run the theme-swap test. If it doesn't exist, or if swapping the active theme requires
  touching a widget, D8 is not satisfied → BLOCK.
- Confirm fonts are bundled assets, not `google_fonts` runtime fetch. Launch in airplane
  mode on first run — if a font fails to load offline, BLOCK (breaks offline-first later).
- No shadows anywhere; depth is tonal + 1px outline only.
- Secrets: grep for hardcoded Supabase/Gemini keys. `.env` gitignored, `.env.example`
  present.

**Attack**
- Add a throwaway second theme with garish colors; flip the provider; confirm EVERY screen
  recolors with zero widget edits.
- Try to use a color in a shell screen without going through the theme accessor — is it
  even possible, or does the API force correctness?

**Forward risk**
- If tokens leak outside the theme, P5's Fresh Start teal / burst amber and any future theme
  become a find-and-replace nightmare. Name it now.

---

## P1 — Database schema (THE most important review — a wrong schema fails everything)

**Blocker checks**
- **Coverage:** walk every screen in Part 5 + every feature in Part 4 and confirm each field
  it needs has a column. Missing home for any field = BLOCK. (Common misses: energy_mode on
  completions, next_action/stuck_since/avoidance_reason on tasks, block_attempts on sessions,
  reset_active/reset_started_at on habits, captures_during on sessions.)
- **Sync integrity:** every syncable table has `dirty` + `synced_at`, and last-write-wins has
  a timestamp to compare on EVERY such table. A table syncable without a comparison timestamp
  = silent data loss later = BLOCK.
- **RLS on every table.** Reproduce a cross-user SELECT as a different uid → must return zero.
  If any table lacks the policy, BLOCK.
- **Indexes for real queries:** inbox (user_id, status, captured_at desc); completions
  (habit_id, completed_at); reminders (place_id), (habit_id/task_id); sessions (user_id,
  started_at). A missing index on a hot path is DEBT at minimum, BLOCK if it's the inbox.
- **Enums complete:** llm_type includes 'uncategorized'; blocking_mode soft|hard;
  reminder_type time|geofence; geofence_transition enter|exit. Incomplete enum = a feature
  can't write its state = BLOCK.
- **Preferences decision made and justified** in SCHEMA.md (discrete columns vs JSONB blob).
  If it's unresolved or undocumented, BLOCK — this is the flagged open decision.
- **ON DELETE behavior chosen explicitly** per FK (not defaulted). Ask: when a habit is
  deleted, what happens to its completions / reminders? If the answer is accidental, BLOCK.

**Attack**
- Take the three heaviest queries (inbox load, today's habits + completion state, active
  session block-list lookup) and write the actual SQL. Does the schema serve them without a
  full scan? Without a JSONB unnest on a hot path?
- Delete a habit that has completions, reminders, and a focus session referencing it. Does
  the DB do something sane, or orphan/error?
- Two devices edit the same task offline. When both sync, does LWW have what it needs to pick
  a winner deterministically?

**Forward risk**
- Every schema shortcut here becomes a migration (best case) or a data-loss rewrite (worst)
  once real captures exist. This is the cheapest possible moment to fix. Be ruthless.

---

## P2 — Data layer, sync, auth, preferences

**Blocker checks**
- drift column names match the LOCKED migration exactly (diff them). Any drift = BLOCK.
- Every write is local-first: prove a create returns and appears in a `watchAll()` stream
  with the network OFF, without awaiting anything network. If a UI write can block on the
  network, BLOCK.
- Repository interfaces are the ONLY data access — grep feature/UI code for direct drift or
  supabase types. Any leak = BLOCK (this contract protects every later phase).
- persona_response_language is collected at onboarding, stored, and exposed via a provider.
- Session survives restart AND opens offline without a blocking network auth check.

**Attack**
- Airplane-mode create → kill app → reopen offline → is the record still there and still
  dirty? Re-enable network → does it sync exactly once (no dupes)?
- Force a sync failure mid-flush → does it retry silently, or corrupt/lose the row, or spin a
  blocking error UI?
- Log in as user B → attempt to read user A's rows through a repository. Zero, or leak?

**Forward risk**
- If the repository signatures can't express the filters P4 (inbox by status) and P9
  (stuck/avoidance queries) need, every later phase will reach around the contract. Pressure-
  test the signatures against those future needs NOW.

---

## P3 — Native capture (Kotlin) — the make-or-break

**Blocker checks (device-verified by the human, reviewer confirms the code path)**
- Audio is written to disk BEFORE any network/async work. Read the code path: is there any
  `await` between "recording stopped" and "file saved"? If yes, BLOCK — a capture can be lost.
- The capture row is written through the P2 CapturesRepository, not raw drift.
- Trigger config (key/press count) is read from settings, not hardcoded.

**Attack**
- Trace: trigger fires → app is killed by the OS before transcription. Is the audio file +
  captures row already durable? Walk it line by line.
- What happens on a denied/revoked accessibility or mic permission mid-session?

**Forward risk**
- OEM battery-killer will murder the foreground service on some devices; confirm it's at
  least documented as a P12 hardening item if not handled.

---

## P4 — Transcription → triage → inbox (SHIP)

**Blocker checks**
- Malformed / non-JSON / partial Gemini response is handled without crash AND without losing
  the capture. Feed it a garbage-response fixture and watch.
- API failure → capture stays queued and retries. Reproduce with the network off.
- Save routes to the correct typed table via P2 repos.
- Gemini key exposure logged as debt (proxy before real users).

**Attack**
- Kill the app between "transcription returned" and "user triaged". Is the capture still in
  the inbox on reopen, or vaporized?
- Feed Arabic/Arabizi audio — do the returned fields come back English per D2, and does the
  raw transcript survive verbatim?

---

## P5 — Habits, Fresh Start, burst, Done list (dogfood)

**Blocker checks**
- Persona acknowledgment + Fresh Start copy honor persona_response_language — assert the
  Gemini call actually passes the pref. English-only output here = BLOCK (regressed D2).
- ZERO shame/streak/guilt framing. No missed-day notification, no streak-loss counter. Any
  present = BLOCK (this is the psychological core of the product).
- Completing any level = full win; the burst fires regardless of level.

**Attack**
- Set language to ar-EG, complete a habit — is the acknowledgment Arabic? Set it back — English?
- Miss a habit — does the app nag, or route calmly to Fresh Start? A nag is a BLOCK.

---

## P6 — Time reminders

**Blocker checks**
- Every reminder is dismissible; copy is a question, never a command. A non-dismissible /
  "won't disappear" pattern = immediate BLOCK.
- "Done ✓" completes via the P5/P2 completion path (not a parallel write).

**Attack**
- Reboot the device — do scheduled reminders survive? Fire one, tap "Done ✓" without opening
  — did it complete through the real repository, or a shortcut that skips sync?

---

## P7 — Focus session / body double

**Blocker checks**
- Persona lines honor language pref.
- "End session" exists but is not prominent (offer, never trap).
- Mid-session captures reuse the P3 pipeline and surface AFTER the session, not during.

**Attack**
- Capture mid-session — does it break the timer or leak into the session view early?
- Force-close mid-session — is the focus_sessions row left in a sane state?

---

## P8 — Android app blocking (Kotlin)

**Blocker checks (human device-verifies overlay; reviewer confirms logic)**
- Never fully traps: hard mode still allows ending the session. If there's a truly
  no-escape state, BLOCK.
- Reads block_list via P2 repo; writes block_attempts to the P7 focus_sessions row.
- No new permissions beyond the existing AccessibilityService.

**Attack**
- Start a session, open a blocked app repeatedly — does block_attempts count accurately?
- Soft vs hard mode: is hard genuinely opt-in, defaulting to soft?

---

## P9 — Context intelligence

**Blocker checks**
- Geofence reminders reuse P6 notification plumbing (not a parallel path).
- All LLM calls reuse the P4 Gemini client and pass persona language.
- Dwell filter actually suppresses drive-by triggers.
- Goals is thin and flagged (not an invented sprawling system from the underspecified source).

**Attack**
- Simulate enter-then-immediate-exit inside dwell window — does it correctly NOT fire?
- A stuck task → is the "next action" a single physical action, or a plan (spec violation)?

---

## P10 — Settings

**Blocker checks**
- Each setting persists via the correct P2 repo/pref.
- Changing trigger config changes P3 capture behavior; changing language changes persona output.

**Attack**
- Change every setting, kill app, reopen — all persisted? Does the trigger change take effect
  without a reinstall?

---

## P11 — iOS blocking (entitlement-gated)

**Blocker checks**
- Entitlement approved before this ships. Soft mode only (hard is unenforceable — must be
  documented, not silently attempted).
- Reuses P7 session lifecycle + P8 block-list model (platform='ios').

---

## P12 — Hardening + freeze

**Blocker checks**
- Permission revoke → restore flow works for accessibility/mic/geofence.
- FULL regression suite green across ALL phases — this is the final gate. Any red = BLOCK.
- TECH_DEBT.md reviewed: anything marked "trigger to fix: before freeze" is resolved.

**Attack**
- Revoke accessibility mid-use, return to app — graceful recovery or broken state?
- Replay the accumulated TECH_DEBT.md — is anything in there actually a landmine for daily use?

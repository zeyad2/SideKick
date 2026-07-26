# Tech debt ledger

Known, consciously-accepted debt and forward-looking traps. Each entry names the
phase where it bites, so it surfaces before that phase starts rather than mid-work.

---

## TasksRepository has no stale-cutoff query (bites P9)

**What.** `TasksRepositoryImpl` (`lib/features/tasks/data/tasks_repository_impl.dart`)
exposes only `watchAll()` and `watchByStatus(status)`. Neither pushes a date
predicate into SQL, so there is no way to ask for "tasks untouched since
`:cutoff`" through the repository interface.

**Why it matters.** The schema ships an index built exactly for this —
`idx_tasks_stale` on `last_activity_at` — for P9's "stale task" surfacing. With
the current interface, P9 can only load *all* tasks and filter in Dart, which
never touches the index and degrades as the task count grows.

**The trap.** This is not a P2/P3 defect — nothing today is broken, and the
frozen repository interface was deliberately not widened speculatively. The risk
is discovering it mid-P9 and being surprised.

**Fix when P9 starts.** Add a query method that pushes the cutoff down, e.g.
`Stream<List<Task>> watchStale({required DateTime before})` selecting
`WHERE last_activity_at < :before AND deleted_at IS NULL`, so the index is used.
Or make a *conscious* decision to accept in-memory filtering for the expected
task volume — but decide it explicitly, don't back into it.

## Phase 1: multi-status inbox indexing (bites P4 at large scale)

**What.** `idx_captures_inbox (user_id, status, captured_at desc)` is fully
index-ordered only for a single-status query. A multi-status inbox can require a
bitmap/sequence scan and sort.

**Risk.** Measured performance is acceptable at personal scale, but a history
above roughly 10,000 captures may make inbox latency visible.

**Fix when it bites.** Add a partial index led by `(user_id, captured_at desc)`
after the production inbox predicate is stable.

## Phase 1: tasks have no avoidance-reason field (bites P9)

**What.** The P9 avoidance flow may need a persisted reason, but the exact shape
is intentionally not frozen yet.

**Fix when P9 starts.** Choose the field shape from the final UX and add one
migration rather than speculating now.

## Phase 3: trigger preference changes are not observed live (bites P10)

**What.** Native reads the configurable gesture, but Flutter pushes profile
values only when the signed-in capture coordinator starts.

**Risk.** A P10 settings change may need a coordinator restart before it applies.

**Fix in P10.** Listen to the profile stream and call `configureTrigger` when the
gesture preference changes.

## Phase 3: foreground-task plugin uses legacy Kotlin integration (bites P12)

**What.** `flutter_foreground_task` 9.2.2 builds now but still applies the legacy
Kotlin Gradle plugin. Current Flutter builds warn that a future release will
reject this integration.

**Fix in P12.** Upgrade to a built-in-Kotlin-compatible release, or isolate a
small plugin fork if upstream has not migrated.

## Phase 3: OEM battery managers can suppress background capture (bites release)

**What.** Some Android vendors aggressively stop accessibility and foreground
services despite the platform-level implementation being correct.

**Risk.** Lock-screen/background capture reliability varies by device and cannot
be proven in host-side tests.

**Fix before release.** Run the device matrix, document vendor-specific battery
exemption steps, and surface recovery guidance without claiming guaranteed OEM
behavior.

## Phase 4: Gemini API key is shipped in the client build (blocks real users)

**What.** The build-define key is extractable from a distributed app binary even
though it is absent from source control.

**Risk.** Key abuse, quota exhaustion, and no trusted policy boundary.

**Fix before distribution.** Put Gemini behind an authenticated edge proxy with
App Check/rate limiting and remove the key from the mobile build.

## Phase 4: inline Gemini audio has a 20 MB request limit

**What.** Audio is sent inline to keep the local retry boundary atomic. Unusually
long captures remain failed and queued instead of using Gemini's Files API.

**Fix before long recordings are enabled.** Add resumable upload, file-readiness
polling, generation, and remote cleanup behind the frozen `GeminiClient`
interface.

## Phase 4: notification and mixed-language acceptance need devices

**What.** The grouped auto-commit notification, cold-launch Undo/Edit actions,
and English/Arabic mixed-audio decomposition are covered at the service and
widget boundaries, but have not been exercised end-to-end on physical Android
and iOS devices against the live Gemini API.

**Close before distribution.** Run the Phase 4 device matrix with notification
permissions granted/denied, background and terminated launches, and representative
Arabic/English recordings. Record screenshots/logs and fix any platform-specific
action routing or transcription differences before release.

## Capture decomposition: shipped end-to-end

**Done.** The rant → many-items pipeline (docs/CAPTURE_DECOMPOSITION.md, FROZEN) is
implemented through data, service, AND presentation layers, and unit/widget-tested:
- Migration `0004_capture_decomposition.sql` (additive, post-lock): `captures.proposed_items jsonb`,
  `goals.capture_id` composite SET-NULL FK + `idx_goals_capture`, drops the two 1:1
  capture CHECKs, widens `resulting_type` to include `goal`. **APPLIED to remote
  Supabase** (eu-west-1 pooler). Note: the remote `supabase_migrations` history was
  empty (0001–0003 had been applied out-of-band), so it was `migration repair`ed to
  mark 0001–0003 applied before `db push` ran 0004 — history is now clean, so future
  `supabase db push` will apply cleanly with no repair.
- Drift mirror bumped to `schemaVersion 2` with an `onUpgrade` (there was none before);
  `ProposedItem` domain model + `AutoCommit` gate; `CaptureAnalysis` unfrozen to an
  ordered draft list; Gemini array `responseSchema` + no-cross-context prompt;
  `CaptureProcessingService` stores drafts and runs the §12 auto-commit branch;
  `CaptureTriageService.saveAll` bulk-materialises idempotently; new
  `CaptureLinkedGoalsRepository.createForCapture`.
- **Multi-card review UI** (`inbox_screen.dart`): `CaptureTriageSheet` now dispatches
  to `_BulkReviewSheet` when a capture carries `proposed_items` — one editable card
  per draft, with complete task/habit/goal fields, partial Save Later re-entry,
  low-confidence guidance, and disposition tracking.
  Captures with no drafts (processed before this change) fall back to the legacy
  single-result editor so nothing already in an inbox is stranded.
- **Auto-commit safety net (§12.5):** `auto_committed_at` persists each receipt;
  the restart-safe inbox strip and one grouped OS notification offer **Undo** and
  non-destructive **Edit**. `CaptureTriageService.undoAutoCommit`
  soft-deletes the materialised children and returns the capture to `ready` — and
  RE-STAMPS the surviving drafts with fresh ids, because a soft-delete only tombstones
  the row and `createForCapture` uses `insertOrIgnore`, so re-saving under the old ids
  would silently no-op against the tombstone and never resurrect the item.

**Implementation notes for the reviewer (not bugs).**
- Auto-commit routes through a brief `processing → ready → triaged` sequence, not
  `processing → triaged` directly as §12.4 describes: `proposed_items` is persisted
  via the existing atomic `finishProcessing(ready)` checkpoint first, then the shared
  bulk path flips to `triaged`. A crash between the two leaves a reviewable `ready`
  capture (nothing lost). The observable end state matches the design; it emits an
  extra `..._status_changed` event.
- The legacy single-result `captures` fields (`llm_type/title/details/
  suggested_schedule/resulting_type/resulting_id`) are retired for the multi-item
  flow but still written by the OLD single-card triage path, which remains until the
  new UI lands.

## Auth: email/password shipped; Google + password reset still open

**Done (this session).** Auth moved from passwordless email-OTP to **explicit
email + password** with no email verification (`DATA_CONTRACT.md §5`):
- `AuthRepository` now exposes `signUpWithPassword` / `signInWithPassword`
  (replacing `sendOtp` / `verifyOtp`); `SupabaseAuthRepository` uses
  `signUp` + `signInWithPassword`. The downstream session shape is unchanged, so
  sync / RLS / the provider graph were untouched.
- `login_screen.dart` is now a single sign-in / create-account form with a mode
  toggle, client-side email + password-length validation, and friendly mapping
  of the common `AuthException`s (replaces the old raw-`toString()` display).

**Requires a dashboard setting.** Supabase **"Confirm email" must be OFF** — the
no-verification decision. `signUpWithPassword` throws a clear error if a session
isn't returned (i.e. confirmation was left on) rather than stranding the user.

**Still open — Google sign-in (designed in, disabled).** The login screen shows a
disabled "Continue with Google · Soon" button. Enabling it needs:
- `google_sign_in` (native `signInWithIdToken`, not the browser-redirect OAuth —
  avoids deep-link plumbing).
- A Google Cloud OAuth client (web client ID for Supabase + an Android client ID),
  the Android SHA-1/SHA-256 fingerprints registered (debug **and** release keys),
  the OAuth consent screen, and Supabase's Google provider enabled.
- An `AuthRepository.signInWithGoogle()` method + wiring the button's `onPressed`.
- Gate invariant to preserve (`lib/core/router/app_gate.dart`): a first Google
  sign-in creates a brand-new user (→ onboarding), but an existing user signing in
  on a new device must still take splash → pull → ready, never a spurious
  re-onboard.

**Partly shipped — password reset.** The **request** half is now wired:
`AuthRepository.sendPasswordReset` → `resetPasswordForEmail`, a
`ForgotPasswordScreen` (route `/forgot-password`, whitelisted under the login
gate and bounced to inbox under the ready gate), and a "Forgot password?" link on
the sign-in form. It always shows the same "check your inbox" message and never
reveals whether an address has an account.

**Still open — completing the reset.** Following the emailed link back into the
app to set a new password is NOT built: it needs deep-link handling (the plumbing
OTP was chosen to avoid) plus an `updateUser(password:)` "set new password"
screen. Also still needs a working outbound email channel (custom SMTP —
Supabase's built-in mailer is rate-limited and not for production) before it's
usable for real users.

**Login-screen polish still deferred.** No "resend"/countdown concepts remain
(OTP-specific), but there's still no password-strength meter and no confirm-
password field on sign-up — acceptable for the personal build.

## Forward-looking: the persona is one-way (bites whenever a conversational agent is wanted)

**What.** Nothing in the app can hold a conversation. The pipeline is
strictly one-way — audio in, structured JSON out, rows written, done:
- `GeminiClient` is `Future<CaptureAnalysis> analyzeCaptureAudio(File)` — a
  single stateless call with a strict `responseSchema`. No turns, no history, no
  free-text reply field.
- Capture processing is fire-and-forget; no session or dialogue outlives a call.
- There is no `conversations`/`messages` schema, and **no audio-output path at
  all** (no TTS, no playback surface).
- `docs/CAPTURE_DECOMPOSITION.md` §12 (auto-commit) deliberately pushes the
  opposite way: the design target is to say nothing and file correctly in silence.

**Why it matters.** "Sidekick talks back" is a plausible product direction, and
the build plan never scoped it. Discovering the gap mid-P5/P7 — the first phases
that generate persona text — would mean either a rushed retrofit or persona copy
scattered across call sites that later needs unpicking.

**What already helps.** Three pieces are unusually good groundwork:
- The persona pref layer (`profiles.persona_response_language`, D2 cross-cutting
  rule, `PersonaOrb`) — persona-generated text is already a first-class concept.
- The D9 append-only `events` log — exactly the behavioural grounding a
  responsive agent needs, and the reason it is being written before it is read.
- Drafts-as-JSON (`CAPTURE_DECOMPOSITION.md` §7) is already a "here's what I
  heard, correct me" exchange; making it spoken is a UI change, not a data-model
  change.

**Rough cost when it is built.** Its own phase, roughly P7-sized: a new additive
migration for `conversations`/`messages` (`0001` is LOCKED); a second method on
`GeminiClient` for multi-turn chat (the interface is frozen but may be *extended*
— add, never change); an audio-output dependency + playback surface; and a
conversational UI. **Do not smuggle any of this into P5.**

**Cheap action to take NOW (P5/P7).** When those phases write persona copy, route
it through a persona/response service rather than inlining prompt strings at each
call site. That costs nothing today and is the difference between later *adding* a
conversational layer and *refactoring every persona call site*.

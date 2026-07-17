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

## Auth/onboarding: login-screen UX polish (deferred)

**What.** The email-OTP login (`lib/features/auth/presentation/login_screen.dart`)
is functional but thin:
- `_sendCode` only checks the email is non-empty — no format validation, so a
  typo round-trips to Supabase before failing.
- Errors are surfaced as `error.toString()` (e.g. `AuthException: Token has
  expired or is invalid`) — raw exception text shown to the user.
- There is no "resend code" affordance or expiry messaging; the only recovery
  from an expired/mistyped code is "Use a different email" (back to step one).

**Risk.** None structural — this is chrome quality, not correctness. Bites
first-time-user polish, not data.

**Fix when auth is next touched** (likely folded into the account-model rework
below): add client-side email validation, map known `AuthException`s to friendly
copy, and add a resend button with a short countdown.

## Auth: planned move to real account creation (email/password + Google)

**What (decision, not yet built).** Today auth is passwordless email-OTP with
`signInWithOtp(shouldCreateUser: true)` — there is no distinct sign-up; a new
email is auto-provisioned on first code verification (`DATA_CONTRACT.md §5`). The
intended direction is **explicit account creation with email + password, and
possibly Google sign-in.**

**What the change touches (so it isn't underestimated):**
- **`AuthRepository` interface + `SupabaseAuthRepository`** — add
  `signUp(email, password)` / `signInWithPassword(...)` / `signInWithGoogle()`
  (or `signInWithIdToken`). This is a **frozen P2 contract** (`DATA_CONTRACT.md
  §5`); widening it is a deliberate contract amendment, not a silent edit.
- **Google login is native, not just Dart** — needs `google_sign_in` (or Supabase
  OAuth), a Google Cloud OAuth client per platform, the Android SHA-1/SHA-256
  fingerprints registered, an iOS URL scheme, and Supabase's Google provider
  enabled. This is real platform/console setup, not a code-only change.
- **Password reset flow** — a new "forgot password" path + screen, which
  reintroduces the email-link/deep-link plumbing that OTP was specifically chosen
  to avoid. Budget for deep-link handling if password reset is in scope.
- **Login/onboarding screens** — the single-step OTP screen becomes a
  sign-in/sign-up form (password field, confirm, validation, provider buttons).
- **The onboarding gate** (`lib/core/router/app_gate.dart`) — already hardened
  this session to wait for the first sync before treating a profile-less signed-in
  user as new (prevents a returning user on a fresh install from re-onboarding and
  having LWW overwrite their synced prefs). The new flows must preserve that
  invariant: OAuth first-sign-in creates a brand-new user (correct → onboarding),
  but an existing user signing in on a new device must still land on the splash →
  pull → ready path, never a spurious re-onboard.
- **Security posture** — passwords mean password strength/breach considerations
  and account-recovery abuse surface that OTP didn't have.

**Why now vs later.** The gate correctness bug is fixed regardless. This entry
exists so that when the account model is reworked, none of the above (especially
the native Google + console setup and the deep-link'd password reset) is
discovered mid-implementation. It is a **feature-sized** change, not a fix.

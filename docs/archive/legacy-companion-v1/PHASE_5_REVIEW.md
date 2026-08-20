# Phase 5 Review — BLOCK

## What I verified (reproduced, with output)

- Ground truth loaded from `SIDEKICK_BUILD_PLAN.md` P5, `DESIGN_SYSTEM.md`,
  `docs/CONVENTIONS.md`, `docs/SCHEMA.md`, `docs/DATA_CONTRACT.md`,
  `docs/EVENTS.md`, `docs/SCREENS.md`, both P5 mockups, source, and tests.
- `SIDEKICK_SPEC.md` is absent: `Test-Path SIDEKICK_SPEC.md` → `False`.
  Spec-dependent details therefore could not be validated.
- Dart analysis succeeded:
  - Command: `C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze`
  - Output: `Analyzing SideKick... No issues found!`
- Required Flutter analysis could not be reproduced:
  - `flutter analyze` → `flutter is not recognized`.
  - Repo-local `.\.tooling\flutter\bin\flutter.bat` → absent;
    `.tooling\flutter` contains only `.git` and `packages`.
  - Installed Flutter tool with `analyze --no-pub` →
    `Flutter failed to write ... C:\src\flutter\bin\cache\libimobiledevice.stamp`.
- Required full and focused Flutter tests could not run for the same SDK-cache
  permission/toolchain problem. A direct Dart test attempt correctly failed
  because Flutter tests require `dart:ui`; it is not a valid substitute:
  - `dart run test ...habit_schedule_test.dart`
  - Output: `Dart library 'dart:ui' is not available on this platform.`
- Current completion path uses the frozen P2 repository and records level,
  energy mode, dirty state, and structural event:
  - `lib/features/habits/application/habit_completion_service.dart:50`
  - `lib/features/habits/data/habit_completions_repository_impl.dart:43`
  - `lib/core/sync/syncable_tables.dart:29`
- Mini, Normal, and Mega all enter the same completion handler and repository
  path:
  - `lib/features/habits/presentation/habits_screen.dart:411`
  - `lib/features/habits/presentation/habits_screen.dart:454`
- Fresh Start persists `reset_active` and `reset_started_at`, with a three-day
  active-window calculation:
  - `lib/features/habits/application/fresh_start_service.dart:55`
  - `lib/features/habits/application/fresh_start_service.dart:62`
  - `lib/features/habits/data/habits_repository_impl.dart:119`
- Done entries are merged, sorted newest-first, converted to local calendar
  days, and date-grouped:
  - `lib/features/habits/application/habits_providers.dart:84`
  - `lib/features/habits/domain/done_entry.dart:39`
- The user-facing habits source contains no notification plumbing or
  streak-loss counter. The reference HTML itself contains forbidden “streak”
  and percentage framing, but canonical P5 source correctly did not copy it:
  - `stitch_sidekick_adhd_companion/fresh_start/code.html:172`
  - `stitch_sidekick_adhd_companion/completion_burst_state/code.html:226`

## Attacks attempted

- **Language preference propagation**
  - Held: the profile provider drives `PersonaCopyService`, the generator
    receives the enum, and the actual Gemini prompt includes `ar-EG`/`en`:
    - `lib/core/persona/persona_providers.dart:22`
    - `lib/core/persona/persona_copy_service.dart:69`
    - `lib/core/persona/persona_copy_generator.dart:42`
    - `lib/core/persona/persona_copy_generator.dart:79`
  - Broke: generated strings are accepted solely for being non-empty;
    wrong-language or shame-bearing Gemini output is queued and later rendered
    unchanged:
    - `lib/core/persona/persona_copy_generator.dart:102`
    - `lib/core/persona/persona_copy_service.dart:67`
- **Runtime ar-EG → en switching**
  - Completion reads the current service at tap time.
  - Fresh Start broke: it uses `ref.read`, caches `_line` with `??=`, and never
    invalidates it when the preference changes:
    - `lib/features/habits/presentation/fresh_start_screen.dart:29`
    - `lib/features/habits/presentation/fresh_start_screen.dart:39`
- **Missed habit / shame / nag**
  - Held in current source. Flexible cadences are deliberately never classified
    as missed; missed habits become calm in-app invitations; no notification API
    is reachable from the feature:
    - `lib/features/habits/application/habit_schedule.dart:8`
    - `lib/features/habits/presentation/habits_screen.dart:267`
    - `test/habits/no_nag_test.dart:24`
- **Completion levels and reward burst**
  - Held: all levels call the same `_complete` path and activate
    `ParticleBurst`.
  - Broke with multiple habits: pending and finished habits are reordered after
    Drift emits, while `HabitCard` instances have no stable key/index mapping.
    Stateful `_bursting` and acknowledgment state can move onto the next habit
    or disappear:
    - `lib/features/habits/presentation/habits_screen.dart:215`
    - `lib/features/habits/presentation/habits_screen.dart:234`
    - `lib/features/habits/presentation/habits_screen.dart:243`
    - `lib/features/habits/presentation/habits_screen.dart:334`
- **Acknowledgment timing**
  - Broke: `AnimatedOpacity` is inserted already at opacity `1`, so it has no
    0→1 transition. The acknowledgment appears immediately rather than fading
    in over the theme’s one-second duration:
    - `lib/features/habits/presentation/habits_screen.dart:434`
    - `lib/features/habits/presentation/habits_screen.dart:459`
- **Persistence/restart/Done ordering**
  - Static repository and grouping paths held.
  - Runtime completion/Done cold restart remains unverified. Existing
    cold-restart coverage tests Fresh Start state, not a completion reappearing
    in Done after reopening:
    - `test/habits/fresh_start_test.dart:213`
    - `test/habits/done_list_test.dart:70`
- **P2 event path**
  - Held for the current UI: P2 emits `habit_completion_created`; P5 emits
    `habit_completed` with level and energy mode through the non-blocking
    emitter:
    - `lib/features/habits/data/habit_completions_repository_impl.dart:66`
    - `lib/features/habits/application/habit_completion_service.dart:58`
- **Theme contract**
  - Broke: P5 widgets synthesize visual colors with raw alpha values and
    hardcode a tab animation duration instead of owning them in the theme:
    - `lib/features/habits/presentation/fresh_start_screen.dart:170`
    - `lib/features/habits/presentation/fresh_start_screen.dart:173`
    - `lib/features/habits/presentation/habits_screen.dart:131`
    - Contract: `docs/CONVENTIONS.md:5`

## Findings

### BLOCKERS (must fix before Phase 6)

- **[critical] Mandatory gate execution is unreproduced.** `flutter analyze` and
  the full/focused `flutter test` suites did not execute because the promised
  repo-local Flutter executable is absent and the installed SDK cache is
  unwritable. Direct Dart analysis is useful but does not satisfy the
  phase-review contract. Restore a runnable SDK and rerun every claimed check.
- **[high] Completion reward state is attached to list position, not habit
  identity.** Moving a completed item from `pending` to `finished` can transfer
  the live burst/acknowledgment state to another habit. Preserve stable identity
  and movement with keyed children plus index lookup, or keep ordering stable
  until the reward completes. Add a two-habit adversarial widget test.
- **[high] The acknowledgment does not fade.** A newly inserted
  `AnimatedOpacity(opacity: 1)` has no opacity transition. Keep the widget
  mounted at opacity zero and transition it, or use an explicit
  `FadeTransition`.
- **[high] D2 and the zero-shame invariant are not enforced on generated
  output.** The prompt carries the preference, but arbitrary non-empty model
  strings are trusted. Reject lines in the wrong script/language or containing
  prohibited framing and fall back to bundled copy.
- **[high] Fresh Start does not honor live language switching.** Its cached
  `ref.read(...).invitation()` survives provider-language changes. Watch/listen
  to the persona-language/service provider and replace the line when the
  preference changes.
- **[high] P5 violates the frozen theme contract.** Presentation code defines
  alpha-adjusted colors and a motion duration. Add semantic color/motion tokens
  to `AppTheme` and consume those tokens.

### DEBT (proceed only after blockers; log if deferred)

- Fresh Start expiry cleanup is presentation-triggered in
  `HabitCard.initState`; expired `reset_active` can remain persisted indefinitely
  when the card is not reconstructed. This risks stale state in P9/P10 sync or
  intelligence consumers.
- `habit_completed` is emitted by `HabitCompletionService`, while direct
  `HabitCompletionsRepository.create` emits only the structural event. P6’s
  notification action can silently omit semantic history if it calls the
  repository directly. Make the completion service the explicit frozen port and
  test the P6 path against it.
- Done rebuilds and sorts complete habit/task histories in memory. This is
  acceptable for initial dogfooding but needs pagination/windowing before
  long-lived history reaches P12 scale.

### NITS

- During a live Fresh Start, Mini is only suggested; Normal and Mega remain
  enabled. The missing `SIDEKICK_SPEC.md` prevents determining whether “3-day
  Mini reset run” means default-to-Mini or enforce-Mini.

## Contract integrity

- CONVENTIONS: violated by presentation-owned alpha colors/motion values.
- SCHEMA: upheld; P5 uses existing habit/reset/completion columns and no locked
  migration was edited.
- DATA_CONTRACT: upheld for current persistence and repository access; no direct
  Drift/Supabase access appears in P5 presentation/application code.
- EVENTS: upheld on the current UI path, with the P6 bypass risk noted above.
- `SIDEKICK_SPEC.md`: unavailable, limiting semantic and visual acceptance
  verification.

## Forward-risk ledger

- Semantic completion outside the repository boundary → P6 reminder “Done” and
  P9 completion reuse → formalize and test one completion port.
- Stale persisted reset flags → P9 context intelligence and cross-device sync →
  clear expiry in application/domain lifecycle, not widget initialization.
- Unvalidated generated persona text → P7 session lines and P9 next-action copy →
  centralize language/no-shame validation in `PersonaCopyService`.
- Position-bound reward state → future filtered/sorted habit views → use stable
  entity identity for transient state.
- Full-history Done merge → P12 long-term dogfood data → introduce bounded
  queries/pagination.
- Presentation-owned visual modifiers → future second theme → move every
  semantic color and animation timing into theme data.

## Verdict + required actions

**BLOCK**

1. Restore a runnable Flutter toolchain and run `flutter analyze --no-pub`, full
   `flutter test`, and focused `test/habits` plus `test/persona`.
2. Fix reward state identity and the nonexistent acknowledgment fade; add
   adversarial multi-habit tests.
3. Validate generated persona output and make Fresh Start reactive to ar-EG/en
   switching.
4. Move P5 alpha colors and animation timing into the theme contract.
5. Add a cold-restart test proving a completion and its Done grouping survive
   reopening.
6. Rerun the Phase 5 gate before starting Phase 6.

# Sidekick — Screen Reference (Stitch mockups)

Visual reference for the Stitch-generated screens in
[`../stitch_sidekick_adhd_companion/`](../stitch_sidekick_adhd_companion/). Each
screen folder holds two files:

- `screen.png` — the rendered mockup
- `code.html` — the generated HTML/CSS (a *reference* layout, not the source of
  truth; Flutter widgets in `DESIGN_SYSTEM.md` are canonical)

> **Local-only.** Like `/docs/`, the `stitch_sidekick_adhd_companion/` folder is
> gitignored and never published to the public repo. This doc lives in `/docs/`
> so the relative links resolve locally.

The **"Screen #"** column matches the numbered screens in the phase prompts of
`SIDEKICK_BUILD_PLAN.md`, so each mockup ties back to the phase that builds it.

---

## Index

| Screen # | Folder | Purpose | Built in |
|---|---|---|---|
| 1 | [`capture_overlay`](../stitch_sidekick_adhd_companion/capture_overlay/) | Recording overlay — blur, pulsing amber mic, live waveform, count-up timer, single "Done" pill. Fires from any screen incl. locked. | **P3** — Native capture pipeline |
| 2 | [`processing`](../stitch_sidekick_adhd_companion/processing/) | Post-recording processing — breathing PersonaOrb as the loading indicator, cycling status text while the capture is transcribed/triaged. | **P3 / P4** — Capture → transcription |
| 3 | [`inbox_home`](../stitch_sidekick_adhd_companion/inbox_home/) | Inbox home — energy-mode selector (Low/Normal/Charged), capture cards, secondary-trigger FAB. The app's landing shell. | **P4** — Transcription → triage → inbox |
| 7 | [`capture_review`](../stitch_sidekick_adhd_companion/capture_review/) | Triage sheet — dimmed transcript, Task/Note/Habit pills (AI suggestion pre-selected), editable title, schedule chip, mini/normal/mega, Save. | **P4** — Triage |
| 4 | [`completion_burst_state`](../stitch_sidekick_adhd_companion/completion_burst_state/) | Habit-completion reward state — the real ParticleBurst (~10 amber dots, short arcs, 400ms fade), single orb pulse, warm acknowledgment in the persona language. "A deep breath, not a party." | **P5** — Elastic habits / reward burst |
| 5 | [`fresh_start`](../stitch_sidekick_adhd_companion/fresh_start/) | Fresh Start — missed-habit recovery in teal, orb teal-mode, zero-shame 3-day Mini reset. No streak-loss counter, no nag. | **P5** — Fresh Start |
| 6 | [`focus_session`](../stitch_sidekick_adhd_companion/focus_session/) | Focus session / body double — blue ring timer, steady "present" orb pulse, midpoint check-in, background color-temperature time cue. | **P7** — Focus session |
| — | [`journal_reflection`](../stitch_sidekick_adhd_companion/journal_reflection/) | Reflection / journaling surface — post-session vibe check (3-tap) and reflective review. *Phase mapping tentative — closest fit is the P7 vibe-check flow; confirm against the real spec.* | **P7 (tentative)** |
| — | [`settings`](../stitch_sidekick_adhd_companion/settings/) | Settings — persona response language (English / Egyptian Arabic), theme, capture key gesture, and other prefs (D2/D4/D8). | **P0 shell + cross-cutting** |

---

## Notes

- Screen numbering (1–7) follows the `SIDEKICK_BUILD_PLAN.md` phase prompts; the
  two unnumbered screens (`journal_reflection`, `settings`) aren't pinned to a
  numbered slot in the plan.
- `journal_reflection`'s phase is a best guess — there is no explicit "journal"
  phase in the current build plan. If `SIDEKICK_SPEC.md` surfaces, re-check it.
- Colors and components in these mockups are illustrative. The canonical tokens
  and widget signatures are in [`../DESIGN_SYSTEM.md`](../DESIGN_SYSTEM.md).
- The screens **not yet generated** — the full auth/onboarding flow, the settings
  sub-screens, the habits/goals/focus/task detail screens, and the *future* insights
  set — have ready-to-use, design-system-matched prompts in
  [`STITCH_PROMPTS.md`](./STITCH_PROMPTS.md). As each is generated, drop its folder into
  `stitch_sidekick_adhd_companion/`, add a row to the index above, and map it to its phase.
  (The insights screens in Group D are *future-plan idea-generation* — they read from the
  `events` log and are not built by any phase in the current plan; see `EVENTS.md`.)

# Sidekick — Stitch prompts for the remaining screens

How to use: paste **§0 Style preamble** at the top of every Stitch generation, then append
one screen block. Generate in the order below — Group A (onboarding) is the live gap;
Group D (insights) is future-plan idea-generation, not a committed phase.

Already designed (don't regenerate): login, inbox_home, capture_overlay, processing,
capture_review (triage), completion_burst_state, fresh_start, focus_session, settings,
journal_reflection.

---

## §0 Style preamble (paste before every screen)

> Design a single mobile screen for **Sidekick**, a calm ADHD companion app. Aesthetic:
> "Analog Warmth" — a dimly-lit, matte, leather-notebook feel. Reject glassmorphism, neon,
> and gradients.
>
> **Colors** (dark only): background `#161311` (warm brown, never navy); cards `#252017`;
> inputs `#2E2A1F`; text cream `#e9e1dd`, muted `#d8c3af`. Primary accent **Reward Amber
> `#ffb963`** with dark text `#2b1700` on top (celebration, primary buttons, the companion
> orb). **Fresh Start Teal `#00a68e`** for new/positive momentum. Soft steel blue `#6B9FD4`
> for "in progress".
> **Depth = tonal layers + a 1px `rgba(255,255,255,0.06)` border on every card. ABSOLUTELY
> NO shadows or glows.**
> **Type:** *DM Serif Display, italic* for titles, identity moments, and empty-state prompts
> only; **DM Sans** (400/500) for all body, labels, data. Pure white is never used.
> **Shape:** cards 12px radius; inputs 8px; all buttons are pills (999px). Primary button =
> amber fill + dark text; secondary = 1px cream outline, no fill.
> **Companion Orb:** a 44px perfect amber circle, the recurring brand element.
> **Layout:** single column, 20px side margins, generous vertical rhythm (spacing in
> multiples of 4px, 24px between blocks). Icons: Material Symbols Outlined.
> **Tone:** English UI only, LTR. Warm, quiet, permanent, forgiving. **Never** any shame,
> streaks, guilt, red "you failed", or countdown pressure.

---

## Group A — Auth & Onboarding  *(build now — the live gap)*

### A1 · OTP verification
Purpose: confirm the email code after the login screen. Centered layout: small amber
companion orb up top; DM Serif italic title "Check your email"; muted line "We sent a code
to name@email.com"; a 6-digit segmented code input (6 rounded boxes, amber active caret);
amber pill "Verify"; a quiet text link "Resend code" + "Change email". No keyboard shown.

### A2 · Welcome / meet your sidekick
Purpose: the first post-login screen; set the tone, promise brevity. Large DM Serif italic
headline like "Let's set up your sidekick" with a warm one-sentence subhead ("Two quick
things, then you're in — I'll learn the rest as we go"). A pulsing 44px amber orb as the
hero. Single amber pill "Begin". Lots of breathing room; feels like opening a notebook.

### A3 · Persona response language
Purpose: choose the voice the companion speaks in. DM Serif italic title "How should I talk
to you?"; muted helper "This only changes what I say back — the app stays in English." Two
large selectable cards (12px, 1px border, amber border + faint amber tint when selected):
"English" (subtitle: Default) and "Egyptian Arabic" (subtitle: العامية المصرية, shown as a
sample of tone, not UI). Amber pill "Continue" at the bottom. Progress dots (step 1 of 2).

### A4 · Your name  *(optional step)*
Purpose: what the companion should call the user. DM Serif italic title "What should I call
you?"; a single dark rounded input (8px) with cream text; muted helper "So it feels less
like a form and more like a friend." Amber pill "Continue" + a quiet "Skip" text link.
Progress dots (step 2 of 2).

### A5 · Capture primer (teach the trigger)
Purpose: teach the core gesture before asking for permissions. DM Serif italic title
"Capture a thought in one press"; an illustrative visual of a phone with a triple-press
volume gesture and a pulsing amber mic; body copy explaining "Triple-press Volume Up from
anywhere — even locked — and just talk. I'll sort it out later." Amber pill "Set it up".

### A6 · Permissions walkthrough
Purpose: request the permissions capture needs, framed as trust not bureaucracy. DM Serif
italic title "A few keys to the workshop". A vertical list of permission rows (card each,
1px border, icon + name + one-line why + a small status pill "Grant" / amber-check "Granted"):
- **Microphone** — "so I can hear your thoughts"
- **Accessibility service** — "so the trigger works from any screen"
- **Notifications** — "gentle, dismissible nudges — never spam"
- **Battery exemption** — "so I don't get killed mid-capture" (note: most important)
Bottom amber pill "Continue" (enabled once required ones are granted); quiet "Why do you
need these?" link.

### A7 · You're all set
Purpose: close onboarding warmly. Full-bleed calm screen: a single steady amber orb; DM
Serif italic line "Okay [name], I'm here whenever you need me."; amber pill "Open Sidekick".
Zero checklist, no confetti — a quiet deep breath, not a party.

---

## Group B — Settings & preferences sub-screens  *(P10)*

### B1 · Trigger configuration
Detail screen from Settings. Title "Capture trigger". Rows: a key selector (Volume Up /
Volume Down segmented), a press-count stepper (2–4), and a prominent secondary "Test trigger"
pill that would simulate the recording overlay. Muted helper explaining the current gesture
in plain words ("Currently: triple-press Volume Up").

### B3 · Places (geofence anchors)
Title "Places". A list of saved places (card each: name, small static map thumbnail, radius
like "150m"). A secondary pill "Add a place". Empty state uses a DM Serif italic prompt
"No places yet — add the spots where reminders make sense."

### B4 · Add / edit place
A place editor: name input; a map area with a draggable pin and a radius circle; a radius
slider (default 150m) with live label; enter/exit toggle. Amber pill "Save place".

### B7 · Block list management
Title "Blocked during focus". A searchable list of installed apps (icon + name + a checkbox
that fills amber when selected). Pre-selected: TikTok, Instagram, YouTube, X. Note copy:
"You'll only be nudged away from these while a focus session is running."

---

## Group C — Core feature screens not yet designed

### C1 · Habits home (Habits tab)
The dedicated Habits tab. DM Serif italic header "Rituals". A list of habit rows, each with
the title and three quick-complete chips **Mini / Normal / Mega** (Mega amber-tinted); the
chip matching current energy is subtly highlighted. Completed rows are dimmed with a teal
"Done" chip (no strikethrough shame). A secondary pill "New ritual". Bottom nav present.

### C2 · Create / edit habit
A habit editor. Title input; a "Levels" section with three editable rows Mini / Normal / Mega
each with a short description input (e.g. Mini = "one push-up"); a frequency selector (Daily /
N per week / specific weekdays as selectable day pills); an optional "Anchor" input ("what do
you already do every day?" for habit stacking); optional link-to-goal row. Amber pill "Save".

### C3 · Task detail
A single task view. DM Serif italic title = task title (editable on tap); details text; a
schedule chip; a highlighted amber "Next physical action" line when present; primary amber
pill "Mark done"; secondary "Snooze". A quiet "This feels stuck" text link that opens C4.

### C4 · Avoidance triage sheet
A bottom sheet (rounded top, card surface). DM Serif italic prompt "What's making this hard?"
Four large tappable option cards, zero judgment: **Too big**, **Unclear**, **Feels scary**,
**Just boring**. Muted footnote "No wrong answer — I'll help based on what you pick." Each
routes elsewhere (don't show the destination).

### C5 · Done list
Title "Done". A reverse-chronological, date-grouped list (date subheads in DM Serif italic
like "Today", "Yesterday"). Each row: a small teal or amber dot, the item, a timestamp, and
a tiny tag (habit level or "task"). Purely factual reflection — explicitly NOT a streak or
score. Calm, lined-paper dividers.

### C6 · Goals list  *(Goal Sage — thin)*
Title "Goals". A list of goal cards (title in DM Serif italic, a one-line "why", a small
status chip active/paused, optional target date). Secondary pill "New goal". Empty state:
DM Serif prompt "What are you moving toward?"

### C7 · Goal detail
A goal view: DM Serif italic goal title; the "why" as a warm quoted line; status control;
optional target date; then two sections "Tasks" and "Habits" listing the items laddering up
to this goal (compact rows). Deliberately simple — no progress bars or milestones yet.

### C8 · Focus session setup
Pre-session screen. DM Serif italic "What are we working on?"; a task input or pick-a-task
chip; a duration selector (25 / 45 / 60 / custom as pills); a "Block distractions" toggle with
a soft/hard sub-choice (soft default; hard labeled "opt-in"); a big amber pill "Start
session". Companion orb present, calm.

### C9 · Focus midpoint check-in
A soft overlay over the running session. Gentle DM Serif italic line "Halfway there — still
with me?"; a single amber "I'm here" pill; subtle, dismissible, non-blocking. Background is
the dimmed focus session.

### C10 · Focus session summary
Post-session screen. DM Serif italic warm closing line ("Nice work — 45 minutes with me.").
A factual summary card (duration, task). If any thoughts were captured mid-session, show a
"Captured while you focused" list to triage now. Amber pill "Done". No score.

### C11 · Vibe check (3-tap)
A minimal post-session prompt (~⅓ of the time). DM Serif italic "How'd that feel?" and three
large tappable faces/dots representing a 3-point scale (rough → okay → good), amber on select.
One tap dismisses. No numbers, no analysis shown.

### C12 · Block overlay (during session)
The screen shown when a blocked app is opened mid-session. Calm, full-screen, NOT punitive:
the companion orb; DM Serif italic line "Still in a focus session"; the current task + a live
session timer; a single "Go back" pill. In hard mode, add a small muted "End session to
unblock" text link. Warm brown, never an angry red wall.

### C13 · Reminder notification (design reference)
A reference sheet showing the system-notification design: the app icon, a **question-framed**
title (e.g. "Feeling up to a quick tidy?"), and two actions **Done ✓** and **Later**. Show
one time-based and one geofence variant ("You're near the pharmacy —…"). Gentle, always
dismissible; no "won't disappear" nag.

---

## Group D — Insights & analytics  *(FUTURE plans — mock to generate ideas, not a committed phase)*

> These read from the append-only event log (`docs/EVENTS.md`). Frame every insight as *the
> app gently noticing a pattern to help* — never a grade, streak, or "you've been avoiding
> this." Explore freely; nothing here is locked.

### D1 · Insights home
Title in DM Serif italic "Patterns I've noticed". A calm feed of insight cards (each: an icon,
a one-line observation in warm plain language, and a soft supporting stat). Examples: "You
capture most thoughts around 10pm", "Mini wins carried you through low-energy weeks". A small
period switcher (This week / This month). No dashboards-of-doom, no dense charts up front.

### D2 · Energy trajectory
A gentle visualization of energy over time: a smooth line/area (amber→teal) across a day or
week showing Low/Normal/Charged, with soft annotations ("You're usually Charged before noon").
Muted, editorial, not a clinical graph. Pair it with a one-line takeaway in DM Serif italic.

### D3 · Weekly reflection
A warm, narrative "week in review": DM Serif italic header with the date range; 3–4 short
observation cards (captures triaged, rituals kept, a focus highlight, an energy note) written
like a companion talking, not a report. A closing encouraging line in the user's persona tone.
Zero red metrics, zero "missed" counts.

### D4 · Insight detail / tip
Tapping an insight opens a fuller card: the observation, a tiny bit of the supporting pattern,
and a single gentle, optional suggestion ("Want me to pre-set Low energy after 9pm?") with an
amber "Try it" pill and a quiet "Not now". Always a suggestion, never an instruction.

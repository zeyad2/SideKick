# Sidekick — Capture Decomposition (rant → many items)

**Status:** FROZEN — design locked. Implement against this; changes require a doc
edit + note, not a silent code divergence. Migration `0004` implements it.

## 1. The problem

A "capture" (rant) is a brain-dump that usually contains **several distinct
things**: a few tasks, maybe a habit, occasionally a goal, sometimes a stray
idea. The whole promise is *"you say a lot of things and they get broken down
**for you**."*

Today the pipeline is **one capture → one item**. Gemini is forced to compress a
multi-thing rant into a single title/type/details, and triage lets you save
exactly one typed record. A five-item rant collapses into one card that says
"schedule for later." That is the opposite of the product promise — the data
model has nowhere to put the other four things.

**Goal of this work:** one rant → **N proposed items**, each independently typed
and editable, approved in a single low-friction review pass.

## 2. Taxonomy — the one rule the classifier *and* the UI share

Every extracted item is exactly one of four **kinds**. The decision rule (frozen
so the Gemini prompt and the type-switch UI agree):

- **Is there a concrete action?**
  - **No** → an outcome you work *toward* over time? → **goal**. Just an
    idea/reference? → **note**.
  - **Yes** → does it *repeat as a behavior*? → **habit**. One-and-done? →
    **task**.

| Kind | One-liner | Has a "done"? | Example |
|---|---|---|---|
| **task** | A discrete completable action | Yes, terminal | "Call the dentist tomorrow" |
| **habit** | A recurring behavior; success = consistency | No, streak | "Start stretching after lunch" |
| **goal** | An outcome tasks/habits ladder up to; you don't *do* it | No, lifecycle | "Get back in shape" |
| **note** | A thought/reference with no action | n/a | "Idea: dark-mode onboarding" |

The classifier is **conservative on goals** — a typical rant is mostly tasks,
occasionally a habit, rarely a goal. Over-eager goal detection reads as wrong.

## 3. The flow

```
rant (audio) → Gemini → N draft items (JSON on the capture)
   ├─ auto-commit-eligible? (see §12) ──→ materialize all N immediately,
   │                                       capture → `triaged`, fire "Added" undo
   └─ otherwise ──→ user reviews a list of cards (switch kind / edit / drop)
                     → "Save all" → N real rows, each linked to the capture
                     → capture → `triaged` once every draft is dispositioned
```

**Key property:** in the **review** path, drafts live as JSON on the capture and
are **not yet real rows** — nothing is written to `tasks`/`habits`/… until the
user approves; this is what makes editing and kind-switching free (see §7). The
**auto-commit** path (§12) skips review entirely for a narrow, safe class of
captures; `proposed_items` is still written first, as the audit trail Undo/Edit
read from.

## 4. The draft contract (`captures.proposed_items`)

A new nullable JSONB column `proposed_items` on `captures` holds an **ordered
array** of draft objects. It mirrors the schema's own JSON-blob precedent
(`suggested_schedule`, `focus_sessions.captures_during`): read whole by the
client, never queried in SQL.

Each draft object — a flat union so the Gemini `responseSchema` stays simple.
`kind` + `title` are always present; the rest are populated per kind:

```jsonc
{
  "kind": "task | habit | goal | note",   // required
  "title": "string",                      // required
  "details": "string | null",             // shared, optional
  "confidence": "high | low",             // model's self-report; feeds §12 auto-commit gate

  // --- task only ---
  "schedule": {                           // null if none suggested
    "date": "2026-07-19 | null",          // ISO date
    "time": "09:00 | null"                // HH:mm, 24h
  },
  "location": {                           // null — DESIGNED-FOR-FUTURE (see §9)
    "name": "string",
    "transition": "enter | exit"
  },
  "reminder": false,                      // create a reminder row on approval?

  // --- habit only ---
  "anchor": "after lunch | null",         // existing routine it attaches to
  "cadence": {                            // default { type: "daily" }
    "type": "daily | weekly | custom",
    "days": ["mon", "wed"],               // for weekly/custom; else omit
    "per_week": 3                         // optional
  },
  "level": "mini | normal | mega",        // default "mini"

  // --- goal only ---
  "why": "string | null",                 // motivation (Goal Sage context)
  "target_date": "2026-12-01 | null"      // goals need not be time-boxed
}
```

The full rant transcript stays at capture level (`captures.raw_transcript`). The
initial `confidence` value is Gemini's self-report. The client may only downgrade
`high` to `low` after an explicit user action rejects automatic handling (Undo,
partial Save Later, or defer-all). That persisted downgrade means "manual review
required" and prevents restart/checkpoint recovery from auto-committing a draft
the user already deferred; the client never upgrades confidence.

The capture's **legacy single-result fields** (`llm_type`, `title`, `details`,
`suggested_schedule`, `resulting_type`, `resulting_id`) are **retired** for the
multi-item flow — kept as columns (the `0001` schema is LOCKED, can't drop) but
no longer the triage source of truth. Child links live on the children
(`tasks/notes/habits.capture_id`, and new `goals.capture_id`).

## 5. Per-kind review fields & screen

A rant produces a scrollable list of draft cards, each independently typed:

```
  "Shape 4 things"                     ← from your rant
  ┌─────────────────────────────────┐
  │ [Task ▾]  Call the dentist    ✕ │  ← kind selector morphs the card
  │ details…                         │
  │ 📅 Tomorrow 9:00   📍 Add place  │  ← task-only fields
  └─────────────────────────────────┘
  ┌─────────────────────────────────┐
  │ [Habit ▾] Stretch after lunch ✕ │
  │ anchor: after lunch · daily·mini │  ← habit-only fields
  └─────────────────────────────────┘
  ┌─────────────────────────────────┐
  │ [Goal ▾]  Get back in shape   ✕ │
  │ why: feel better · by Dec       │  ← goal-only fields
  └─────────────────────────────────┘
        [ Save all 3 ]   (✕'d ones dropped)
```

- **task** — title, details, schedule (date + time), location (place +
  enter/exit), reminder toggle.
- **habit** — title, anchor, cadence (default daily), level (default mini).
- **goal** — title, why, optional target date.
- **note** — title, body.

Per-card `✕` drops a draft; one **Save all** materializes the survivors.

## 6. Approval / materialization

On **Save all**, for each surviving draft, create the real row on the matching
repository via its existing `createForCapture(...)`:

- task  → `CaptureLinkedTasksRepository.createForCapture` (title, details, scheduledAt)
- note  → `CaptureLinkedNotesRepository.createForCapture` (title, body)
- habit → `CaptureLinkedHabitsRepository.createForCapture` (title, anchor, levelConfig)
- goal  → **new** `CaptureLinkedGoalsRepository.createForCapture` (title, why, targetDate)

Each child carries `capture_id`, so the 1→N link is the existing child column —
no capture-level 1:1 field needed. The capture flips to `triaged` when the last
draft is dispositioned (saved or dropped). Materialization is **idempotent** per
draft (re-running Save must not double-create) — reuse the existing
"already linked by capture_id" guard pattern, keyed per draft (see §11 open item).

## 7. Kind-switching — draft-stage only

Because drafts are JSON, not rows, switching a card's kind is just editing a
draft object — no table migration.

- **Switching is a pre-approval affordance only.** The `[Task ▾]` selector
  reclassifies a draft freely during review. Shared fields (title, details) carry
  over; kind-specific fields reset to AI-suggested or empty defaults.
- **After Save, switching is out of scope.** A real task row → habit means
  delete + recreate across tables; we do not build cross-table conversion. The
  pre-approval switch covers the "AI guessed wrong" case. Rule to freeze:
  **switch drafts, not records.**

## 8. Schema changes — migration `0004` (additive, post-lock)

Per `SCHEMA.md`, `0001` is LOCKED; this is a new additive migration.

1. `captures` ADD COLUMN `proposed_items jsonb` (nullable). Read whole; no index.
2. `goals` ADD COLUMN `capture_id` — the one gap: goals currently have no
   capture link. Composite `SET NULL` FK to `captures(id, user_id)`, matching
   `tasks.capture_id` (same-user ownership, child outlives parent).
3. **Drop the 1:1 capture CHECK** (`resulting_type`/`resulting_id` null unless
   `status='triaged'`, both present when triaged). The terminal state is now
   "all proposed items dispositioned," and the single result fields are retired.
4. `ResultingType` domain enum gains `goal` (drives draft routing, not a DB
   CHECK — the retired `captures.resulting_type` CHECK is dropped in step 3).

**Drift mirror:** bump `AppDatabase.schemaVersion` 1 → 2, add `proposedItems`,
`dispositionedItemIds`, and `autoCommittedAt` to `Captures`, add `captureId` to
`Goals` (TEXT), and add the `onUpgrade`
migration (currently there is none). Local DB has no CHECKs, so only the two
columns change client-side.

## 9. Designed-for-future-but-inert: location / context-aware reminders

The **task** draft carries `location` + a `reminder` toggle now, even though
context-aware (geofence) reminders are not implemented this phase. Reason: the
fields map straight onto the existing `reminders` / `places` schema
(`reminder_type='geofence'`, `geofence_transition`, `place_id`), so laying the UI
in now costs nothing and the future feature slots in without a redesign. This
phase: the schedule (time) reminder may be wired; the location field is captured
and stored but does not yet create geofence rows. Flagged so a reviewer doesn't
read the inert field as a bug.

## 10. Frozen P4 Gemini contract change

`CaptureAnalysis` (single object) and the `responseSchema` (single `enum`) are a
**frozen P4 boundary**. This work deliberately unfreezes them:

- `CaptureAnalysis` → returns an **ordered list of draft items** (the §4 shape).
- `responseSchema` → an array of item objects; prompt instructs the model to
  emit one array element per distinct thing in the rant, choosing a `kind` per
  the §2 rule and filling only that kind's fields, plus a per-item `confidence`.
- The prompt **must not cross-propagate context between items**: a location,
  date, or trigger stated for one item is not spread to sibling items unless the
  speaker said it for them too (see §12 — an inferred shared trigger is exactly
  the quiet wrong guess that would erode trust in auto-commit).
- `CaptureProcessingService` stores the list into `captures.proposed_items`
  instead of the single title/type/details. Failure/retry semantics are
  unchanged (still row-status only; audio stays put on failure).

Every frozen-contract test that asserts "one capture → one deterministic typed
row" (`test/inbox/p4_capture_loop_test.dart`) is rewritten for the N-item flow.

## 11. Out of scope & resolved decisions

**Deferred (not this phase):** geofence reminder creation; post-approval
cross-table kind conversion; goal breakdown / sub-goals / milestones (still the
future Goal-Sage migration); the shipped-key and 20 MB inline-audio Gemini debt
(unchanged, see `techdebt.md`).

**Resolved decisions (locked):**
- **Draft identity for idempotency.** Each draft gets a **stable client-assigned
  id** when `proposed_items` is written (Gemini isn't trusted to supply one).
  Materialization stores the approved draft-id → child-id mapping and re-checks it
  before creating, so a retried Save (or an auto-commit replay) never
  double-creates.
- **Partial approval / re-entry.** Saving some drafts and closing keeps the
  capture in review with the **remaining** drafts; dispositioned draft ids are
  tracked and their cards are not re-shown. Remaining drafts are durably
  downgraded to `confidence: low` as the explicit manual-review marker described
  in §4, so recovery never auto-commits them. The capture flips to `triaged` only
  when every draft is saved or dropped.
- **Empty extraction.** Zero actionable items → a **single `note` fallback**
  carrying the raw transcript, so nothing a user said is silently lost.
- **Cadence UI depth (habits).** v1 ships a **daily default + a simple
  weekly-days picker**; `cadence.type = custom` and interval math are stored-but-
  not-authored in the UI yet.

## 12. Direct capture (auto-commit)

Not every capture deserves a review pass. "Remind me to put the food in the
fridge when I'm home and feed the dogs," said one-handed while driving, should
just **become tasks** — no app, no approval. This section defines the narrow,
safe class of captures that skip §5's review entirely, and the safety net that
makes skipping approval acceptable.

**Same gesture, one pipeline.** There is no separate "quick add" trigger. Every
capture runs the same rant → Gemini → `proposed_items` path (§3). Auto-commit is
a decision made *after* extraction, from what's actually in the audio — not a
mode the user selects up front (they're driving; one button, they talk).

### 12.1 Eligibility — the gate

A capture is auto-commit-eligible **only when every one of these holds**:

1. **Every extracted item is a `task`.** Any `habit`, `goal`, or `note` present
   → review. Habits and goals create *ongoing structure*; a wrong one is clutter
   that implies commitment, not a one-tap delete. Only the cheap-to-undo kind
   earns the right to skip approval.
2. **Every item is `confidence: high`.** Any low-confidence item → review.
3. **Item count ≤ 3.** More than a few tasks is too much to have silently
   materialized (and to Undo) from the car. Over the cap → review.

The gate is **structural**, computed client-side from `proposed_items` — the
model's `confidence` is an input (condition 2), but the model does not get to
*force* an auto-commit; it can only fail the gate. Length of the rant is not a
gate input; homogeneity (all-tasks) + the count cap already cover the "long
rambling rant" case, which will almost always trip condition 1 or 3.

### 12.2 Atomic per capture

Auto-commit is **all-or-nothing for the whole capture.** If every item passes the
gate, materialize them all and go straight to `triaged`. If *any* item fails,
the **entire** capture goes to review (§5) — we never auto-add some items and
shelve others from the same recording. One capture = one disposition. This keeps
the mental model honest: a capture was either handled for you, or it's waiting.

When a long/mixed capture is sent to review this way, surface a brief nudge
("Needs your review — tap to open") so the user learns the boundary: concise,
all-task captures get handled automatically; anything richer waits.

### 12.3 No cross-item context inference

Each task is materialized with **only the context stated for it.** A location,
date, or trigger the speaker attached to one task is **not** propagated to
siblings. "Feed the dogs" in the example gets no location unless the speaker said
so — a plain task is the correct, honest result. (Enforced in the Gemini prompt,
§10.) An inferred shared trigger is precisely the quiet wrong guess that would
make auto-commit untrustworthy.

### 12.4 Materialization & state

On passing the gate, `CaptureProcessingService` runs the same
`CaptureLinkedTasksRepository.createForCapture(...)` path that "Save all" uses,
for every item, using the per-draft client id for idempotency (§11). The capture
transitions **`processing → triaged`** directly, skipping `ready`. `proposed_items`
is written first and retained — it is the audit trail Undo and Edit read from.
The rows are **real immediately**; there is no pending/soft-commit state.

### 12.5 Safety net — notification + Undo + discoverability

Skipping approval is only acceptable because a mistake is one tap to reverse:

- **One grouped notification per capture**: `✓ Added 2 tasks — [Undo] [Edit]`.
  Never one-notification-per-task — grouped is the only car-usable form.
  - **Undo** — live for a few seconds; soft-deletes every task created from this
    capture (bulk, not per-item) and returns the capture to a reviewable state.
  - **Edit** — deep-links into the app to the created task(s); does not undo.
  - **Dismissing is approval.** There is no explicit "approve" action — the rows
    are already real, so adding an approve step would re-introduce the friction
    this whole path removes.
- **Discoverable after the fact**: an "auto-added recently" strip in the inbox,
  so a missed notification is still recoverable without hunting through the task
  list.

A notification is a courtesy (and can't be safely tapped mid-drive anyway); the
inbox strip is the durable safety net.

### 12.6 Out of scope this phase

Auto-commit for **notes** (harmless but not time-sensitive — they wait in review
for now); a user-facing **strictness setting** for the gate (the §12.1 rule is
the fixed default); and any **geofence** wiring for the location an auto-committed
task may carry (stored, inert — §9).

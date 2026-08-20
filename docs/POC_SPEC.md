# Sidekick POC Spec

## Product

Sidekick is an Android-first POC for creating smart task reminders from typed
input or the existing audio shortcut.

The POC promise:

> Capture or type a reminder once, let Sidekick infer the task/time/place
> trigger, then remind at the right moment with a correction loop.

## In Scope

- Android proof platform.
- Auth/profile and onboarding gate.
- Theme and shell.
- Local-first storage and sync foundation.
- Android hardware/audio capture shortcut.
- Gemini transport for reminder drafting.
- Captures as durable input records.
- Task reminders as the only extracted item type.
- Places for location-triggered reminders.
- Settings for capture, notification, location, account, and sync controls.
- Events for reminder actions and correction signals.
- Future conversation/message storage only as data-model preparation.

## Out of Scope

- Habit, goal, note, focus, app-blocking, vibe-check, and Done-list product
  surfaces.
- Persona chat UI.
- TTS or spoken talk-back.
- Proactive assistant suggestions.
- iOS proof.
- Additional themes.
- Broad capture decomposition into non-reminder item kinds.

## Capture Flow

Typed and audio input must feed the same reminder-drafting pipeline by Phase 2.
Audio is written to disk before any AI call. A single input may create multiple
task-reminder drafts, but no POC draft may become a habit, goal, or note.

High-confidence drafts with a clear trigger enter a 10-second auto-commit
countdown. The user can cancel or edit before activation. Low-confidence or
incomplete drafts open review.

Unclear audio gets two retry prompts. After the retry limit, the app falls back
to typed input.

## Reminder Runtime

Active reminders may be time-based or place-based. Android scheduling must
support local notifications, geofence enter/exit triggers, dwell filtering, and
resync after app start. Notification actions are Done, Later, Dismiss, and Wrong
place.

## AI Context

AI context may include profile preferences, saved places, active reminders,
recent reminder actions, and recent unclear captures. Context can improve a
user-requested reminder, but AI must not create reminders from context alone.

Every AI-created reminder stores confidence, trigger explanation, and context
items used.

## Active Navigation

- Capture
- Reminders
- Places
- Settings

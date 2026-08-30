# Sidekick — agent operating manual

Read this file first. It tells you what this repository is, which rules are
non-negotiable, and which document to open next. Do not start editing from a
feature request alone; the wiring here spans four runtimes and the failure modes
are almost all at the seams between them.

## What this is

An Android-first POC for smart task reminders. The whole product is one loop:

> Capture or type a reminder once → Sidekick infers task/time/place →
> a 10-second correction window → remind at the right moment →
> learn from Done / Later / Dismiss / Wrong place.

Anything outside that loop is future work and belongs in
[docs/FUTURE_PLANS.md](docs/FUTURE_PLANS.md), not in `lib/`.

Authoritative scope: [docs/POC_SPEC.md](docs/POC_SPEC.md).
Phase plan and report format: [docs/POC_PHASES.md](docs/POC_PHASES.md).

## The four runtimes

Every non-trivial change touches more than one of these. Know which you are in.

| Runtime | Lives in | Owns |
|---|---|---|
| Flutter UI + application services | `lib/features/**` | Screens, drafting, creation/approval flow |
| Flutter core | `lib/core/**` | Drift DB, sync, auth, events, theme, capture bridge |
| Android native | `android/app/src/main/kotlin/**` | Alarms, geofences, notifications, the alarm screen, the durable action journal, audio capture |
| Postgres (Supabase) | `supabase/migrations/**` | Cloud mirror, RLS, LWW guard, type + FK constraints |

The Dart↔Kotlin and Dart↔Postgres boundaries are typed contracts that the
compiler does **not** check for you. See
[docs/RUNTIME_CONTRACTS.md](docs/RUNTIME_CONTRACTS.md) before crossing either.

## Hard rules

1. **Local-first, always.** A user mutation writes drift and returns. Sync is a
   background best-effort concern and must never block, fail, or delay the UI.
2. **Ids are client-generated UUIDv4.** Postgres declares every `id` and every
   `*_id` column as `uuid`. A non-UUID string will pass drift and then poison
   that table's sync permanently. Never invent an id format.
3. **`events` and `reminder_events` are append-only.** No update, no delete, no
   read-side product feature. RLS enforces this server-side.
4. **Enums own the allowed values.** Drift carries no CHECK constraints;
   `lib/core/domain/enums.dart` is where the wire strings live, and Postgres
   CHECKs mirror them. Change all three together or not at all.
5. **Never repurpose a column.** If you need new state, add a column or a table.
   (`captures.error` was overloaded this way and it leaked user text into an AI
   prompt — see the review report.)
6. **Every reminder mutation must reconcile the native schedule.** Status,
   trigger type, place, and time changes all imply a `schedule()` or `cancel()`.
   A DB row that disagrees with the alarm/geofence registry is the worst bug
   class in this app because it is invisible until a notification is wrong.
7. **No new product surface.** The nav is Capture / Reminders / Places /
   Settings. `test/static/poc_cleanup_test.dart` enforces it.
8. **Do not add AI/Claude attribution to commits or PR bodies.**

## Where to put things

Full directory-by-directory rules: [docs/CODE_MAP.md](docs/CODE_MAP.md).
The short version:

- Pure decisions and orchestration → `lib/features/<feature>/application/`
- Drift reads/writes → `lib/features/<feature>/data/`
- Immutable models + repository interfaces → `lib/features/<feature>/domain/`
- Widgets → `lib/features/<feature>/presentation/`
- Anything two features share → `lib/core/**`
- Anything that must survive the app process being killed → Kotlin

## Before you finish

```
C:\src\flutter\bin\dart.bat analyze
C:\src\flutter\bin\flutter.bat test
```

Both must be clean. If you touched Kotlin, note that Robolectric tests exist
under `android/app/src/test/kotlin/` and are not part of `flutter test`.
Details and layering rules: [docs/TESTING.md](docs/TESTING.md).

If you completed a build phase, write the report format from
`docs/POC_PHASES.md` into `docs/reports/`. If you knowingly left debt, append it
to `TECH_DEBT.md` with trigger and cost — that file is read, not decoration.

## Known-broken as of 2026-08-29

Do not "discover" these again; they are documented with evidence and fixes in
[docs/reports/CODE_REVIEW_2026-08-29.md](docs/reports/CODE_REVIEW_2026-08-29.md).
The load-bearing ones: reminder times are parsed in UTC rather than the user's
zone; native action ids break `reminder_events` sync; auto-commit only advances
while the Capture tab is mounted; deleting a place orphans its geofence.

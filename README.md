# Sidekick

An offline-first "analog companion" for Android and iOS — a calm, low-friction
personal assistant built around fast capture and gentle, shame-free habit
support. Built with Flutter + Dart, local-first storage with cloud sync.

> Personal project, built in phases. This repository holds the application
> source; internal planning and design-review documents are kept out of the
> public tree (see [Repository layout](#repository-layout)).

## Status

- **Phase 0 — Foundations, theme architecture, app shell** ✅
  Swappable dark theme (Analog Companion as the default), offline-bundled
  fonts, shared visual primitives, and a four-destination app shell.
- **Phase 1 — Database schema** ✅ (design + reviewed migration under
  `supabase/`).

Feature behavior, persistence wiring, auth, sync, Gemini, and native capture
land in later phases.

## Toolchain

- Flutter 3.44.6 stable
- Dart 3.12.2 with sound null safety
- Android minimum SDK 26
- iOS target generated with Flutter defaults

Dependencies are exact-pinned in `pubspec.yaml` and fully resolved in
`pubspec.lock`.

## Run

```text
flutter pub get
flutter run --dart-define-from-file=.env
```

Runtime config is read from a gitignored `.env` at the repo root (see
`.env.example` for the keys). It is loaded at build time via
`--dart-define-from-file`; no secrets are committed. Required keys:
`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` (Supabase's modern client key,
`sb_publishable_…`, replacing the legacy `anon` JWT). `GEMINI_API_KEY` is
optional and unused at this stage. Extra keys in `.env` are ignored.

## Verify

```text
flutter analyze
flutter test
```

## Design system

The visual language (colors, type, spacing, radii) is defined in
`DESIGN_SYSTEM.md` and consumed as a single **registered theme**, never as
hardcoded values. Adding a second theme is a data swap, not a widget refactor —
widgets reach every visual token through the theme accessor only.

## Repository layout

```text
lib/          Flutter app (core/ + feature-first modules)
assets/fonts/ Bundled DM Serif Display + DM Sans (offline-first, no runtime fetch)
supabase/     Postgres schema migration + RLS tests
scripts/      Local tooling (e.g. migration test runner)
test/         Widget + architecture tests
```

Internal planning and review material — the phased build plan, review rubrics,
schema rationale, and per-phase gate reviews — is intentionally **not published**
and stays local (see the "Kept local" section of `.gitignore`).

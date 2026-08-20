# Sidekick conventions

## Theme access and D8

`AppTheme` is the complete visual contract. It exposes `colors`, `colorScheme`,
`textTheme`, `spacing`, `radii`, `dimensions`, and `motion`. Widgets read it only
through `context.appTheme`, provided by `AppThemeScope`. Widgets must not contain
raw colors, font choices, spacing, radii, outline widths, or component
dimensions.

A tinted or translucent colour is still a colour: composing one at a call site
(`colors.secondary.withValues(alpha: 0.4)`) puts a visual decision in a widget
where a second theme cannot restate it. Such colours are named tokens on
`AppColors` — `secondarySurface` and `secondaryOutline` are the Fresh Start
chip. The same rule covers every duration: `AppMotion` owns them, including
`tabSelection` for the Today/Done selector.

`AppThemeRegistry.themes` is the named registry and intentionally contains one
entry: `analog_companion`. `activeThemeNameProvider` is the selectable theme
name; `activeThemeProvider` resolves it to an `AppTheme`. A future theme is added
as registry data. It must not require widget edits. The theme-swap widget test
is the regression proof for this D8 rule.

Analog Companion is dark-only. Depth uses the surface-container stack and the
theme's one-pixel outline; shadows are prohibited. DM Serif Display italic is
reserved for identity and intent moments. DM Sans 400/500 is functional text.
Both families are bundled under `assets/fonts` and never fetched at runtime.

## Routing

Sidekick uses `go_router` because its declarative shell routes and deep-linkable
paths fit the feature-first structure without generated files. Public constants
are `AppRoutes.inbox`, `AppRoutes.habits`, `AppRoutes.focus`, and
`AppRoutes.settings`; corresponding route-name constants end in `Name`.

## Folder rules

Shared infrastructure belongs in `lib/core/<area>`. Product code belongs in
`lib/features/<feature>/{data,domain,presentation}`. Presentation code may depend
on domain contracts and core UI contracts. Domain must not depend on data or
presentation. Data implements domain contracts. Phase 0 deliberately leaves all
data and domain folders empty; no database tables, auth, sync, or feature logic
is implemented.

## Environment

`AppConfig` reads `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `GEMINI_API_KEY` with
`String.fromEnvironment`. Pass them at build/run time, for example:

```text
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=GEMINI_API_KEY=...
```

`.env.example` documents names only. Real `.env` variants are ignored and are
not loaded automatically. Never commit or hardcode credentials.

## Shared widget signatures

- `PillButton({required String label, required VoidCallback? onPressed, PillButtonVariant variant = primary})`
- `SurfaceCard({required Widget child})`
- `PersonaOrb({bool isPulsing = false, PersonaOrbTone tone = amber, int singlePulseToken = 0})`
- `ParticleBurst({required Widget child, bool isActive = false, VoidCallback? onComplete})`

`ParticleBurst` kept its Phase 5-facing API through the Phase 0 pass-through and
is implemented for real in Phase 5 — the signature never changed. `PersonaOrb`
gained `tone` (Fresh Start's teal mode) and `singlePulseToken` (one
acknowledging pulse per completion) in Phase 5; both are optional, so the
Phase 0 signature still calls correctly. Motion values — particle count, size,
burst duration, acknowledgment fade — are theme tokens on `AppMotion`, never
literals in a widget.

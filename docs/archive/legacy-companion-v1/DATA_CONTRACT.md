# Sidekick — Data Contract (P2, FROZEN)

**Status:** ✅ frozen at the end of Phase 2. Later feature phases depend **only**
on the interfaces and providers named here. drift + Supabase types never escape
`lib/**/data/` or `lib/core/**` — feature code sees domain models and repository
interfaces, nothing else.

Authoritative code:
- Local schema: `lib/core/db/tables.dart` + generated `app_database.g.dart`
- Repositories: `lib/features/<feature>/domain/*.dart` (interface) + `data/*.dart` (impl)
- Providers: `lib/core/providers/`, `lib/core/auth/auth_providers.dart`,
  `lib/core/sync/sync_providers.dart`, `lib/features/profile/preferences_providers.dart`

---

## 1. Local-first write model (D5)

Every mutation is **local-first and synchronous-feeling**. A `create/update/delete`:

1. writes the row to the local drift database,
2. sets `updated_at = now()` (device UTC wall-clock — the client-owned LWW clock),
3. sets `dirty = true` (and `deleted_at` for deletes — soft delete / tombstone),
4. emits a structural event as a **non-blocking side effect** (see §5),
5. returns immediately. **No repository method awaits the network.**

`watch*` methods return `Stream<List<T>>` (or `Stream<T?>`) reading LOCAL drift,
filtered to the owning user and `deleted_at IS NULL`. Streams update the instant a
local write (or a pull) lands.

`dirty` / `synced_at` are **client-local only** — they do not exist in the cloud
schema (SCHEMA.md R0). The cloud owns `updated_at` + `deleted_at`.

### Enums
Allowed value sets live in `lib/core/domain/enums.dart` (the local drift schema
carries no CHECKs; the domain layer enforces them). Each enum ⇄ its stored `wire`
string. `PersonaLanguage` wires are `en` / `ar-EG`.

---

## 2. Repository interfaces (THE contract — frozen)

Constructed per signed-in user; obtained via the providers in §6. Signatures
(return types abbreviated; see the domain files for full parameter lists):

| Interface | Key methods |
|---|---|
| `CapturesRepository` | `watchAll()`, `watchByStatuses(Set<CaptureStatus>)`, `getByIds(List<String>)`, `create({audioPath, capturedAt, source})`, `update(Capture)`, `delete(id)` |
| `TasksRepository` | `watchAll()`, `watchByStatus(TaskStatus)`, `create({title, details, captureId, goalId, scheduledAt})`, `update(Task)`, `delete(id)` |
| `NotesRepository` | `watchAll()`, `create({title, body, captureId})`, `update(Note)`, `delete(id)` |
| `GoalsRepository` | `watchAll()`, `watchByStatus(GoalStatus)`, `create({title, why, targetDate})`, `update(Goal)`, `delete(id)` |
| `HabitsRepository` | `watchAll()`, `create({title, frequencyConfig, levelConfig, anchorDescription, captureId, goalId})`, `update(Habit)`, `delete(id)` |
| `HabitCompletionsRepository` | `watchAll()`, `watchByHabit(id)`, `create({habitId, level, energyMode, completedAt})`, `delete(id)` |
| `PlacesRepository` | `watchAll()`, `create({name, lat, lng, radiusM})`, `update(Place)`, `delete(id)` |
| `FocusSessionsRepository` | `watchAll()`, `watchById(id)`, `create({durationMinutes, taskId, taskLabel, blockingEnabled, blockingMode})`, `update(FocusSession)`, `delete(id)` |
| `VibeChecksRepository` | `watchAll()`, `create({value, focusSessionId})`, `delete(id)` |
| `RemindersRepository` | `watchAll()`, `createTimeReminder({scheduledAt, taskId, habitId, recurrence, copy})`, `createGeofenceReminder({placeId, transition, taskId, habitId, dwellSeconds, copy})`, `update(Reminder)`, `delete(id)` |
| `BlockListRepository` | `watchAll()`, `create({platform, appIdentifier, appLabel})`, `delete(id)` |
| `ProfileRepository` | `watch()`, `get()`, `ensureExists()`, `setPersonaLanguage(PersonaLanguage)`, `setTheme(String)`, `mergePrefs(Map)` |

Capture decomposition extends the frozen interfaces additively through
`CaptureLinkedTasksRepository`, `CaptureLinkedNotesRepository`,
`CaptureLinkedHabitsRepository`, and `CaptureLinkedGoalsRepository`. Their
`createForCapture` methods accept a stable draft id for idempotent 1:N
materialization; the frozen `GoalsRepository.create({title, why, targetDate})`
signature remains unchanged.

`update(model)` on a `status`-bearing entity detects a status change and emits
`<entity>_status_changed`. `delete(id)` is a soft delete (tombstone) so it
propagates through sync.

---

## 3. Events log — write-only (D9)

`EventsRepository` (`lib/core/events/events_repository.dart`) exposes **only**:

- `append(DomainEvent)` — immutable INSERT, LOCAL-FIRST + `dirty`. Never updates/deletes.
- `getSince(DateTime)` — **`@visibleForTesting` only.** Not a product read surface.

There is deliberately **no** read/query/analytics API and no UI reads events.

### The emission hook — `EventEmitter`
`lib/core/events/event_emitter.dart`. The write-only API later phases call:

- `emit({userId, eventType, entityType, entityId, metadata})`
- `emitCreated({userId, entityType, entityId, metadata})` → `<entity>_created`
- `emitStatusChanged({userId, entityType, entityId, from, to})` → `<entity>_status_changed`

Every method is **`void`, fire-and-forget, and swallows all errors** — emitting an
event can never block or fail the user mutation it rides on. Taxonomy: `docs/EVENTS.md`.

---

## 4. Sync engine (D5)

Behind `SyncEngine` (`lib/core/sync/sync_engine.dart`), stub-able in tests:

- `flush()` — push every `dirty` row for each `kSyncableTables` table via
  `SyncGateway.push`; on success clear `dirty` + set `synced_at`.
- `pull()` — for each table, ask the gateway for rows `updated_at > last_pull`,
  apply with **last-write-wins**, advance the local `sync_meta.last_pull` cursor.
- `syncNow()` = flush then pull. `start()` triggers `syncNow` on connectivity
  regained (`ConnectivityService`); the app also calls `syncNow` on foreground.
- All failures are swallowed and retried on the next trigger — **sync never blocks the UI.**

**LWW (pull side):** an incoming row is applied unless the local row is `dirty`
and strictly newer (it will push next flush); ties go to the incoming
server-arbitrated row. **`events` push is INSERT-ONLY** (immutable, client-id'd —
no conflict, D9).

`SyncGateway` is the network boundary (`SupabaseSyncGateway` is the impl); rows are
neutral snake_case JSON maps. `dirty` / `synced_at` are stripped before push.

---

## 5. Auth / session accessor

`AuthRepository` (`lib/core/auth/auth_repository.dart`). **Email + password**,
explicit account creation, **no email verification** (deliberate low-friction
onboarding for the ADHD audience — requires Supabase "Confirm email" OFF).
Google sign-in is the planned second method (native `signInWithIdToken`),
designed into the login screen but disabled until the Google Cloud console +
native setup lands (techdebt.md).

- `SessionState get current` — read **synchronously** from the cached (restored)
  session; never a network call. This is what lets the app open offline without a
  spinner-lock.
- `Stream<SessionState> watch()` — seeded with `current`, then follows changes.
- `signUpWithPassword({email, password})`, `signInWithPassword({email, password})`,
  `signOut()`.

> **Contract amendment (was email-OTP `sendOtp`/`verifyOtp`).** The downstream
> session shape (`SessionState`, `user.id`, JWT) is unchanged, so sync, RLS, and
> the provider graph are untouched — only the credential-exchange methods changed.

`Supabase.initialize` runs in `main` before `runApp`; it restores the cached
session from local storage without a network round-trip. The root router
(`app_router.dart`) gates: signed-out → `/login`, signed-in & not onboarded →
`/onboarding`, else the shell.

---

## 6. Providers (frozen)

| Provider | Type | Notes |
|---|---|---|
| `appDatabaseProvider` | `AppDatabase` | single local DB for the session |
| `idGeneratorProvider` | `IdGenerator` | client UUID v4 |
| `supabaseClientProvider` | `SupabaseClient` | |
| `connectivityServiceProvider` | `ConnectivityService` | |
| `eventsRepositoryProvider` | `EventsRepository` | D9 write-only |
| `eventEmitterProvider` | `EventEmitter` | the emission hook |
| `syncGatewayProvider` | `SyncGateway` | Supabase-backed |
| `pendingAudioQueueProvider` | `FutureProvider<PendingAudioQueue>` | resolves docs dir |
| `authRepositoryProvider` | `AuthRepository` | |
| `sessionProvider` | `StreamProvider<SessionState>` | |
| `currentUserIdProvider` | `String?` | sync; `null` when signed out |
| `requireUserIdProvider` | `String` | throws when signed out |
| `syncEngineProvider` | `SyncEngine?` | `null` when signed out; started on build |
| `<entity>RepositoryProvider` | the interface | one per §2 entity (`core/providers/repository_providers.dart`) |
| `profileRepositoryProvider` | `ProfileRepository` | |
| `profileProvider` | `StreamProvider<Profile?>` | live preferences |
| `personaLanguageProvider` | `PersonaLanguage` | D2, app-wide (default English) |
| `onboardingCompletedProvider` | `bool` | drives the gate |

Repository providers are bound to `requireUserIdProvider`; read them only from
signed-in surfaces.

---

## 7. Pending-audio queue (for P3/P4)

`PendingAudioQueue` (`lib/core/audio/pending_audio_queue.dart`). The "capture must
never be lost" store: P3 writes audio to disk **before** any network work and
enqueues it; P4 drains it.

- `reservePath({extension})` — a destination `File` under
  `<app-docs>/pending_audio/` for a recorder to write to directly (bytes hit disk
  first). Reserve does not create the file.
- `enqueueBytes(bytes, {extension})` → `PendingAudio`
- `pending()` → `List<PendingAudio>` (oldest first)
- `remove(id)` — drop a drained entry.

Concrete impl: `DirectoryPendingAudioQueue({baseDir})`; the app injects the
platform documents directory, tests inject a temp dir.

---

## 8. Preferences storage

Persona language + theme are discrete columns on `profiles`; additive UI config
(trigger, energy time-rules, onboarding flags) lives in the `prefs` JSON blob
(SCHEMA.md §Preferences). Onboarding writes `persona_response_language` and
`prefs.onboarding_completed = true` via `ProfileRepository`.

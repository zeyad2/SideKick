import 'package:drift/drift.dart';

// =============================================================================
// drift tables — the LOCAL mirror of the LOCKED Postgres schema.
//
// Mirrors `supabase/migrations/0001_initial_schema.sql` (12 tables) and the
// additive `0002_events_log.sql` (`events`), column-for-column (snake_case
// names match the migration). Plus the CLIENT-LOCAL sync bookkeeping the cloud
// schema deliberately omits (SCHEMA.md R0): `dirty` + `synced_at` on every
// syncable table, and a local-only `sync_meta` cursor table.
//
// Deliberate deviations from the cloud schema (a local cache, not the arbiter
// of integrity — see docs/DATA_CONTRACT.md):
//   * No FK / CHECK / composite-ownership constraints. RLS + the server's FKs
//     enforce integrity; the client trusts what it wrote and what it pulled.
//     Enums are enforced in the domain layer, not by the local DB.
//   * JSONB columns are stored as TEXT holding a JSON string; repositories
//     encode/decode. (The value is always read whole, never queried in SQL.)
// =============================================================================

/// The five columns every syncable table carries locally:
/// `created_at` / `updated_at` / `deleted_at` mirror the cloud LWW clock +
/// tombstone; `dirty` / `synced_at` are the client-local push bookkeeping the
/// cloud schema omits (R0). A freshly-created local row is `dirty = true`.
mixin SyncColumns on Table {
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Local-only: this row has un-pushed local changes. Cleared after a
  /// successful push. Not present in the cloud schema.
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  /// Local-only: when this device last pushed this row (`null` = never).
  DateTimeColumn get syncedAt => dateTime().nullable()();
}

@DataClassName('ProfileRow')
class Profiles extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get personaResponseLanguage =>
      text().withDefault(const Constant('en'))();
  TextColumn get theme =>
      text().withDefault(const Constant('analog_companion'))();

  /// Additive client-only UI config (JSON blob). See SCHEMA.md §Preferences.
  TextColumn get prefs => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('CaptureRow')
class Captures extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get audioPath => text().nullable()();
  TextColumn get rawTranscript => text().nullable()();
  TextColumn get llmType =>
      text().withDefault(const Constant('uncategorized'))();
  TextColumn get title => text().nullable()();
  TextColumn get details => text().nullable()();
  TextColumn get suggestedSchedule => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get resultingType => text().nullable()();
  TextColumn get resultingId => text().nullable()();
  DateTimeColumn get capturedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('GoalRow')
class Goals extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get why => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get targetDate => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('TaskRow')
class Tasks extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get captureId => text().nullable()();
  TextColumn get goalId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get details => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('todo'))();
  TextColumn get nextAction => text().nullable()();
  DateTimeColumn get scheduledAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get lastActivityAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('NoteRow')
class Notes extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get captureId => text().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get body => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('HabitRow')
class Habits extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get captureId => text().nullable()();
  TextColumn get goalId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get frequencyConfig => text().nullable()();
  TextColumn get levelConfig => text().nullable()();
  TextColumn get anchorDescription => text().nullable()();
  BoolColumn get resetActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get resetStartedAt => dateTime().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('HabitCompletionRow')
class HabitCompletions extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get habitId => text()();
  TextColumn get level => text()();
  TextColumn get energyMode => text().nullable()();
  DateTimeColumn get completedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('PlaceRow')
class Places extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  IntColumn get radiusM => integer().withDefault(const Constant(150))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('FocusSessionRow')
class FocusSessions extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get taskId => text().nullable()();
  TextColumn get taskLabel => text().nullable()();
  IntColumn get durationMinutes => integer()();
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  BoolColumn get blockingEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get blockingMode => text().withDefault(const Constant('soft'))();
  IntColumn get blockAttempts => integer().withDefault(const Constant(0))();
  TextColumn get capturesDuring => text().withDefault(const Constant('[]'))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('VibeCheckRow')
class VibeChecks extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get focusSessionId => text().nullable()();
  IntColumn get value => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('ReminderRow')
class Reminders extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get reminderType => text()();
  TextColumn get taskId => text().nullable()();
  TextColumn get habitId => text().nullable()();
  DateTimeColumn get scheduledAt => dateTime().nullable()();
  TextColumn get recurrence => text().nullable()();
  DateTimeColumn get snoozeUntil => dateTime().nullable()();
  TextColumn get placeId => text().nullable()();
  TextColumn get geofenceTransition => text().nullable()();
  IntColumn get dwellSeconds =>
      integer().nullable().withDefault(const Constant(60))();
  TextColumn get copy => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('scheduled'))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('BlockListRow')
class BlockList extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get platform => text()();
  TextColumn get appIdentifier => text()();
  TextColumn get appLabel => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Append-only, immutable behavioural event log (D9 / `0002_events_log.sql`).
/// Rows are only ever INSERTed locally; nothing updates or deletes them.
@DataClassName('EventRow')
class Events extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get eventType => text()();
  TextColumn get entityType => text().nullable()();
  TextColumn get entityId => text().nullable()();
  TextColumn get metadata => text().withDefault(const Constant('{}'))();
  DateTimeColumn get occurredAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// LOCAL-ONLY (never synced): the per-table pull cursor. One row per synced
/// table holding the newest `updated_at` this device has already pulled
/// (SCHEMA.md R0). The next pull asks the server for `updated_at > last_pull`.
class SyncMeta extends Table {
  // `tableName` is a reserved drift getter, so this local-only cursor column is
  // named `syncTable`. It never syncs, so the SQL name need match nothing.
  TextColumn get syncTable => text()();
  DateTimeColumn get lastPull => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{syncTable};
}

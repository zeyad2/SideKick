import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sidekick/core/db/tables.dart';

// Re-export the table DSL classes so repositories that import app_database.dart
// can name them in `where`/`orderBy` callbacks (e.g. `(Tasks t) => ...`).
export 'package:sidekick/core/db/tables.dart';

part 'app_database.g.dart';

/// The local-first store. Every repository write hits this database first and
/// returns immediately (D5); sync is a best-effort background concern.
///
/// The schema mirrors the LOCKED Postgres migrations `0001` + `0002` plus the
/// client-local sync bookkeeping (see [tables.dart] and docs/DATA_CONTRACT.md).
@DriftDatabase(
  tables: <Type>[
    Profiles,
    Captures,
    Goals,
    Tasks,
    Notes,
    Habits,
    HabitCompletions,
    Places,
    FocusSessions,
    VibeChecks,
    Reminders,
    BlockList,
    Events,
    SyncMeta,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  /// Test constructor: pass an in-memory or otherwise custom executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  /// Local schema evolution. v1 → v2 (capture decomposition, migration `0004`):
  /// add the decomposition checkpoint columns and `goals.capture_id`. The local DB has no
  /// CHECKs/FKs, so only the two columns change client-side; existing rows keep
  /// their data and the new columns default to null.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) => m.createAll(),
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.addColumn(captures, captures.proposedItems);
        await m.addColumn(captures, captures.dispositionedItemIds);
        await m.addColumn(captures, captures.autoCommittedAt);
        await m.addColumn(goals, goals.captureId);
      }
    },
  );

  /// Clears every local table — all synced rows AND the local pull cursor
  /// (`sync_meta`) — in a single transaction. Called on sign-out: the local DB
  /// is shared across accounts on one device, so a different user signing in
  /// must inherit neither the previous user's rows nor their stale pull cursor
  /// (which would otherwise make the new user under-pull their own data). After
  /// a wipe the next session starts blank and re-pulls from the server.
  Future<void> wipeAllData() => transaction(() async {
    for (final TableInfo<Table, dynamic> table in allTables) {
      await delete(table).go();
    }
  });

  static QueryExecutor _open() =>
      driftDatabase(name: 'sidekick', native: const DriftNativeOptions());
}

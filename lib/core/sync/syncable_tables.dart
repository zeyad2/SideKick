import 'package:meta/meta.dart';

/// One syncable table: its SQL name (identical on drift and Postgres) and
/// whether pushes are INSERT-ONLY (`events`, per D9 — immutable, client-id'd,
/// no LWW conflict).
@immutable
class SyncableTable {
  const SyncableTable(this.name, {this.insertOnly = false});

  final String name;
  final bool insertOnly;

  /// The column carrying the owning user's id. `profiles` is keyed by the user
  /// id itself (`id`); every other table carries a `user_id`. Used to scope the
  /// flush/ack to the signed-in user on a shared local database.
  String get ownerColumn => name == 'profiles' ? 'id' : 'user_id';
}

/// The registry the sync engine iterates. Order matters only cosmetically;
/// each table syncs independently. `sync_meta` is deliberately absent — it is
/// the LOCAL-ONLY pull cursor and never leaves the device.
const List<SyncableTable> kSyncableTables = <SyncableTable>[
  SyncableTable('profiles'),
  SyncableTable('captures'),
  SyncableTable('goals'),
  SyncableTable('tasks'),
  SyncableTable('notes'),
  SyncableTable('habits'),
  SyncableTable('habit_completions'),
  SyncableTable('places'),
  SyncableTable('focus_sessions'),
  SyncableTable('vibe_checks'),
  SyncableTable('reminders'),
  SyncableTable('block_list'),
  SyncableTable('events', insertOnly: true),
];

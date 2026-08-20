import 'package:meta/meta.dart';

/// One syncable table: its SQL name (identical on drift and Postgres) and
/// whether pushes are INSERT-ONLY (`events`/`reminder_events`: immutable,
/// client-id'd, no LWW conflict).
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
  SyncableTable('places'),
  SyncableTable('captures'),
  SyncableTable('task_reminders'),
  SyncableTable('reminder_events', insertOnly: true),
  SyncableTable('conversations'),
  SyncableTable('messages'),
  SyncableTable('events', insertOnly: true),
];

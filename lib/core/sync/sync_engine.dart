import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:sidekick/core/sync/connectivity_service.dart';
import 'package:sidekick/core/sync/sync_gateway.dart';
import 'package:sidekick/core/sync/syncable_tables.dart';

/// The background sync engine (D5). Local writes never wait on it; it flushes
/// dirty rows up and pulls remote changes down, best-effort. Failures are
/// swallowed and retried on the next trigger — sync NEVER blocks the UI.
abstract interface class SyncEngine {
  /// Flush local changes up, then pull remote changes down. Best-effort.
  Future<void> syncNow();

  /// Push every dirty row; clear `dirty` + set `synced_at` on success.
  Future<void> flush();

  /// Pull rows updated since the per-table cursor; upsert with LWW; advance it.
  Future<void> pull();

  /// Begin reacting to connectivity regained (and app-foreground, wired by the
  /// caller via [syncNow]).
  void start();

  /// Completes once the first [syncNow] cycle has finished — whether it
  /// succeeded, failed, or found nothing. The onboarding gate waits on this so a
  /// returning user on a fresh install is not misclassified as new (and made to
  /// re-onboard, overwriting synced preferences) before their profile pulls
  /// down. It never throws: a failed cycle still settles.
  Future<void> get firstSyncSettled;

  Future<void> dispose();
}

/// drift-backed [SyncEngine]. Iterates [kSyncableTables] generically via raw
/// SQL (the local sync bookkeeping is uniform across tables), so there is no
/// per-table mapping to maintain.
class DriftSyncEngine implements SyncEngine {
  DriftSyncEngine({
    required this.db,
    required this.gateway,
    required this.connectivity,
    required this.userId,
    this.tables = kSyncableTables,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase db;
  final SyncGateway gateway;
  final ConnectivityService connectivity;
  final String userId;
  final List<SyncableTable> tables;
  final DateTime Function() _clock;

  /// Columns that live only on the local mirror (R0) — never pushed upstream.
  static const Set<String> _localOnlyColumns = <String>{'dirty', 'synced_at'};

  /// JSONB columns: stored as TEXT locally, must round-trip as JSON objects.
  static const Set<String> _jsonColumns = <String>{
    'prefs',
    'ai_context',
    'metadata',
  };

  StreamSubscription<bool>? _connectivitySub;
  bool _syncing = false;
  final Completer<void> _firstSync = Completer<void>();

  @override
  Future<void> get firstSyncSettled => _firstSync.future;

  @override
  void start() {
    _connectivitySub ??= connectivity.onConnectedChanged.listen((
      bool connected,
    ) {
      if (connected) {
        unawaited(syncNow());
      }
    });
    // Cold-start: a device already online when the engine starts gets no
    // connectivity transition, so kick a best-effort sync now. Offline start
    // fails silently and retries on the next connectivity-regained event.
    unawaited(syncNow());
  }

  @override
  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  @override
  Future<void> syncNow() async {
    if (_syncing) {
      return;
    }
    _syncing = true;
    try {
      await flush();
      await pull();
    } catch (error, stackTrace) {
      _report('syncNow', error, stackTrace);
    } finally {
      _syncing = false;
      if (!_firstSync.isCompleted) {
        _firstSync.complete();
      }
    }
  }

  @override
  Future<void> flush() async {
    for (final SyncableTable table in tables) {
      try {
        await _flushTable(table);
      } catch (error, stackTrace) {
        _report('flush ${table.name}', error, stackTrace);
      }
    }
  }

  @override
  Future<void> pull() async {
    for (final SyncableTable table in tables) {
      try {
        await _pullTable(table);
      } catch (error, stackTrace) {
        _report('pull ${table.name}', error, stackTrace);
      }
    }
  }

  Future<void> _flushTable(SyncableTable table) async {
    // Scope to the signed-in user: the local DB is shared across accounts on a
    // device, so a prior user's dirty rows must never be pushed under this
    // user's JWT (RLS would reject the whole batch).
    final List<QueryRow> dirty = await db
        .customSelect(
          'SELECT * FROM ${table.name} '
          'WHERE dirty = 1 AND ${table.ownerColumn} = ?',
          variables: <Variable<Object>>[Variable<String>(userId)],
        )
        .get();
    if (dirty.isEmpty) {
      return;
    }

    final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
    final Map<String, Map<String, Object?>> payloadById =
        <String, Map<String, Object?>>{};
    final List<_DirtyRef> refs = <_DirtyRef>[];
    for (final QueryRow row in dirty) {
      final Map<String, Object?> data = Map<String, Object?>.of(row.data);
      refs.add(_DirtyRef(data['id']! as String, data['updated_at'] as String?));
      for (final String col in _localOnlyColumns) {
        data.remove(col);
      }
      for (final String col in _jsonColumns) {
        final Object? value = data[col];
        if (value is String) data[col] = jsonDecode(value);
      }
      payloads.add(data);
      payloadById[data['id']! as String] = data;
    }

    final List<Map<String, Object?>> accepted = await gateway.push(
      table.name,
      payloads,
      insertOnly: table.insertOnly,
    );
    if (table.insertOnly) {
      await _markSynced(table, refs);
      return;
    }
    for (final Map<String, Object?> row in accepted) {
      final String? id = row['id'] as String?;
      if (id == null) continue;
      final Map<String, Object?>? pushed = payloadById[id];
      final DateTime? remoteUpdated = _parseDate(row['updated_at']);
      if (remoteUpdated == null) continue;
      final _LocalVersion? current = await _localVersion(table.name, id);
      if (current != null &&
          current.dirty &&
          refs.any(
            (_DirtyRef ref) =>
                ref.id == id && ref.updatedAt != current.updatedAtIso,
          )) {
        continue;
      }
      final bool serverAcceptedPayload =
          pushed != null && _sameServerPayload(pushed, row);
      if (serverAcceptedPayload ||
          await _remoteWins(table.name, id, remoteUpdated)) {
        await _applyRemote(table.name, row);
      }
    }
    await _markSynced(table, refs);
  }

  /// Clear `dirty` only for rows whose version still matches what was pushed.
  /// A local edit landing during the in-flight push bumps `updated_at`, so its
  /// `(id, updated_at)` no longer matches — it stays dirty and retries on the
  /// next flush instead of being silently marked clean with an unsent payload.
  Future<void> _markSynced(SyncableTable table, List<_DirtyRef> refs) async {
    final List<String> conditions = <String>[];
    final List<Variable<Object>> variables = <Variable<Object>>[
      Variable<String>(_clock().toIso8601String()),
      Variable<String>(userId),
    ];
    for (final _DirtyRef ref in refs) {
      if (ref.updatedAt != null) {
        conditions.add('(id = ? AND updated_at = ?)');
        variables
          ..add(Variable<String>(ref.id))
          ..add(Variable<String>(ref.updatedAt!));
      } else {
        conditions.add('(id = ?)');
        variables.add(Variable<String>(ref.id));
      }
    }
    await db.customUpdate(
      'UPDATE ${table.name} SET dirty = 0, synced_at = ? '
      'WHERE ${table.ownerColumn} = ? AND (${conditions.join(' OR ')})',
      variables: variables,
      updates: _updatesFor(table.name),
    );
  }

  /// The drift table object(s) a raw write touches, so dependent query-streams
  /// (`watchAll`, etc.) re-run after a flush/pull mutation.
  Set<ResultSetImplementation<dynamic, dynamic>> _updatesFor(String tableName) {
    for (final TableInfo<Table, dynamic> info in db.allTables) {
      if (info.actualTableName == tableName) {
        return <ResultSetImplementation<dynamic, dynamic>>{info};
      }
    }
    return const <ResultSetImplementation<dynamic, dynamic>>{};
  }

  Future<void> _pullTable(SyncableTable table) async {
    final DateTime? since = await _lastPull(table.name);
    final DateTime? querySince = since?.subtract(
      const Duration(milliseconds: 1),
    );
    final List<Map<String, Object?>> remote = await gateway.pull(
      table.name,
      userId: userId,
      since: querySince,
    );
    if (remote.isEmpty) {
      return;
    }

    DateTime? maxUpdated = since;
    for (final Map<String, Object?> row in remote) {
      final DateTime remoteUpdated = _parseDate(row['updated_at'])!;
      if (await _remoteWins(table.name, row['id']! as String, remoteUpdated)) {
        await _applyRemote(table.name, row);
      }
      if (maxUpdated == null || remoteUpdated.isAfter(maxUpdated)) {
        maxUpdated = remoteUpdated;
      }
    }

    if (maxUpdated != null) {
      await _setLastPull(table.name, maxUpdated);
    }
  }

  bool _sameServerPayload(
    Map<String, Object?> pushed,
    Map<String, Object?> accepted,
  ) {
    for (final MapEntry<String, Object?> entry in pushed.entries) {
      final String key = entry.key;
      if (key == 'updated_at' || key == 'created_at') continue;
      if (!_sameJsonValue(entry.value, accepted[key])) {
        return false;
      }
    }
    return true;
  }

  bool _sameJsonValue(Object? left, Object? right) {
    Object? normalize(Object? value) {
      if (value is DateTime) return value.toUtc().toIso8601String();
      if (value is Map || value is List) return jsonEncode(value);
      return value;
    }

    return normalize(left) == normalize(right);
  }

  /// Last-write-wins on the pull side. The incoming row is applied unless the
  /// LOCAL row has un-pushed edits (`dirty`) that are strictly newer — in which
  /// case the local edit is kept and will push on the next flush. On a tie the
  /// incoming (server-arbitrated) row wins (SCHEMA.md §Sync).
  Future<bool> _remoteWins(
    String tableName,
    String id,
    DateTime remoteUpdated,
  ) async {
    final List<QueryRow> rows = await db
        .customSelect(
          'SELECT updated_at, dirty FROM $tableName WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(id)],
        )
        .get();
    if (rows.isEmpty) {
      return true;
    }
    final QueryRow local = rows.first;
    final bool localDirty = (local.data['dirty'] as int? ?? 0) != 0;
    final DateTime? localUpdated = _parseDate(local.data['updated_at']);
    if (localDirty &&
        localUpdated != null &&
        localUpdated.isAfter(remoteUpdated)) {
      return false;
    }
    return true;
  }

  Future<_LocalVersion?> _localVersion(String tableName, String id) async {
    final List<QueryRow> rows = await db
        .customSelect(
          'SELECT updated_at, dirty FROM $tableName WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(id)],
        )
        .get();
    if (rows.isEmpty) return null;
    final QueryRow row = rows.first;
    return _LocalVersion(
      updatedAtIso: row.data['updated_at']?.toString(),
      dirty: (row.data['dirty'] as int? ?? 0) != 0,
    );
  }

  Future<void> _applyRemote(String tableName, Map<String, Object?> row) async {
    final Map<String, Object?> data = Map<String, Object?>.of(row);
    // Stamp local bookkeeping: a pulled row is clean and now synced.
    data['dirty'] = 0;
    data['synced_at'] = _clock().toIso8601String();

    final List<String> columns = data.keys.toList(growable: false);
    final String placeholders = List<String>.filled(
      columns.length,
      '?',
    ).join(', ');
    final List<Variable<Object>> variables = columns
        .map((String col) => Variable<Object>(_toSqlite(col, data[col])))
        .toList(growable: false);

    await db.customInsert(
      'INSERT OR REPLACE INTO $tableName (${columns.join(', ')}) '
      'VALUES ($placeholders)',
      variables: variables,
      updates: _updatesFor(tableName),
    );
  }

  /// Coerce a remote value into the sqlite representation of the local column.
  /// Handles both real-Supabase shapes (bool, decoded JSON objects) and the
  /// already-sqlite shapes a fake gateway echoes back (int bools, JSON strings).
  Object? _toSqlite(String column, Object? value) {
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value ? 1 : 0;
    }
    if (_jsonColumns.contains(column) && value is! String) {
      return jsonEncode(value);
    }
    return value;
  }

  DateTime? _parseDate(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.tryParse(value.toString());
  }

  Future<DateTime?> _lastPull(String tableName) async {
    final SyncMetaData? row = await (db.select(
      db.syncMeta,
    )..where((SyncMeta m) => m.syncTable.equals(tableName))).getSingleOrNull();
    return row?.lastPull;
  }

  Future<void> _setLastPull(String tableName, DateTime value) async {
    await db
        .into(db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            syncTable: tableName,
            lastPull: Value<DateTime>(value),
          ),
        );
  }

  void _report(String op, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('SyncEngine: $op failed (retried later): $error');
    }
  }
}

/// A snapshot of a dirty row's identity and version at push time, used to
/// acknowledge (`dirty = 0`) only the exact version that was sent.
class _DirtyRef {
  const _DirtyRef(this.id, this.updatedAt);
  final String id;
  final String? updatedAt;
}

class _LocalVersion {
  const _LocalVersion({required this.updatedAtIso, required this.dirty});

  final String? updatedAtIso;
  final bool dirty;
}

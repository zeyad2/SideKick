import 'package:supabase_flutter/supabase_flutter.dart';

/// The network boundary of sync, behind an interface so the engine is
/// stub-able in tests (a `FakeSyncGateway` replaces this).
///
/// Rows are neutral JSON maps keyed by snake_case column name — the same names
/// on both the drift mirror and Postgres.
abstract interface class SyncGateway {
  /// Push local rows for [table].
  ///
  /// * Normal tables: an LWW-guarded UPSERT. PostgREST issues a plain upsert;
  ///   the server-side `sync_lww_guard` trigger (migration 0003) rejects a
  ///   pushed row whose `updated_at` is older than the stored row and clamps a
  ///   future `updated_at` to `now()` (clock-skew guard) — SCHEMA.md §Sync.
  /// * [insertOnly] tables (`events`): an idempotent insert (`ON CONFLICT DO
  ///   NOTHING`) — rows are immutable and client-id'd, so a duplicate id on
  ///   retry is a no-op and existing data is never overwritten (D9).
  Future<void> push(
    String table,
    List<Map<String, Object?>> rows, {
    required bool insertOnly,
  });

  /// Pull rows for [table] updated since [since] (exclusive), owned by
  /// [userId]. `null` [since] pulls everything. Includes tombstoned rows
  /// (`deleted_at` set) so deletes propagate.
  Future<List<Map<String, Object?>>> pull(
    String table, {
    required String userId,
    DateTime? since,
  });
}

/// Supabase-backed [SyncGateway]. Isolates every PostgREST call so the rest of
/// the app never touches Supabase types directly.
///
/// Booleans are stored as int 0/1 in sqlite; this gateway coerces them to real
/// JSON booleans for the known bool columns before pushing, and datetimes are
/// already ISO-8601 text (store_date_time_values_as_text), which Postgres
/// `timestamptz` accepts directly.
class SupabaseSyncGateway implements SyncGateway {
  SupabaseSyncGateway(this._client);

  final SupabaseClient _client;

  /// Columns stored as int 0/1 locally that are `boolean` in Postgres.
  static const Set<String> _boolColumns = <String>{
    'blocking_enabled',
    'reset_active',
    'archived',
  };

  Map<String, Object?> _coerceForPush(Map<String, Object?> row) {
    final Map<String, Object?> out = Map<String, Object?>.of(row);
    for (final String col in _boolColumns) {
      final Object? value = out[col];
      if (value is int) {
        out[col] = value != 0;
      }
    }
    return out;
  }

  @override
  Future<void> push(
    String table,
    List<Map<String, Object?>> rows, {
    required bool insertOnly,
  }) async {
    if (rows.isEmpty) {
      return;
    }
    final List<Map<String, Object?>> payload =
        rows.map(_coerceForPush).toList(growable: false);
    if (insertOnly) {
      // Idempotent insert: a retry after a committed-but-unacknowledged push
      // (crash between the server commit and the local `dirty` clear) must not
      // fail on the duplicate client-generated id. `ON CONFLICT DO NOTHING`
      // ignores an already-present event without ever overwriting it, so the
      // immutable append-only contract (D9) holds. Non-`events` LWW arbitration
      // and the clock-skew clamp are enforced server-side by the
      // `sync_lww_guard` trigger (0003), so a plain upsert is safe here.
      await _client
          .from(table)
          .upsert(payload, ignoreDuplicates: true, onConflict: 'id');
    } else {
      await _client.from(table).upsert(payload);
    }
  }

  @override
  Future<List<Map<String, Object?>>> pull(
    String table, {
    required String userId,
    DateTime? since,
  }) async {
    // RLS already scopes to the owner; the explicit filter keeps intent clear.
    final String ownerColumn = table == 'profiles' ? 'id' : 'user_id';
    var query = _client.from(table).select().eq(ownerColumn, userId);
    if (since != null) {
      query = query.gt('updated_at', since.toUtc().toIso8601String());
    }
    final List<Map<String, Object?>> rows = await query.order('updated_at');
    return rows;
  }
}

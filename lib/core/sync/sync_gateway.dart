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
  ///   the server-side `sync_lww_guard` trigger in the POC baseline rejects a
  ///   pushed row whose `updated_at` is older than the stored row and clamps a
  ///   future `updated_at` to `now()` (clock-skew guard) — SCHEMA.md §Sync.
  /// * [insertOnly] tables (`events`, `reminder_events`): an idempotent insert (`ON CONFLICT DO
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
/// Datetimes are already ISO-8601 text (store_date_time_values_as_text), which
/// Postgres `timestamptz` accepts directly.
class SupabaseSyncGateway implements SyncGateway {
  SupabaseSyncGateway(this._client);

  final SupabaseClient _client;

  Map<String, Object?> _coerceForPush(Map<String, Object?> row) {
    return Map<String, Object?>.of(row);
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
    final List<Map<String, Object?>> payload = rows
        .map(_coerceForPush)
        .toList(growable: false);
    if (insertOnly) {
      // Idempotent insert: a retry after a committed-but-unacknowledged push
      // (crash between the server commit and the local `dirty` clear) must not
      // fail on the duplicate client-generated id. `ON CONFLICT DO NOTHING`
      // ignores an already-present event without ever overwriting it, so the
      // immutable append-only contract (D9) holds. LWW arbitration and the
      // clock-skew clamp for normal tables are enforced server-side by the
      // `sync_lww_guard` trigger in the POC baseline, so a plain upsert is
      // safe outside the insert-only path.
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

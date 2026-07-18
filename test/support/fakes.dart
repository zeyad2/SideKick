import 'dart:async';

import 'package:sidekick/core/auth/auth_repository.dart';
import 'package:sidekick/core/sync/sync_gateway.dart';

/// A record of one [SyncGateway.push] call.
class PushCall {
  PushCall(this.table, this.rows, this.insertOnly);
  final String table;
  final List<Map<String, Object?>> rows;
  final bool insertOnly;
}

/// In-memory [SyncGateway] for sync tests. Push stores rows by id in a
/// per-table remote store (so a later pull can serve them back), and records
/// every push so tests can assert insert-only / payload shape.
class FakeSyncGateway implements SyncGateway {
  final List<PushCall> pushes = <PushCall>[];
  final Map<String, Map<String, Map<String, Object?>>> remote =
      <String, Map<String, Map<String, Object?>>>{};

  /// Optional hook awaited in the middle of a [push] (after it is recorded,
  /// before the local ack runs). Lets a test inject a concurrent local edit
  /// while a flush is "in flight" over the network.
  Future<void> Function()? onPush;

  /// When true, [push] throws — simulating an offline / unreachable server. The
  /// engine swallows the error, so the pushed rows must stay dirty and retry.
  bool failPush = false;

  /// Seed a remote row (as if another device wrote it) for a pull test.
  void seedRemote(String table, Map<String, Object?> row) {
    remote.putIfAbsent(table, () => <String, Map<String, Object?>>{})[
        row['id']! as String] = row;
  }

  @override
  Future<void> push(
    String table,
    List<Map<String, Object?>> rows, {
    required bool insertOnly,
  }) async {
    if (failPush) {
      throw StateError('offline: server unreachable');
    }
    pushes.add(PushCall(table, rows, insertOnly));
    if (onPush != null) {
      await onPush!();
    }
    final Map<String, Map<String, Object?>> store =
        remote.putIfAbsent(table, () => <String, Map<String, Object?>>{});
    for (final Map<String, Object?> row in rows) {
      store[row['id']! as String] = row;
    }
  }

  @override
  Future<List<Map<String, Object?>>> pull(
    String table, {
    required String userId,
    DateTime? since,
  }) async {
    final Iterable<Map<String, Object?>> rows =
        remote[table]?.values ?? const <Map<String, Object?>>[];
    return rows.where((Map<String, Object?> row) {
      if (since == null) {
        return true;
      }
      final DateTime updated = DateTime.parse(row['updated_at']! as String);
      return updated.isAfter(since);
    }).toList(growable: false);
  }
}

/// Configurable [AuthRepository] for widget/gate tests. No Supabase involved.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this._state);

  FakeAuthRepository.signedIn(String userId)
    : _state = SessionState(phase: AuthPhase.signedIn, userId: userId);

  FakeAuthRepository.signedOut() : _state = const SessionState.signedOut();

  SessionState _state;
  final StreamController<SessionState> _controller =
      StreamController<SessionState>.broadcast();

  @override
  SessionState get current => _state;

  @override
  Stream<SessionState> watch() async* {
    yield _state;
    yield* _controller.stream;
  }

  void emit(SessionState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    emit(const SessionState(phase: AuthPhase.signedIn, userId: 'fake-user'));
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    emit(const SessionState(phase: AuthPhase.signedIn, userId: 'fake-user'));
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    lastPasswordResetEmail = email;
  }

  /// The email passed to the most recent [sendPasswordReset], for assertions.
  String? lastPasswordResetEmail;

  @override
  Future<void> signOut() async => emit(const SessionState.signedOut());
}

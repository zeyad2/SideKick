import 'package:meta/meta.dart';
import 'package:sidekick/core/capture/capture_ingestion_barrier.dart';
import 'package:sidekick/core/db/app_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where the user is in the auth lifecycle. `unknown` only appears before the
/// first state is known; a restored offline session resolves straight to
/// [signedIn] with no network round-trip.
enum AuthPhase { unknown, signedIn, signedOut }

@immutable
class SessionState {
  const SessionState({required this.phase, this.userId, this.email});

  const SessionState.signedOut()
    : phase = AuthPhase.signedOut,
      userId = null,
      email = null;

  final AuthPhase phase;
  final String? userId;
  final String? email;

  bool get isSignedIn => phase == AuthPhase.signedIn && userId != null;
}

/// Auth + session accessor. Uses Supabase **email + password** for explicit
/// account creation (no email verification — the onboarding is deliberately
/// low-friction for the ADHD audience). Google sign-in is a planned addition
/// (native `signInWithIdToken`) and is stubbed but disabled in the UI until the
/// Google Cloud console + native setup lands. See docs/DATA_CONTRACT.md §5.
abstract interface class AuthRepository {
  /// The current session, read SYNCHRONOUSLY from the cached (restored)
  /// session — never a network call. This is what lets the app open offline
  /// without a spinner-lock.
  SessionState get current;

  /// Auth state changes (sign-in, sign-out, token refresh), seeded with
  /// [current].
  Stream<SessionState> watch();

  /// Create a new account with [email] + [password] and establish a session.
  ///
  /// Assumes Supabase "Confirm email" is OFF (our decision: no verification),
  /// so sign-up returns a session immediately. If confirmation is ever turned
  /// back on, no session is returned and this throws to surface the misconfig
  /// rather than silently leaving the user signed out.
  Future<void> signUpWithPassword({
    required String email,
    required String password,
  });

  /// Sign in to an existing account with [email] + [password].
  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  /// Send a password-reset email to [email]. Always resolves without revealing
  /// whether the address has an account (Supabase does not disclose this), so
  /// the UI shows the same "check your inbox" message either way. Completing the
  /// reset (following the emailed link back into the app to set a new password)
  /// needs deep-link handling that is not wired yet — see techdebt.md.
  Future<void> sendPasswordReset({required String email});

  /// End the session AND wipe all local data. The local DB is shared across
  /// accounts on a device, so sign-out clears every synced row and the pull
  /// cursor — otherwise the next account inherits the previous user's rows and
  /// a stale cursor that makes it under-pull its own data.
  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._auth, this._db, this._captureBarrier);

  final GoTrueClient _auth;
  final AppDatabase _db;
  final CaptureIngestionBarrier _captureBarrier;

  SessionState _fromSession(Session? session) {
    if (session == null) {
      return const SessionState.signedOut();
    }
    return SessionState(
      phase: AuthPhase.signedIn,
      userId: session.user.id,
      email: session.user.email,
    );
  }

  @override
  SessionState get current => _fromSession(_auth.currentSession);

  @override
  Stream<SessionState> watch() async* {
    yield current;
    yield* _auth.onAuthStateChange.map(
      (AuthState state) => _fromSession(state.session),
    );
  }

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    final AuthResponse response = await _auth.signUp(
      email: email,
      password: password,
    );
    // With email confirmation disabled Supabase returns a live session here and
    // onAuthStateChange flips the app to signed-in. A null session means
    // confirmation is (unexpectedly) enabled — fail loudly instead of stranding
    // the user on a screen that looks like nothing happened.
    if (response.session == null) {
      throw const AuthException(
        'Account created but sign-in did not complete. '
        'Email confirmation must be disabled for this app.',
      );
    }
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) => _auth.signInWithPassword(email: email, password: password);

  @override
  Future<void> sendPasswordReset({required String email}) =>
      _auth.resetPasswordForEmail(email);

  @override
  Future<void> signOut() async {
    await _captureBarrier.closeAndDrain();
    try {
      // End the session first so no in-flight sync can re-populate the tables
      // under the outgoing user's JWT, then clear the shared local store.
      await _auth.signOut();
      await _db.wipeAllData();
    } finally {
      _captureBarrier.reopen();
    }
  }
}

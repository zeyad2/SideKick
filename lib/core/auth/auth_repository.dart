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

/// Auth + session accessor. Uses Supabase email OTP with a **6-digit code**
/// (not magic-link): a code typed back into the app needs no deep-link /
/// universal-link plumbing, which suits the personal build. See
/// docs/DATA_CONTRACT.md.
abstract interface class AuthRepository {
  /// The current session, read SYNCHRONOUSLY from the cached (restored)
  /// session — never a network call. This is what lets the app open offline
  /// without a spinner-lock.
  SessionState get current;

  /// Auth state changes (sign-in, sign-out, token refresh), seeded with
  /// [current].
  Stream<SessionState> watch();

  /// Send a 6-digit OTP code to [email].
  Future<void> sendOtp(String email);

  /// Verify the 6-digit [token] for [email], establishing a session.
  Future<void> verifyOtp({required String email, required String token});

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
  Future<void> sendOtp(String email) =>
      _auth.signInWithOtp(email: email, shouldCreateUser: true);

  @override
  Future<void> verifyOtp({required String email, required String token}) =>
      _auth.verifyOTP(email: email, token: token, type: OtpType.email);

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

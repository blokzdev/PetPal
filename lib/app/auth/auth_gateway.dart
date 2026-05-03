import 'dart:async';

import 'app_auth_session.dart';

/// Phase 7 task H.1 — abstract auth surface.
///
/// Production implementation is [SupabaseAuthGateway]; tests use
/// [InMemoryAuthGateway]. Mirrors the Phase 7 G.2 SyncBackend
/// abstraction pattern: the rest of the app depends only on this
/// interface, so the `supabase_flutter` package import is contained
/// in one file.
///
/// **Magic-link flow.** Per DECISIONS row 70 + row 82, the sign-in
/// path is a magic link emailed via Supabase Auth's `signInWithOtp`
/// (60-min link expiration, no password). The user taps the link,
/// returns to PetPal via the deep-link intent filter (manifest
/// `petpal://login-callback`), and `supabase_flutter`'s built-in
/// `app_links` integration resolves the redirect into a populated
/// session. Consumers watch [onSessionChange] to react.
abstract class AuthGateway {
  /// Currently-authenticated session, if any. Sync getter — backed
  /// by an in-memory cache; safe to call from build methods.
  AppAuthSession? get currentSession;

  /// Stream of session transitions. Emits the new value (including
  /// null on sign-out / token expiry). Multi-listener safe.
  Stream<AppAuthSession?> get onSessionChange;

  /// Send a magic-link email to [email]. Returns when the email has
  /// been queued for delivery (Supabase 200 response). Does NOT
  /// indicate the user has signed in — that arrives via
  /// [onSessionChange] after the user taps the link and returns.
  ///
  /// [emailRedirectTo] is the deep-link URL the magic link redirects
  /// to (e.g. `petpal://login-callback`). The deep-link scheme is
  /// registered in `android/app/src/main/AndroidManifest.xml`.
  ///
  /// Throws [AuthGatewayException] on Supabase error. Validation of
  /// [email] (format / non-empty) is the caller's responsibility.
  Future<void> sendMagicLink({
    required String email,
    required String emailRedirectTo,
  });

  /// Sign out the current user. Clears the local session, fires a
  /// `null` event on [onSessionChange]. Idempotent — safe to call
  /// when already signed out.
  Future<void> signOut();
}

/// Common exception type for any Supabase-side auth failure.
/// Production [SupabaseAuthGateway] wraps `AuthException` /
/// network failures into this; the UI maps it onto VOICE.md §6
/// register copy.
class AuthGatewayException implements Exception {
  const AuthGatewayException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'AuthGatewayException: $message'
      '${cause != null ? ' (cause: $cause)' : ''}';
}

/// Phase 7 task H.1 — test fake. Holds session state in memory;
/// supports scripted magic-link "delivery" for sign-in flow tests.
///
/// Usage:
/// ```dart
/// final gateway = InMemoryAuthGateway();
/// gateway.scriptMagicLinkAccept(
///   AppAuthSession(userId: 'u1', email: 'a@b.com', ...),
/// );
/// await gateway.sendMagicLink(email: 'a@b.com', emailRedirectTo: '...');
/// // session is now populated; onSessionChange has fired.
/// ```
///
/// Without a scripted accept, [sendMagicLink] queues the email but
/// does NOT change the session — matching production behaviour
/// where the user must tap the link. Tests that need to simulate
/// the deep-link return call [simulateDeepLinkSignIn] explicitly.
class InMemoryAuthGateway implements AuthGateway {
  InMemoryAuthGateway({AppAuthSession? initial}) : _session = initial;

  AppAuthSession? _session;
  final _controller = StreamController<AppAuthSession?>.broadcast();
  AppAuthSession? _scriptedAccept;
  String? _lastSentEmail;
  String? _lastEmailRedirectTo;
  int _sendMagicLinkCount = 0;
  Object? _scriptedSendError;

  /// Pre-arrange a session that will be installed automatically the
  /// next time [sendMagicLink] is called. Mirrors the production
  /// happy path (user receives + clicks link before the test runs
  /// further assertions).
  void scriptMagicLinkAccept(AppAuthSession session) {
    _scriptedAccept = session;
  }

  /// Pre-arrange a thrown error from the next [sendMagicLink] call.
  /// Cleared after one trip.
  void scriptSendError(Object error) {
    _scriptedSendError = error;
  }

  /// Manually fire the deep-link return path (matches the production
  /// `onAuthStateChange.signedIn` event). Use when a test wants to
  /// drive the timing explicitly instead of relying on
  /// [scriptMagicLinkAccept].
  void simulateDeepLinkSignIn(AppAuthSession session) {
    _session = session;
    _controller.add(session);
  }

  /// Manually fire a session-expiry event without going through the
  /// sign-out path (e.g. to test refresh-window UX).
  void simulateSessionExpired() {
    _session = null;
    _controller.add(null);
  }

  // --- AuthGateway ---

  @override
  AppAuthSession? get currentSession => _session;

  @override
  Stream<AppAuthSession?> get onSessionChange => _controller.stream;

  @override
  Future<void> sendMagicLink({
    required String email,
    required String emailRedirectTo,
  }) async {
    _sendMagicLinkCount++;
    _lastSentEmail = email;
    _lastEmailRedirectTo = emailRedirectTo;
    final err = _scriptedSendError;
    if (err != null) {
      _scriptedSendError = null;
      throw err;
    }
    final scripted = _scriptedAccept;
    if (scripted != null) {
      _scriptedAccept = null;
      _session = scripted;
      _controller.add(scripted);
    }
  }

  @override
  Future<void> signOut() async {
    if (_session == null) return;
    _session = null;
    _controller.add(null);
  }

  // --- Test introspection ---

  String? get lastSentEmail => _lastSentEmail;
  String? get lastEmailRedirectTo => _lastEmailRedirectTo;
  int get sendMagicLinkCount => _sendMagicLinkCount;

  /// Release stream resources (call from test teardown).
  Future<void> dispose() async {
    await _controller.close();
  }
}

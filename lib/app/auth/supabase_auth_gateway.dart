import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_auth_session.dart';
import 'auth_gateway.dart';

/// Phase 7 task H.1 — production [AuthGateway] backed by
/// `supabase_flutter`'s `Supabase.instance.client.auth`.
///
/// Constructor accepts the `GoTrueClient` so tests can swap a fake
/// in if needed; production callers pass `Supabase.instance.client.auth`
/// after `Supabase.initialize()` has run in `main()`.
///
/// Deep-link handling is automatic: `Supabase.initialize()` registers
/// an `app_links` listener that resolves the magic-link callback URL
/// (per the manifest intent filter) into a fresh session, fires a
/// `signedIn` event on `onAuthStateChange`, and that flows out
/// through [onSessionChange] without needing any per-activity glue.
class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._auth);

  final GoTrueClient _auth;
  StreamSubscription<AuthState>? _sub;
  final _controller = StreamController<AppAuthSession?>.broadcast(
    onListen: () {},
    onCancel: () {},
  );

  /// Wire the underlying Supabase auth-state stream into our domain
  /// stream. Call once after construction; safe to call again
  /// (idempotent — re-subscribing cancels the prior subscription).
  void initialize() {
    _sub?.cancel();
    _sub = _auth.onAuthStateChange.listen((event) {
      _controller.add(_toAppSession(event.session));
    });
  }

  @override
  AppAuthSession? get currentSession => _toAppSession(_auth.currentSession);

  @override
  Stream<AppAuthSession?> get onSessionChange => _controller.stream;

  @override
  Future<void> sendMagicLink({
    required String email,
    required String emailRedirectTo,
  }) async {
    try {
      await _auth.signInWithOtp(
        email: email,
        emailRedirectTo: emailRedirectTo,
      );
    } on AuthException catch (e) {
      throw AuthGatewayException(e.message, cause: e);
    } catch (e) {
      throw AuthGatewayException(
        'Could not send the sign-in email. Check your connection and try again.',
        cause: e,
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on AuthException catch (e) {
      throw AuthGatewayException(e.message, cause: e);
    } catch (e) {
      throw AuthGatewayException(
        'Sign-out failed. The local session was cleared regardless.',
        cause: e,
      );
    }
  }

  /// Release stream subscriptions (call from app teardown / hot
  /// restart). Production app rarely tears down — Supabase's auth
  /// client lives for the process lifetime — so this is here for
  /// test hygiene.
  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }

  static AppAuthSession? _toAppSession(Session? s) {
    if (s == null) return null;
    return AppAuthSession(
      userId: s.user.id,
      email: s.user.email,
      accessToken: s.accessToken,
      // Supabase reports `expiresAt` in seconds-since-epoch; convert
      // to a Dart DateTime. Falls back to "1 hour from now" if the
      // field is somehow missing (defensive — should never happen
      // for a populated Session).
      expiresAt: s.expiresAt != null
          ? DateTime.fromMillisecondsSinceEpoch(s.expiresAt! * 1000)
          : DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

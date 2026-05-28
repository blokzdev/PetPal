import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_auth_session.dart';
import 'auth_gateway.dart';

/// Phase 7 task H.1 — magic-link redirect URL.
///
/// Locked to `petpal://login-callback`. Registered in
/// `android/app/src/main/AndroidManifest.xml` (intent filter under
/// `MainActivity`) and supplied to `signInWithOtp` via
/// [AuthGateway.sendMagicLink]'s `emailRedirectTo` parameter.
///
/// **Must also be added to Supabase Auth → Settings → "Additional
/// redirect URLs"** in the dashboard, otherwise Supabase rejects
/// the magic-link redirect with `400 invalid_request`. Documented
/// in `docs/SETUP.md`.
const String kMagicLinkRedirectUrl = 'petpal://login-callback';

/// Phase 7 task H.1 — gateway provider seam.
///
/// Default returns an [InMemoryAuthGateway] with no session — keeps
/// tests + pre-Supabase-init runtime safe (chat surface still
/// renders the "sign-in coming" register from F.1, sync card stays
/// in `signedOut` state). `main()` overrides this with a
/// [SupabaseAuthGateway] when `Supabase.initialize()` succeeds.
final authGatewayProvider = Provider<AuthGateway>((ref) {
  final gateway = InMemoryAuthGateway();
  ref.onDispose(gateway.dispose);
  return gateway;
});

/// Phase 7 task H.1 — auth session notifier.
///
/// `AsyncNotifier<AppAuthSession?>` — null state = signed out, data
/// state = signed in. Subscribed to [AuthGateway.onSessionChange] so
/// the deep-link return path (magic-link tap → app reopens →
/// Supabase fires signedIn) updates the notifier without any
/// per-screen plumbing.
///
/// Sub-tasks consume this:
///   - **H.1.b** — `cloudSyncAdapterProvider` watches signed-in
///     userId to construct an [E2eeSyncAdapter] keyed to the right
///     account.
///   - **H.1.c** — `EntitlementNotifier` watches this to fetch the
///     userId-keyed entitlement row from Supabase per row 78.
///   - **H.1.c** — Settings sign-out tile + Plan card render based
///     on this state.
class AuthSessionNotifier extends AsyncNotifier<AppAuthSession?> {
  StreamSubscription<AppAuthSession?>? _sub;

  @override
  Future<AppAuthSession?> build() async {
    final gateway = ref.read(authGatewayProvider);
    await _sub?.cancel();
    _sub = gateway.onSessionChange.listen((session) {
      state = AsyncValue.data(session);
    });
    ref.onDispose(() => _sub?.cancel());
    return gateway.currentSession;
  }

  /// Send a magic link to [email]. UI is responsible for validating
  /// the email format before calling. Throws [AuthGatewayException]
  /// on Supabase error.
  ///
  /// Does NOT change the session — the user must tap the link to
  /// complete sign-in. The deep-link return drives the actual
  /// session update via [AuthGateway.onSessionChange].
  Future<void> sendMagicLink({required String email}) async {
    final gateway = ref.read(authGatewayProvider);
    await gateway.sendMagicLink(
      email: email,
      emailRedirectTo: kMagicLinkRedirectUrl,
    );
  }

  /// Sign out the current user. Idempotent. Stream listener fires
  /// the `null` state transition; we don't need to write `state`
  /// here.
  Future<void> signOut() async {
    final gateway = ref.read(authGatewayProvider);
    await gateway.signOut();
  }
}

final authSessionProvider =
    AsyncNotifierProvider<AuthSessionNotifier, AppAuthSession?>(
  AuthSessionNotifier.new,
);

/// Convenience derived provider — sync getter for "is the user
/// signed in?" — used by widgets that need a quick boolean and
/// don't care about the session payload.
final isSignedInProvider = Provider<bool>((ref) {
  return ref.watch(authSessionProvider).maybeWhen(
        data: (s) => s != null,
        orElse: () => false,
      );
});

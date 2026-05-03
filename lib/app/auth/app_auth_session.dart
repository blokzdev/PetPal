/// Phase 7 task H.1 — domain-layer auth session value type.
///
/// Decoupled from `supabase_flutter`'s `Session` so the rest of the
/// app — entitlement notifier, ProxyTransport user-JWT wiring,
/// sync-card auth state — depends only on the harness, not on the
/// Supabase package. The conversion lives in `SupabaseAuthGateway`.
///
/// Load-bearing fields:
///   - [userId] — Supabase auth UUID; entitlement rows are keyed
///     here per DECISIONS row 78.
///   - [accessToken] — JWT for `ProxyTransport.userJwt` (DECISIONS
///     row 82's signed-in proxy auth path).
///   - [email] — display-only, surfaced in Settings + sign-out
///     confirmation copy.
///   - [expiresAt] — refresh-window math (Phase 7 H.1.c watches
///     this to surface "session expired, sign in again").
class AppAuthSession {
  const AppAuthSession({
    required this.userId,
    required this.email,
    required this.accessToken,
    required this.expiresAt,
  });

  final String userId;
  final String? email;
  final String accessToken;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppAuthSession &&
          other.userId == userId &&
          other.email == email &&
          other.accessToken == accessToken &&
          other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(userId, email, accessToken, expiresAt);

  @override
  String toString() => 'AppAuthSession(userId: $userId, email: $email, '
      'expiresAt: $expiresAt)';
}

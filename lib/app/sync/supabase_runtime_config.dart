import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Phase 7 task H.1.b — runtime Supabase config seam.
///
/// Holds the SUPABASE_URL + anon key supplied via `--dart-define`.
/// Default provider returns `null`, which keeps every dependent
/// surface (sync backend, future ProxyTransport wiring) on its
/// not-yet-configured fallback. `main()` overrides the provider with
/// a populated [SupabaseRuntimeConfig] only when both env vars are
/// present and `Supabase.initialize()` succeeded.
///
/// Why a provider instead of `Supabase.instance.client.realtimeUrl`?
/// Because the client-side path (REST-direct in [SupabaseSyncBackend])
/// doesn't use `Supabase.instance` — it talks to PostgREST + Storage
/// REST endpoints with the URL + anon key as plain strings. Keeping
/// the config in a provider also makes it overridable from tests
/// without standing up the singleton.
class SupabaseRuntimeConfig {
  const SupabaseRuntimeConfig({
    required this.url,
    required this.anonKey,
  });

  /// Supabase project URL, e.g. `https://abcdefgh.supabase.co`.
  /// Trailing slash is stripped by consumers — pass either form.
  final String url;

  /// Supabase anon public key. Safe to embed in the client; RLS does
  /// the actual gating per DECISIONS row 82.
  final String anonKey;
}

final supabaseRuntimeConfigProvider =
    Provider<SupabaseRuntimeConfig?>((ref) => null);

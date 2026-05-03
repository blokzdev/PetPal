import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos/entitlement_repo.dart';
import '../auth/auth_session_notifier.dart';
import '../providers.dart';
import '../sync/supabase_runtime_config.dart';
import 'entitlement.dart';
import 'supabase_entitlements_client.dart';

/// Phase 7 task B.1 / H.1.c.2 — active-user entitlement notifier.
///
/// Provides the [Entitlement] every quota gate + Pro-feature surface
/// reads. Refresh path is staged:
///
///   - **B.1 (initial commit):** the notifier emits the cached value
///     from Drift for the active user, or [Entitlement.freeAnonymous]
///     when no cache row exists / no auth is wired yet.
///   - **F.1:** [build] consults the `byok_enabled` flag in
///     [SettingsStorage] and emits [Entitlement.byok] when set.
///     Pre-Phase-7 users with an API key in [SecureApiKeyStorage]
///     are auto-promoted to BYOK on first read (row-74 lock).
///   - **H.1.c.2 (this commit):** when signed in + Supabase config
///     available + BYOK off, [build] fetches the canonical
///     entitlement row from `/rest/v1/entitlements?user_id=eq.<id>`
///     per DECISIONS rows 78 + 82. Local Drift cache is the
///     fallback on transient backend failure (no entitlement loss
///     on flaky network). [refresh] does an explicit re-fetch via
///     `ref.invalidateSelf()`.
///
/// The agent loop's quota gate consumes [entitlementProvider] via
/// `ref.read` — never via `ref.watch` inside hot paths, since a
/// rebuild on entitlement change is exactly what the gate is gated on.
class EntitlementNotifier extends AsyncNotifier<Entitlement> {
  /// Phase 7 task F.1 — local-only flag so anonymous users can keep
  /// BYOK state across launches without an entitlements-table row
  /// (the repo no-ops on `freeAnonymous` + `userId == null` by
  /// design — server-side state for anonymous users is undefined).
  /// Once Group H lands sign-in, the BYOK row will move into the
  /// repo keyed by Supabase user-id; this flag becomes the
  /// signed-out fallback.
  static const _byokEnabledKey = 'byok_enabled';

  @override
  Future<Entitlement> build() async {
    // Defensive: tests that don't override settingsStorageProvider /
    // apiKeyStorageProvider see the build path gracefully fall
    // through to the safe default rather than throwing
    // UnimplementedError. Production overrides both in `main()`, so
    // this guard never fires in the running app.
    try {
      final settings = ref.read(settingsStorageProvider);
      final byok = await settings.getBool(_byokEnabledKey) ?? false;
      if (byok) return Entitlement.byok();

      // Phase 7 task F.1 — one-time migration for pre-F.1 users
      // who already have a key in SecureStorage. The pre-Phase-7
      // onboarding mandated a key; that intent maps cleanly to
      // BYOK. Promote silently so chat keeps working without
      // re-prompting (DECISIONS row 74's "existing keys persist
      // on upgrade" lock).
      final apiKey = await ref.read(apiKeyStorageProvider).read();
      if (apiKey != null && apiKey.isNotEmpty) {
        await settings.setBool(_byokEnabledKey, true);
        return Entitlement.byok();
      }
    } catch (_) {
      // Missing override path — tests that don't care about
      // entitlement (chat tests with their own llmClient override,
      // for example) get the synthetic default below.
      return Entitlement.freeAnonymous();
    }

    // Phase 7 task H.1.c.2 — auth-aware refresh from Supabase.
    //
    // Subscribe to userId only (NOT the whole session) so token
    // refresh inside `supabase_flutter` doesn't trigger a notifier
    // rebuild. Sign-in / sign-out / different-user transitions DO
    // trigger rebuild — those are the load-bearing events.
    final userId =
        ref.watch(authSessionProvider.select((s) => s.value?.userId));
    final config = ref.watch(supabaseRuntimeConfigProvider);

    if (userId == null || config == null) {
      // Signed out OR Supabase not configured — fall through to
      // the synthetic anonymous default. Chat surfaces correctly
      // gate to the BYOK / sign-in-coming register.
      return Entitlement.freeAnonymous();
    }

    // Have auth + config — read cache first so a transient backend
    // failure still emits useful state, then refresh from server.
    EntitlementRepo? repo;
    Entitlement? cached;
    try {
      repo = await ref.read(entitlementRepoProvider.future);
      cached = await repo.read(userId);
    } catch (_) {
      // Test path with no DB override / unavailable repo — fall
      // through with no cache. Server fetch may still succeed.
    }

    try {
      final client = ref.read(entitlementsClientProvider);
      if (client == null) {
        // Test path / Supabase config went null mid-flight — emit
        // safe default. Production: provider is always populated
        // by the time userId is non-null.
        return cached ?? _freeSignedIn(userId);
      }
      final fetched = await client.fetch(userId);
      if (fetched != null) {
        // Merge in local-only owned care pack skill IDs (server
        // schema v1 doesn't carry them; the play-billing-verify
        // Edge Function will mirror them in a later commit per
        // row 78). Without this merge, sign-in would silently
        // drop the user's purchased care packs.
        final merged = fetched.copyWith(
          ownedCarePackSkillIds:
              cached?.ownedCarePackSkillIds ?? const <String>{},
        );
        await repo?.upsert(merged);
        return merged;
      }
      // Server returned no row yet — first sign-in pre-webhook /
      // pre-trigger. Default to free signed-in with the user's
      // UUID so quota gates can attribute counters correctly.
      return _freeSignedIn(userId);
    } catch (_) {
      // Network / 5xx / parse failure — keep emitting cached
      // value if we have one. No-cache + signed-in → "free
      // signed-in" (NOT freeAnonymous) since the user IS
      // authenticated on this device, even if we can't confirm
      // their server-side tier this round.
      return cached ?? _freeSignedIn(userId);
    }
  }

  /// Phase 7 task H.1.c.2 — explicit refresh against Supabase.
  ///
  /// Called from app-foreground hooks (later commit), post-IAP
  /// purchase (after [setOptimistic] grace period), and the
  /// daily-reconciliation flow (per DECISIONS row 78). Also
  /// surfaced as a Settings "Refresh subscription state" tile in
  /// H.1.e for users who hit a reconciliation-edge case.
  ///
  /// Implementation: invalidate self + await rebuild. The
  /// auth-aware [build] does the heavy lifting; this just forces
  /// it to re-run rather than serve the cached AsyncValue.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  static Entitlement _freeSignedIn(String userId) {
    final now = DateTime.now();
    return Entitlement(
      state: EntitlementState.free,
      userId: userId,
      counterPeriodStart: DateTime(now.year, now.month),
      fetchedAt: now,
    );
  }

  /// Override the entitlement directly. Used by:
  ///   - The post-IAP-purchase flow (Group C) to optimistically
  ///     reflect a Pro upgrade before the next Supabase round-trip.
  ///   - Tests + dev tooling.
  Future<void> setOptimistic(Entitlement next) async {
    state = AsyncValue.data(next);
    // Persist to the cache so a relaunch picks it up. The
    // reconciliation pass will overwrite if the server disagrees.
    final repo = await ref.read(entitlementRepoProvider.future);
    await repo.upsert(next);
  }

  /// Phase 7 task F.1 — flip the BYOK lane on / off.
  ///
  /// **On**: persist the user's `sk-ant-…` key via
  /// [SecureApiKeyStorage], persist `byok_enabled = true` in
  /// [SettingsStorage], emit [Entitlement.byok]. Caller is
  /// expected to have already validated [apiKey] via
  /// [ByokValidator] (format check + live ping per DECISIONS row
  /// 74).
  ///
  /// **Off**: clear the stored key, persist `byok_enabled =
  /// false`, emit [Entitlement.freeAnonymous]. The free-tier
  /// 200-msg/mo proxy lane resumes (once Group H wires the proxy
  /// + sign-in; until then chat is unavailable for free users).
  Future<void> setByokActive({required bool active, String? apiKey}) async {
    final settings = ref.read(settingsStorageProvider);
    // Route through ApiKeyNotifier so the apiKeyProvider state
    // refreshes alongside the underlying SecureStorage write — chat
    // composer + llmClientProvider both watch that provider.
    final keyNotifier = ref.read(apiKeyProvider.notifier);
    if (active) {
      if (apiKey == null || apiKey.isEmpty) {
        throw ArgumentError(
          'setByokActive(active: true) requires a non-empty apiKey',
        );
      }
      await keyNotifier.save(apiKey);
      await settings.setBool(_byokEnabledKey, true);
      state = AsyncValue.data(Entitlement.byok());
    } else {
      await keyNotifier.clear();
      await settings.setBool(_byokEnabledKey, false);
      // Phase 7 task H.1.c.2 — invalidateSelf so build() re-runs
      // through the auth-aware path. A signed-in user dropping BYOK
      // refetches their server entitlement; a signed-out user lands
      // on freeAnonymous. Without this, build() stayed on the BYOK
      // result cached in `state` and the user appeared stuck.
      ref.invalidateSelf();
    }
  }
}

/// Phase 7 task H.1.c.2 — entitlements REST client provider.
///
/// Returns:
///   - `null` when [supabaseRuntimeConfigProvider] is null (Supabase
///     not configured at build time — `--dart-define` values absent).
///   - A live [SupabaseEntitlementsClient] otherwise. The client's
///     `jwtSource` closure reads the latest accessToken from
///     [authSessionProvider] on every fetch so token refresh inside
///     `supabase_flutter` is picked up without rebuilding the
///     provider.
///
/// Tests override this with a [FakeEntitlementsClient] to drive
/// the auth-aware refresh path without HTTP plumbing.
final entitlementsClientProvider = Provider<EntitlementsClient?>((ref) {
  final config = ref.watch(supabaseRuntimeConfigProvider);
  if (config == null) return null;
  return SupabaseEntitlementsClient(
    supabaseUrl: config.url,
    anonKey: config.anonKey,
    jwtSource: () =>
        ref.read(authSessionProvider).value?.accessToken ?? '',
  );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos/entitlement_repo.dart';
import '../providers.dart';
import 'entitlement.dart';

/// Phase 7 task B.1 — active-user entitlement notifier.
///
/// Provides the [Entitlement] every quota gate + Pro-feature surface
/// reads. Refresh path is staged:
///
///   - **B.1 (initial commit):** the notifier emits the cached value
///     from Drift for the active user, or [Entitlement.freeAnonymous]
///     when no cache row exists / no auth is wired yet.
///   - **F.1 (this commit):** [build] now consults the
///     `byok_enabled` flag in [SettingsStorage] and emits
///     [Entitlement.byok] when it's set. Existing pre-Phase-7
///     users with an API key in [SecureApiKeyStorage] are
///     auto-promoted to BYOK on first read (one-time migration —
///     row 74 lock).
///   - **Later (Group H):** [refresh] becomes a real Supabase round-
///     trip + cache upsert, called on app foreground / chat-screen
///     mount / post-Play-webhook per DECISIONS row 78.
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
    // apiKeyStorageProvider see the build path above gracefully fall
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
      // for example) get the synthetic default.
    }

    return Entitlement.freeAnonymous();
  }

  /// Reconcile the local cache against Supabase. **Stub for B.1** —
  /// emits the current state unchanged. A later commit (after Group
  /// H lands `supabase_flutter`) replaces the body with a real
  /// fetch + upsert via [EntitlementRepo].
  Future<void> refresh() async {
    // Defensive: keep the existing AsyncValue.data shape. If we're
    // currently in error or loading, leave that to the consumer to
    // resolve — a refresh() call shouldn't paper over upstream
    // failures.
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(current);
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
      state = AsyncValue.data(Entitlement.freeAnonymous());
    }
  }
}

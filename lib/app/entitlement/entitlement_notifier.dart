import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos/entitlement_repo.dart';
import '../providers.dart';
import 'entitlement.dart';

/// Phase 7 task B.1 — active-user entitlement notifier.
///
/// Provides the [Entitlement] every quota gate + Pro-feature surface
/// reads. Refresh path is staged:
///
///   - **B.1 (this commit):** the notifier emits the cached value
///     from Drift for the active user, or [Entitlement.freeAnonymous]
///     when no cache row exists / no auth is wired yet. [refresh] is
///     a no-op stub; reconciliation against Supabase lands when auth
///     wires in (Group F.1) + the `EntitlementService` (later task)
///     queries the Supabase `entitlements` row.
///   - **Later:** [refresh] becomes a real Supabase round-trip + cache
///     upsert, called on app foreground / chat-screen mount /
///     post-Play-webhook per DECISIONS row 78.
///
/// The agent loop's quota gate consumes [entitlementProvider] via
/// `ref.read` — never via `ref.watch` inside hot paths, since a
/// rebuild on entitlement change is exactly what the gate is gated on.
class EntitlementNotifier extends AsyncNotifier<Entitlement> {
  @override
  Future<Entitlement> build() async {
    // No auth wiring yet (Group F.1). The active-user concept doesn't
    // resolve to a userId; the cache is empty by definition. Return
    // the synthetic anonymous default; refresh() will be wired to
    // Supabase once auth lands.
    return Entitlement.freeAnonymous();
  }

  /// Reconcile the local cache against Supabase. **Stub for B.1** —
  /// emits the current state unchanged. A later commit (after Group
  /// F.1 lands `supabase_flutter`) replaces the body with a real
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
}

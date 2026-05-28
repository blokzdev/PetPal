import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/cloud_sync_adapter.dart';
import '../../data/sync/e2ee_sync_adapter.dart';
import '../../data/sync/supabase_sync_backend.dart';
import '../../data/sync/sync_backend.dart';
import '../../data/sync/sync_session.dart';
import '../auth/auth_session_notifier.dart';
import '../entitlement/entitlement.dart';
import '../providers.dart';
import 'supabase_runtime_config.dart';

/// Phase 7 task G.2 / H.1.b — sync provider graph.
///
/// **Layered**: `syncSession` (in-memory key cache) → `syncBackend`
/// (network) → `cloudSyncAdapter` (push/pull logic) →
/// `entitlementGatedSyncAdapter` (Pro gate). H.1.b lights up the
/// production wiring: when [supabaseRuntimeConfigProvider] is
/// populated AND [authSessionProvider] has a session, [syncBackend]
/// returns a [SupabaseSyncBackend] keyed to that user's UUID;
/// otherwise it stays on the unauthenticated [InMemorySyncBackend]
/// fallback so the Settings sync card renders the `signedOut` state
/// correctly.

/// One [SyncSession] per app launch — holds the derived key after
/// passphrase setup / unlock; locked on app close (memory reclaim).
final syncSessionProvider = Provider<SyncSession>((ref) {
  return SyncSession();
});

/// Production-aware sync backend.
///
/// Returns:
///   - [SupabaseSyncBackend] when signed-in + Supabase config set
///     (H.1.b production path).
///   - [InMemorySyncBackend] (unauthenticated) otherwise — chat /
///     sync surfaces stay on the "sign-in coming" / "sign in to
///     enable sync" register.
///
/// JWT freshness: the backend re-reads `accessToken` from
/// [authSessionProvider] on every request via the closure, so token
/// refresh inside `supabase_flutter` is picked up without
/// re-instantiating the backend.
final syncBackendProvider = Provider<SyncBackend>((ref) {
  final config = ref.watch(supabaseRuntimeConfigProvider);
  final session = ref.watch(authSessionProvider).value;
  if (config == null || session == null) {
    return InMemorySyncBackend(isAuthenticated: false);
  }
  return SupabaseSyncBackend(
    supabaseUrl: config.url,
    anonKey: config.anonKey,
    userId: session.userId,
    jwtSource: () =>
        ref.read(authSessionProvider).value?.accessToken ?? '',
  );
});

/// Phase 7 task G.2 — actions surfaced to the passphrase setup
/// screen + the Settings sync card. Thin wrapper that pulls the
/// session + backend from Riverpod and runs the
/// setup/unlock/lock flows; keeps the UI free of crypto + network
/// plumbing.
final syncSetupActionProvider = Provider<SyncSetupActions>((ref) {
  return SyncSetupActions(
    session: ref.read(syncSessionProvider),
    backend: ref.read(syncBackendProvider),
  );
});

class SyncSetupActions {
  SyncSetupActions({required this.session, required this.backend});

  final SyncSession session;
  final SyncBackend backend;

  /// First-device setup: derive key, encrypt + upload challenge.
  /// Throws if the backend is unauthenticated (Group H.1 ships
  /// sign-in; until then setup is unreachable in production but
  /// works in tests against a `InMemorySyncBackend(isAuthenticated:
  /// true)`).
  Future<void> runSetup({required String passphrase}) async {
    if (!backend.isAuthenticated) {
      throw const _SyncAuthRequired();
    }
    final challenge = await session.setup(passphrase: passphrase);
    await backend.storeChallenge(challenge);
  }

  /// Second-device unlock: pull challenge, attempt decrypt.
  /// Returns true on success, false on wrong passphrase.
  Future<bool> runUnlock({required String passphrase}) async {
    if (!backend.isAuthenticated) {
      throw const _SyncAuthRequired();
    }
    final challenge = await backend.fetchChallenge();
    if (challenge == null) {
      throw const _SyncSetupRequired();
    }
    return session.unlock(passphrase: passphrase, challenge: challenge);
  }

  /// Drop the cached key (sign-out / explicit lock).
  void lock() => session.lock();
}

class _SyncAuthRequired implements Exception {
  const _SyncAuthRequired();
  @override
  String toString() =>
      'Sign in to your PetPal account before setting up sync.';
}

class _SyncSetupRequired implements Exception {
  const _SyncSetupRequired();
  @override
  String toString() =>
      'No sync passphrase exists yet for this account. Set one up '
      'on the device that has your journal first.';
}

/// Phase 7 task G.2 — derived UI state for the Settings sync card.
///
///   - `proLocked` — entitlement is not Pro; sync is gated.
///   - `signedOut` — Pro entitlement but backend not authenticated.
///   - `setupNeeded` — signed in but no challenge stored yet.
///   - `locked` — challenge exists but session not unlocked.
///   - `unlocked` — ready to push/pull.
enum SyncUiState { proLocked, signedOut, setupNeeded, locked, unlocked }

/// Settings card surfaces this; checked synchronously each rebuild
/// so the card flips state immediately after passphrase setup /
/// unlock without an extra refresh.
final syncUiStateProvider = Provider<SyncUiState>((ref) {
  final ent = ref.watch(entitlementProvider).maybeWhen(
        data: (e) => e,
        orElse: Entitlement.freeAnonymous,
      );
  if (!ent.isPro) return SyncUiState.proLocked;
  final backend = ref.watch(syncBackendProvider);
  if (!backend.isAuthenticated) return SyncUiState.signedOut;
  final session = ref.watch(syncSessionProvider);
  if (session.isUnlocked) return SyncUiState.unlocked;
  // The "setupNeeded vs locked" distinction needs an async
  // backend.fetchChallenge() — keep the resolution in the card
  // itself via a FutureProvider so the synchronous derivation here
  // stays cheap.
  return SyncUiState.locked;
});

/// Phase 7 task G.2 — `setupNeeded` distinguisher. Cheap async
/// fetch; the Settings card calls it once on mount + after
/// notifier transitions.
final syncChallengeExistsProvider = FutureProvider<bool>((ref) async {
  final backend = ref.watch(syncBackendProvider);
  if (!backend.isAuthenticated) return false;
  final challenge = await backend.fetchChallenge();
  return challenge != null;
});

/// Phase 7 task H.1.b — production [CloudSyncAdapter] wiring.
///
/// Composes [E2eeSyncAdapter] (encrypts wiki blobs) +
/// [EntitlementGatedSyncAdapter] (Pro-only gate per row 36) against
/// the active sync backend + signed-in user.
///
/// Returns [NoopCloudSyncAdapter] when:
///   - No auth session (signed out)
///   - Backend isn't authenticated (Supabase config missing or
///     session expired)
///
/// FutureProvider because [E2eeSyncAdapter] needs the resolved
/// [WikiIo] from `wikiIoProvider` (which is itself async — the
/// platform path-provider lookup happens lazily). Consumers wrap
/// reads in `.when(data: ..., loading: ..., error: ...)`.
final cloudSyncAdapterProvider =
    FutureProvider<CloudSyncAdapter>((ref) async {
  final session = ref.watch(authSessionProvider).value;
  final backend = ref.watch(syncBackendProvider);

  if (session == null || !backend.isAuthenticated) {
    return NoopCloudSyncAdapter();
  }

  final wiki = await ref.watch(wikiIoProvider.future);
  final inner = E2eeSyncAdapter(
    backend: backend,
    session: ref.watch(syncSessionProvider),
    wiki: wiki,
    userId: session.userId,
  );

  return EntitlementGatedSyncAdapter(
    inner: inner,
    entitlementSource: () =>
        ref.read(entitlementProvider).value ?? Entitlement.freeAnonymous(),
  );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/cloud_sync_adapter.dart';
import '../../data/sync/sync_backend.dart';
import '../../data/sync/sync_session.dart';
import '../entitlement/entitlement.dart';
import '../providers.dart';

/// Phase 7 task G.2 — sync provider graph.
///
/// **Layered**: `syncSession` (in-memory key cache) → `syncBackend`
/// (network) → `cloudSyncAdapter` (push/pull logic) →
/// `entitlementGatedSyncAdapter` (Pro gate). Production wiring for
/// the backend (Supabase Storage + Postgres clients) lands in
/// Group H.1 alongside magic-link sign-in; G.2 ships the in-memory
/// fake so tests + the passphrase setup UX work end-to-end.

/// One [SyncSession] per app launch — holds the derived key after
/// passphrase setup / unlock; locked on app close (memory reclaim).
final syncSessionProvider = Provider<SyncSession>((ref) {
  return SyncSession();
});

/// G.2 stub. Returns an [InMemorySyncBackend] that's NOT
/// authenticated — sync attempts surface the "sign in to enable
/// sync" path. H.1 overrides this provider with the real
/// `SupabaseSyncBackend` once auth lands. Tests inject a fully-
/// wired `InMemorySyncBackend(isAuthenticated: true)` directly.
final syncBackendProvider = Provider<SyncBackend>((ref) {
  return InMemorySyncBackend(isAuthenticated: false);
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
      'Sign in to your PetPal account before setting up sync. '
      '(Magic-link sign-in ships in a later update.)';
}

class _SyncSetupRequired implements Exception {
  const _SyncSetupRequired();
  @override
  String toString() =>
      "No sync passphrase exists yet for this account. Set one up "
      "on the device that has your journal first.";
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

/// G.2 placeholder — production [CloudSyncAdapter] composes
/// `E2eeSyncAdapter` + `EntitlementGatedSyncAdapter` once H.1 wires
/// auth + the production backend. Tests construct adapters
/// directly with their own session + backend overrides. The
/// existing `NoopCloudSyncAdapter` from Phase 2 stays as the
/// pre-wiring default so callers that read this provider don't
/// crash.
final cloudSyncAdapterProvider = Provider<CloudSyncAdapter>((ref) {
  return NoopCloudSyncAdapter();
});

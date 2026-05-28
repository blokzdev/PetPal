import '../../app/entitlement/entitlement.dart';
import '../../app/entitlement/quota_exception.dart';

/// Cloud sync surface — placeholder interface, no implementation yet.
///
/// Per DECISIONS row 11, the choice of backend (custom server, git+gpg,
/// S3+CRDTs, …) was deferred to the sync/monetization phase — renumbered
/// from Phase 5 to Phase 7 by DECISIONS row 34. This interface
/// lands in Phase 2 so the rest of the app can be written against the
/// seam, and so swapping the backend in later is a one-file change
/// rather than a refactor.
///
/// Phase 7 implements push/pull semantics (Supabase backend per DECISIONS
/// row 82; last-writer-wins per file path, with the body_hash stored in
/// `entries` doubling as a conflict detector).
abstract class CloudSyncAdapter {
  /// Push local changes for [petId] to the remote. Implementations may
  /// choose what counts as "changes" (since-last-sync diff, full
  /// snapshot, etc.) — the chat UI just calls this and awaits.
  Future<SyncResult> push({required int petId});

  /// Pull remote changes for [petId] into the local wiki. Returns the
  /// paths that were updated so the caller can invalidate downstream
  /// providers (wikiEntriesProvider, etc.).
  Future<SyncResult> pull({required int petId});

  /// Most recent sync state, surfaced to the UI as a status pill /
  /// banner. Null while no sync has run yet.
  SyncStatus get status;
}

class SyncResult {
  const SyncResult({
    required this.changedPaths,
    required this.completedAt,
  });
  final List<String> changedPaths;
  final DateTime completedAt;
}

enum SyncState { idle, syncing, error }

class SyncStatus {
  const SyncStatus({
    required this.state,
    this.lastSyncAt,
    this.errorMessage,
  });
  final SyncState state;
  final DateTime? lastSyncAt;
  final String? errorMessage;
}

/// Default no-op adapter so the rest of the app can construct a sync
/// provider without crashing when a real sync backend isn't active.
/// Push and pull return immediately with no changed paths.
class NoopCloudSyncAdapter implements CloudSyncAdapter {
  NoopCloudSyncAdapter();

  @override
  SyncStatus status = const SyncStatus(state: SyncState.idle);

  @override
  Future<SyncResult> push({required int petId}) async {
    final now = DateTime.now();
    status = SyncStatus(state: SyncState.idle, lastSyncAt: now);
    return SyncResult(changedPaths: const [], completedAt: now);
  }

  @override
  Future<SyncResult> pull({required int petId}) async {
    final now = DateTime.now();
    status = SyncStatus(state: SyncState.idle, lastSyncAt: now);
    return SyncResult(changedPaths: const [], completedAt: now);
  }
}

/// Phase 7 task D.1 — entitlement-gated sync decorator.
///
/// Wraps any [CloudSyncAdapter] (today: [NoopCloudSyncAdapter]; G.2:
/// the real Supabase Storage adapter) and throws [SyncQuotaExceeded]
/// before push/pull when the active entitlement isn't Pro.
///
/// Sync is **Pro-only** per DECISIONS row 36. BYOK does NOT unlock
/// sync — sync is a server-cost feature, not a cost-driven cap.
/// The gate fires on every push/pull; status reads pass through
/// untouched (UI may want to show "sync requires Pro" without
/// throwing).
class EntitlementGatedSyncAdapter implements CloudSyncAdapter {
  EntitlementGatedSyncAdapter({
    required CloudSyncAdapter inner,
    required Entitlement Function() entitlementSource,
  })  : _inner = inner,
        _entitlementSource = entitlementSource;

  final CloudSyncAdapter _inner;
  final Entitlement Function() _entitlementSource;

  @override
  SyncStatus get status => _inner.status;

  @override
  Future<SyncResult> push({required int petId}) async {
    _enforceProGate();
    return _inner.push(petId: petId);
  }

  @override
  Future<SyncResult> pull({required int petId}) async {
    _enforceProGate();
    return _inner.pull(petId: petId);
  }

  void _enforceProGate() {
    final ent = _entitlementSource();
    if (!ent.isPro) {
      throw SyncQuotaExceeded(ent);
    }
  }
}

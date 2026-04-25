/// Cloud sync surface — placeholder interface, no implementation yet.
///
/// Per DECISIONS row 11, the choice of backend (custom server, git+gpg,
/// S3+CRDTs, …) is deferred to the start of Phase 5. This interface
/// lands in Phase 2 so the rest of the app can be written against the
/// seam, and so swapping the backend in later is a one-file change
/// rather than a refactor.
///
/// Phase 5 will implement push/pull semantics (probably last-writer-wins
/// per file path, with the body_hash stored in `entries` doubling as a
/// conflict detector). The exact contract is intentionally loose for
/// now.
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
/// provider without crashing while Phase 5's backend choice is pending.
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

import 'dart:typed_data';

import 'sync_session.dart';

/// Phase 7 task G.2 — abstract network surface for sync.
///
/// Production implementation is [SupabaseSyncBackend] (next file);
/// tests use [InMemorySyncBackend]. Keeping the production
/// `CloudSyncAdapter` agnostic of the `supabase` package lets the
/// test suite verify the load-bearing E2EE invariant — "backend
/// never sees plaintext" — without needing a real Supabase client
/// or an HTTP fake stack.
abstract class SyncBackend {
  /// True when authentication is established (signed-in user with
  /// a valid Supabase JWT). False before Group H.1 wires sign-in,
  /// or for a signed-out user.
  bool get isAuthenticated;

  /// Fetch the user's existing passphrase challenge from the
  /// `sync_challenges` table. Returns null if the user has not
  /// completed first-device setup.
  Future<SyncChallenge?> fetchChallenge();

  /// Persist the user's passphrase challenge — called from
  /// first-device setup. Idempotent: calling with the same salt +
  /// ciphertext is a no-op.
  Future<void> storeChallenge(SyncChallenge challenge);

  /// Return the metadata rows from `wiki_sync_objects` for
  /// [petId] whose `updated_at` is strictly greater than [since].
  /// Empty list when there are no deltas. Used by the pull path
  /// to discover what's new on the server.
  Future<List<RemoteObjectMeta>> listSince({
    required int petId,
    required DateTime since,
  });

  /// Download the encrypted blob bytes for [objectKey]. Throws
  /// [SyncBackendException] on 404 / auth failure / network error.
  Future<Uint8List> downloadObject(String objectKey);

  /// Upload the encrypted blob bytes + sidecar metadata in one
  /// logical operation. Implementations should write the blob to
  /// Storage first; only on success should they upsert the
  /// sidecar row (so a failed upload can't leave the sidecar
  /// claiming a blob exists that doesn't).
  Future<void> uploadObject({
    required String objectKey,
    required Uint8List blob,
    required RemoteObjectMeta meta,
  });

  /// Mark [objectKey] as deleted on the server. The blob itself
  /// stays (per row 83's S3 versioning + delete marker model);
  /// the sidecar row gets `deleted = true` so other devices
  /// reconcile the deletion on next pull.
  Future<void> markDeleted({
    required String objectKey,
    required RemoteObjectMeta meta,
  });
}

/// Sidecar metadata row for one wiki object. Mirrors the
/// `wiki_sync_objects` table per DECISIONS row 83.
class RemoteObjectMeta {
  const RemoteObjectMeta({
    required this.petId,
    required this.relativePath,
    required this.writeTs,
    required this.bodyHash,
    this.deleted = false,
  });

  final int petId;
  final String relativePath;

  /// Client-supplied wall clock for the write — the LWW key (G.3
  /// implements the comparison rule with the 5-second skew
  /// tolerance from row 72).
  final DateTime writeTs;

  /// SHA-256 hex of the **plaintext** (not the ciphertext —
  /// ciphertext changes every encrypt due to fresh IV). The server
  /// can't verify this matches the blob (would require plaintext);
  /// it's a trust-the-client field used for client-side LWW
  /// comparison + dedup per DECISIONS row 83.
  final String bodyHash;

  /// Logical-delete marker — `true` means the path was deleted on
  /// some device. Pull deletes the local file when it sees this
  /// flip true. The blob itself stays (S3 versioning floor).
  final bool deleted;

  Map<String, Object?> toJson() => {
        'pet_id': petId,
        'relative_path': relativePath,
        'write_ts': writeTs.toUtc().millisecondsSinceEpoch,
        'body_hash': bodyHash,
        'deleted': deleted,
      };

  static RemoteObjectMeta fromJson(Map<String, Object?> json) =>
      RemoteObjectMeta(
        petId: json['pet_id'] as int,
        relativePath: json['relative_path'] as String,
        writeTs: DateTime.fromMillisecondsSinceEpoch(
          json['write_ts'] as int,
          isUtc: true,
        ),
        bodyHash: json['body_hash'] as String,
        deleted: json['deleted'] as bool? ?? false,
      );
}

class SyncBackendException implements Exception {
  const SyncBackendException(this.message);
  final String message;
  @override
  String toString() => 'SyncBackendException: $message';
}

/// Phase 7 task G.2 — in-memory test backend.
///
/// The crucial **"backend never sees plaintext"** invariant test
/// runs against this fake. Every uploaded blob is captured into
/// [uploads] and asserted to NOT contain the original plaintext
/// bytes anywhere — that's the load-bearing E2EE check.
///
/// Authentication defaults to true (tests skip the auth-gating
/// path); set [isAuthenticated] false in the constructor to
/// exercise the unauthenticated-error path.
class InMemorySyncBackend implements SyncBackend {
  InMemorySyncBackend({this.isAuthenticated = true});

  @override
  final bool isAuthenticated;

  /// Captured uploads, keyed by objectKey. Tests assert against
  /// this map.
  final Map<String, Uint8List> uploads = {};

  /// Captured sidecar metadata, keyed by objectKey.
  final Map<String, RemoteObjectMeta> metadata = {};

  /// Captured challenge, if [storeChallenge] was called.
  SyncChallenge? challenge;

  @override
  Future<SyncChallenge?> fetchChallenge() async => challenge;

  @override
  Future<void> storeChallenge(SyncChallenge ch) async {
    challenge = ch;
  }

  @override
  Future<List<RemoteObjectMeta>> listSince({
    required int petId,
    required DateTime since,
  }) async {
    return metadata.values
        .where((m) => m.petId == petId)
        .where((m) => m.writeTs.isAfter(since))
        .toList();
  }

  @override
  Future<Uint8List> downloadObject(String objectKey) async {
    final blob = uploads[objectKey];
    if (blob == null) {
      throw SyncBackendException('object $objectKey not found');
    }
    return blob;
  }

  @override
  Future<void> uploadObject({
    required String objectKey,
    required Uint8List blob,
    required RemoteObjectMeta meta,
  }) async {
    uploads[objectKey] = blob;
    metadata[objectKey] = meta;
  }

  @override
  Future<void> markDeleted({
    required String objectKey,
    required RemoteObjectMeta meta,
  }) async {
    metadata[objectKey] = RemoteObjectMeta(
      petId: meta.petId,
      relativePath: meta.relativePath,
      writeTs: meta.writeTs,
      bodyHash: meta.bodyHash,
      deleted: true,
    );
  }
}

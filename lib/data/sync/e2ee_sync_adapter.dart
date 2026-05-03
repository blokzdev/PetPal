import 'dart:convert';
import 'dart:typed_data';

import '../wiki_io.dart';
import 'cloud_sync_adapter.dart';
import 'conflict_resolver.dart';
import 'sync_backend.dart';
import 'sync_session.dart';
import 'wiki_crypto.dart';

/// Phase 7 task G.2 — production [CloudSyncAdapter] wiring the
/// E2EE crypto layer ([WikiCrypto]) + the [SyncSession] key cache
/// + the [SyncBackend] network surface together.
///
/// **Backend never sees plaintext.** Every body that crosses the
/// `SyncBackend` interface is wire-format ciphertext per
/// [WikiCrypto]'s blob shape. The only network calls that touch a
/// plain string are (a) the `body_hash` (SHA-256 hex of plaintext —
/// trust-the-client field per row 83) and (b) the `relative_path`
/// (object key path component — already public structure). Neither
/// reveals body content.
///
/// **Auth + Pro gating are upstream.** This adapter assumes the
/// caller (typically [EntitlementGatedSyncAdapter]) has already
/// confirmed Pro entitlement, and that [SyncSession.isUnlocked] is
/// true. The adapter throws [SyncStateException] if either is
/// violated mid-flight.
///
/// **Conflict handling is G.3's problem.** This adapter implements
/// straightforward LWW: on pull, the server's `write_ts` wins if
/// it's strictly later than the local file's recorded
/// `write_ts`. Tighter rules (5-second skew tolerance,
/// `.conflict.md` fallback for genuinely-divergent edits per row
/// 72) land in G.3 — at that point this class will route through
/// a [ConflictResolver] before writing locally.
class E2eeSyncAdapter implements CloudSyncAdapter {
  E2eeSyncAdapter({
    required SyncBackend backend,
    required SyncSession session,
    required WikiIo wiki,
    required String userId,
    DateTime Function() clock = DateTime.now,
    ConflictResolver? resolver,
  })  : _backend = backend,
        _session = session,
        _wiki = wiki,
        _userId = userId,
        _clock = clock,
        _resolver = resolver ?? const ConflictResolver();

  final SyncBackend _backend;
  final SyncSession _session;
  final WikiIo _wiki;
  final String _userId;
  final DateTime Function() _clock;
  final ConflictResolver _resolver;

  /// Track the last write timestamp we observed for each
  /// `<petId>/<relativePath>` so we can compare against the
  /// remote's `write_ts` on pull. In v1 this lives in memory only
  /// — a relaunch picks up the real ts from the file mtime, which
  /// the production WikiIo will surface in a follow-up.
  /// G.3 may move this to a Drift-backed table for stable LWW
  /// semantics across launches.
  final Map<String, DateTime> _lastWriteTs = {};

  @override
  SyncStatus status = const SyncStatus(state: SyncState.idle);

  void _enforceState() {
    if (!_backend.isAuthenticated) {
      throw const SyncStateException(
        'sync requires sign-in (Group H.1 ships magic-link auth).',
      );
    }
    if (!_session.isUnlocked) {
      throw const SyncStateException(
        'sync session is locked — passphrase has not been entered '
        'this session.',
      );
    }
  }

  @override
  Future<SyncResult> push({required int petId}) async {
    _enforceState();
    status = const SyncStatus(state: SyncState.syncing);
    try {
      final relativePaths = await _wiki.listForPet(petId);
      final changed = <String>[];
      for (final fullPath in relativePaths) {
        final relPath = _stripPetPrefix(petId: petId, fullPath: fullPath);
        final body = await _wiki.read(fullPath);
        final plaintext = Uint8List.fromList(utf8.encode(body));
        final hash = WikiCrypto.bodyHash(plaintext);
        final tsKey = _tsKey(petId, relPath);
        final writeTs = _lastWriteTs[tsKey] ?? _clock();
        // Skip uploads when local hash matches the server's
        // recorded hash — saves bandwidth for the common case
        // (most files don't change session-to-session).
        final remote =
            (await _backend.listSince(petId: petId, since: _epoch))
                .where((m) => m.relativePath == relPath)
                .cast<RemoteObjectMeta?>()
                .firstWhere((_) => true, orElse: () => null);
        if (remote != null && remote.bodyHash == hash && !remote.deleted) {
          continue;
        }
        final aad = BlobAad(
          petId: petId,
          relativePath: relPath,
          writeTs: writeTs,
        );
        final blob = await _session.crypto.encrypt(
          plaintext: plaintext,
          keyBytes: _session.derivedKey,
          aad: aad,
        );
        final objectKey = _objectKey(petId: petId, relPath: relPath);
        await _backend.uploadObject(
          objectKey: objectKey,
          blob: blob,
          meta: RemoteObjectMeta(
            petId: petId,
            relativePath: relPath,
            writeTs: writeTs,
            bodyHash: hash,
          ),
        );
        _lastWriteTs[tsKey] = writeTs;
        changed.add(relPath);
      }
      final now = _clock();
      status = SyncStatus(state: SyncState.idle, lastSyncAt: now);
      return SyncResult(changedPaths: changed, completedAt: now);
    } catch (e) {
      status = SyncStatus(
        state: SyncState.error,
        lastSyncAt: status.lastSyncAt,
        errorMessage: '$e',
      );
      rethrow;
    }
  }

  @override
  Future<SyncResult> pull({required int petId}) async {
    _enforceState();
    status = const SyncStatus(state: SyncState.syncing);
    try {
      final since = status.lastSyncAt ?? _epoch;
      final remote = await _backend.listSince(petId: petId, since: since);
      final changed = <String>[];
      for (final meta in remote) {
        final fullPath =
            _fullPath(petId: meta.petId, relPath: meta.relativePath);
        final tsKey = _tsKey(meta.petId, meta.relativePath);

        if (meta.deleted) {
          await _wiki.deleteIfExists(fullPath);
          _lastWriteTs[tsKey] = meta.writeTs;
          changed.add(meta.relativePath);
          continue;
        }

        final objectKey =
            _objectKey(petId: meta.petId, relPath: meta.relativePath);
        final blob = await _backend.downloadObject(objectKey);
        final aad = BlobAad(
          petId: meta.petId,
          relativePath: meta.relativePath,
          writeTs: meta.writeTs,
        );
        final remoteBytes = await _session.crypto.decrypt(
          blob: blob,
          keyBytes: _session.derivedKey,
          aad: aad,
        );

        // Local participant — null if the file doesn't exist locally
        // (first-pull on this device). _lastWriteTs may also be null
        // post-restart even when the file exists — the resolver
        // routes that path to a defensive .conflict.md so user edits
        // aren't silently overwritten.
        final localBytes = await _readLocalBytes(fullPath);
        final localParticipant = localBytes == null
            ? null
            : ConflictParticipant(
                bytes: localBytes,
                writeTs: _lastWriteTs[tsKey],
              );
        final remoteParticipant = ConflictParticipant(
          bytes: remoteBytes,
          writeTs: meta.writeTs,
        );

        final resolution = _resolver.resolve(
          local: localParticipant,
          remote: remoteParticipant,
        );

        switch (resolution) {
          case KeepLocal():
            // No-op. Update the tracker so future LWW comparisons
            // against this remote ts know we've already seen it.
            _lastWriteTs[tsKey] = meta.writeTs;

          case KeepRemote(:final bytes, :final writeTs):
            await _wiki.writeAtomic(fullPath, utf8.decode(bytes));
            _lastWriteTs[tsKey] = writeTs;
            changed.add(meta.relativePath);

          case WriteWithConflict(
              :final survivorBytes,
              :final survivorTs,
              :final loserBytes,
            ):
            await _wiki.writeAtomic(
              fullPath,
              utf8.decode(survivorBytes),
            );
            final conflictPath = _fullPath(
              petId: meta.petId,
              relPath: conflictPathFor(meta.relativePath),
            );
            await _wiki.writeAtomic(
              conflictPath,
              utf8.decode(loserBytes),
            );
            _lastWriteTs[tsKey] = survivorTs;
            changed.add(meta.relativePath);
            changed.add(conflictPathFor(meta.relativePath));
        }
      }
      final now = _clock();
      status = SyncStatus(state: SyncState.idle, lastSyncAt: now);
      return SyncResult(changedPaths: changed, completedAt: now);
    } catch (e) {
      status = SyncStatus(
        state: SyncState.error,
        lastSyncAt: status.lastSyncAt,
        errorMessage: '$e',
      );
      rethrow;
    }
  }

  /// Read local bytes if the file exists. Returns null on miss
  /// (the WikiIo.read contract throws when missing — the catch
  /// translates that to null for the resolver).
  Future<Uint8List?> _readLocalBytes(String fullPath) async {
    try {
      final body = await _wiki.read(fullPath);
      return Uint8List.fromList(utf8.encode(body));
    } catch (_) {
      return null;
    }
  }

  /// Object key derivation per DECISIONS row 83:
  /// `<userId>/<petId>/<relativePath>.enc`
  String _objectKey({required int petId, required String relPath}) =>
      '$_userId/$petId/$relPath.enc';

  /// Wiki-root-relative full path used by [WikiIo].
  String _fullPath({required int petId, required String relPath}) =>
      '${_wiki.petDir(petId)}/$relPath';

  /// Strip the `wiki/<petId>/` prefix from a full WikiIo path so
  /// only the per-pet relative segment ends up in the object key.
  String _stripPetPrefix({required int petId, required String fullPath}) {
    final prefix = '${_wiki.petDir(petId)}/';
    return fullPath.startsWith(prefix)
        ? fullPath.substring(prefix.length)
        : fullPath;
  }

  String _tsKey(int petId, String relPath) => '$petId/$relPath';

  static final DateTime _epoch =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// Thrown when push / pull is attempted in an invalid state —
/// missing auth or locked session. Distinct from
/// [SyncQuotaExceeded] (Pro gate, thrown upstream by
/// [EntitlementGatedSyncAdapter]).
class SyncStateException implements Exception {
  const SyncStateException(this.message);
  final String message;
  @override
  String toString() => 'SyncStateException: $message';
}

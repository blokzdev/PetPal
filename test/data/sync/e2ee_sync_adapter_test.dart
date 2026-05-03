import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/sync/e2ee_sync_adapter.dart';
import 'package:petpal/data/sync/sync_backend.dart';
import 'package:petpal/data/sync/sync_session.dart';
import 'package:petpal/data/sync/wiki_crypto.dart';
import 'package:petpal/data/wiki_io.dart';

/// Phase 7 task G.2 — adapter integration tests against the
/// in-memory backend.
///
/// **The load-bearing E2EE invariant** lives here:
/// `push_uploads_only_ciphertext_never_plaintext`. Every test in
/// this file exercises the production [E2eeSyncAdapter] code path
/// against an [InMemorySyncBackend], and the invariant test
/// scrapes the captured upload bytes for the original plaintext —
/// fails if any byte sequence of the plaintext appears anywhere
/// in the captured network payload.
void main() {
  WikiCrypto fastCrypto() => WikiCrypto(
        argon2: Argon2id(
          parallelism: 1,
          memory: 8,
          iterations: 1,
          hashLength: 32,
        ),
      );

  Future<({E2eeSyncAdapter adapter, _CapturingWikiIo wiki, InMemorySyncBackend backend, SyncSession session})>
      build({String userId = 'user-uuid', bool authenticated = true}) async {
    final backend = InMemorySyncBackend(isAuthenticated: authenticated);
    final session = SyncSession(crypto: fastCrypto());
    await session.setup(passphrase: 'correct horse staple');
    final wiki = _CapturingWikiIo();
    final adapter = E2eeSyncAdapter(
      backend: backend,
      session: session,
      wiki: wiki,
      userId: userId,
    );
    return (adapter: adapter, wiki: wiki, backend: backend, session: session);
  }

  group('push', () {
    test('encrypts every wiki file + uploads ciphertext only — '
        'plaintext NEVER appears in the captured network payload '
        '(load-bearing E2EE invariant)', () async {
      final s = await build();
      const plaintext1 = 'unique-marker-A: vital signs normal at vet';
      const plaintext2 = 'unique-marker-B: weight 14.2 kg';
      await s.wiki.writeAtomic('wiki/7/vet/2026-04.md', plaintext1);
      await s.wiki.writeAtomic('wiki/7/weight/log.md', plaintext2);

      final result = await s.adapter.push(petId: 7);
      expect(result.changedPaths, hasLength(2));

      // Per-blob assertion: the encoded blob must not contain the
      // original plaintext anywhere. AES-GCM under any sane params
      // makes this vanishingly unlikely; the test is the canary
      // against an "encrypt is a no-op" regression.
      for (final blob in s.backend.uploads.values) {
        final asString = utf8.decode(blob, allowMalformed: true);
        expect(asString.contains(plaintext1), isFalse,
            reason: 'plaintext1 leaked into uploaded blob');
        expect(asString.contains(plaintext2), isFalse,
            reason: 'plaintext2 leaked into uploaded blob');
      }
      // Sidecar metadata is server-visible by design — pet_id +
      // path + write_ts + body_hash. body_hash is a hash, NOT
      // plaintext. Confirm the hash doesn't equal the plaintext.
      for (final meta in s.backend.metadata.values) {
        expect(meta.bodyHash.contains(plaintext1), isFalse);
        expect(meta.bodyHash.contains(plaintext2), isFalse);
        expect(meta.bodyHash.length, equals(64),
            reason: 'SHA-256 hex is exactly 64 chars');
      }
    });

    test('object key shape per DECISIONS row 83: '
        '<userId>/<petId>/<relPath>.enc', () async {
      final s = await build(userId: 'abc-uuid');
      await s.wiki.writeAtomic('wiki/42/vet/checkup.md', 'body');

      await s.adapter.push(petId: 42);
      expect(s.backend.uploads.keys, contains('abc-uuid/42/vet/checkup.md.enc'));
    });

    test('throws SyncStateException when not authenticated', () async {
      final s = await build(authenticated: false);
      await s.wiki.writeAtomic('wiki/1/a.md', 'body');
      await expectLater(
        () => s.adapter.push(petId: 1),
        throwsA(isA<SyncStateException>()),
      );
    });

    test('throws SyncStateException when session is locked', () async {
      final backend = InMemorySyncBackend();
      final session = SyncSession(crypto: fastCrypto()); // never setup()
      final wiki = _CapturingWikiIo();
      final adapter = E2eeSyncAdapter(
        backend: backend,
        session: session,
        wiki: wiki,
        userId: 'user',
      );
      await wiki.writeAtomic('wiki/1/a.md', 'body');
      await expectLater(
        () => adapter.push(petId: 1),
        throwsA(isA<SyncStateException>()),
      );
    });

    test('skips upload when remote body_hash matches local hash '
        '(bandwidth saver)', () async {
      final s = await build();
      await s.wiki.writeAtomic('wiki/1/a.md', 'body');

      // First push uploads.
      await s.adapter.push(petId: 1);
      final firstUploadBlob = Uint8List.fromList(
        s.backend.uploads['user-uuid/1/a.md.enc']!,
      );

      // Second push with no local change — must NOT re-upload (the
      // captured blob bytes stay byte-identical, proving the
      // upload was skipped).
      await s.adapter.push(petId: 1);
      expect(s.backend.uploads['user-uuid/1/a.md.enc'],
          equals(firstUploadBlob));
    });
  });

  group('pull', () {
    test('downloads + decrypts every remote object, writes plaintext '
        'locally', () async {
      // Source: fully-set-up adapter with two blobs uploaded.
      final source = await build();
      await source.wiki.writeAtomic('wiki/1/a.md', 'plaintext-A');
      await source.wiki.writeAtomic('wiki/1/b.md', 'plaintext-B');
      await source.adapter.push(petId: 1);

      // Target: a fresh device — same passphrase + challenge,
      // empty local wiki, shared backend.
      final challenge = source.backend.challenge ??
          await source.session.setup(passphrase: 'correct horse staple');
      // (in build() we already setup; refresh challenge into backend)
      await source.backend.storeChallenge(challenge);

      final targetBackend = source.backend;
      final targetSession = SyncSession(crypto: fastCrypto());
      final fetched = await targetBackend.fetchChallenge();
      expect(fetched, isNotNull);
      final unlocked = await targetSession.unlock(
        passphrase: 'correct horse staple',
        challenge: fetched!,
      );
      expect(unlocked, isTrue);
      final targetWiki = _CapturingWikiIo();
      final target = E2eeSyncAdapter(
        backend: targetBackend,
        session: targetSession,
        wiki: targetWiki,
        userId: 'user-uuid',
      );

      final result = await target.pull(petId: 1);
      expect(result.changedPaths, hasLength(2));
      expect(targetWiki.writes['wiki/1/a.md'], equals('plaintext-A'));
      expect(targetWiki.writes['wiki/1/b.md'], equals('plaintext-B'));
    });

    test('deleted-marker propagates: pull deletes the local file when '
        'the remote sidecar flips deleted=true', () async {
      final source = await build();
      await source.wiki.writeAtomic('wiki/1/a.md', 'body');
      await source.adapter.push(petId: 1);
      await source.backend.markDeleted(
        objectKey: 'user-uuid/1/a.md.enc',
        meta: source.backend.metadata['user-uuid/1/a.md.enc']!.copyForDeleteTest(
          newWriteTs: DateTime.utc(2027),
        ),
      );

      // Fresh target device.
      final challenge = source.backend.challenge!;
      final targetSession = SyncSession(crypto: fastCrypto());
      await targetSession.unlock(
        passphrase: 'correct horse staple',
        challenge: challenge,
      );
      final targetWiki = _CapturingWikiIo();
      // Pre-seed a stale local copy as if a previous pull had
      // landed it.
      await targetWiki.writeAtomic('wiki/1/a.md', 'stale local body');
      final target = E2eeSyncAdapter(
        backend: source.backend,
        session: targetSession,
        wiki: targetWiki,
        userId: 'user-uuid',
      );

      await target.pull(petId: 1);
      expect(targetWiki.writes.containsKey('wiki/1/a.md'), isFalse,
          reason: 'deleted-marker pull should remove the local file');
    });
  });
}

/// In-memory WikiIo that captures writes + supports listForPet +
/// deleteIfExists for sync-path tests.
class _CapturingWikiIo implements WikiIo {
  final Map<String, String> writes = {};

  @override
  Future<void> writeAtomic(String relPath, String body) async {
    writes[relPath] = body;
  }

  @override
  Future<String> read(String relPath) async {
    final body = writes[relPath];
    if (body == null) throw StateError('not written: $relPath');
    return body;
  }

  @override
  Future<List<String>> listForPet(int petId) async {
    final prefix = '${petDir(petId)}/';
    return writes.keys.where((k) => k.startsWith(prefix)).toList();
  }

  @override
  String petDir(int petId) => 'wiki/$petId';

  @override
  String soulPath(int petId) => 'wiki/$petId/SOUL.md';

  @override
  Future<void> writeBytesAtomic(String relPath, Uint8List bytes) =>
      throw UnimplementedError();
  @override
  Future<Uint8List> readBytes(String relPath) =>
      throw UnimplementedError();
  @override
  Future<void> deleteIfExists(String relPath) async {
    writes.remove(relPath);
  }

  @override
  Future<int> bytesForPet(int petId) async => 0;
}

extension on RemoteObjectMeta {
  RemoteObjectMeta copyForDeleteTest({required DateTime newWriteTs}) =>
      RemoteObjectMeta(
        petId: petId,
        relativePath: relativePath,
        writeTs: newWriteTs,
        bodyHash: bodyHash,
        deleted: deleted,
      );
}

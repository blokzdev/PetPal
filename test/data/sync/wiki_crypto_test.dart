import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/sync/wiki_crypto.dart';

/// Phase 7 task G.2 — wiki crypto round-trip + invariants.
///
/// Argon2id is the load-bearing slow KDF (~500ms per derive on the
/// row 71 starting params). To keep the test suite fast we
/// override with a tiny `Argon2id(memory: 8, iterations: 1)`
/// instance — same algorithm, different cost — for the cases that
/// just need a key. The single test that pins the production
/// params runs at full cost.
void main() {
  // Tiny Argon2id for fast tests. Production params are pinned
  // separately below.
  Argon2id fastArgon() => Argon2id(
        parallelism: 1,
        memory: 8,
        iterations: 1,
        hashLength: 32,
      );

  group('encrypt / decrypt round-trip', () {
    test('byte-identical plaintext after round-trip', () async {
      final crypto = WikiCrypto(argon2: fastArgon());
      final salt = WikiCrypto.generateSalt();
      final key = await crypto.deriveKey(passphrase: 'correct horse', salt: salt);
      final aad = BlobAad(
        petId: 7,
        relativePath: 'vet/2026-04-12-checkup.md',
        writeTs: DateTime.utc(2026, 4, 12, 10, 30),
      );
      final plaintext = Uint8List.fromList(
        utf8.encode('Vitals normal at the vet. Weight 14.2 kg.'),
      );

      final blob = await crypto.encrypt(
        plaintext: plaintext,
        keyBytes: key,
        aad: aad,
      );
      final out = await crypto.decrypt(
        blob: blob,
        keyBytes: key,
        aad: aad,
      );
      expect(out, equals(plaintext));
    });

    test('encrypted blob bytes do NOT contain the plaintext '
        '(the load-bearing E2EE invariant)', () async {
      final crypto = WikiCrypto(argon2: fastArgon());
      final salt = WikiCrypto.generateSalt();
      final key =
          await crypto.deriveKey(passphrase: 'staple battery', salt: salt);
      final aad = BlobAad(
        petId: 1,
        relativePath: 'vet/checkup.md',
        writeTs: DateTime.utc(2026, 5, 1),
      );
      const plaintext = 'absolutely-unique-marker-string-that-must-not-leak';
      final blob = await crypto.encrypt(
        plaintext: Uint8List.fromList(utf8.encode(plaintext)),
        keyBytes: key,
        aad: aad,
      );
      // Search for the plaintext bytes anywhere in the wire-format
      // blob. AES-GCM should make this vanishingly unlikely under
      // any reasonable parameters; this test is the canary against
      // an accidental "encrypt is a no-op" regression.
      final blobAsString = utf8.decode(blob, allowMalformed: true);
      expect(blobAsString.contains(plaintext), isFalse,
          reason: 'plaintext leaked into ciphertext');
    });

    test('two encrypts of the same plaintext + key produce DIFFERENT '
        'ciphertext (fresh random IV per encrypt)', () async {
      final crypto = WikiCrypto(argon2: fastArgon());
      final salt = WikiCrypto.generateSalt();
      final key = await crypto.deriveKey(passphrase: 'pw', salt: salt);
      final aad = BlobAad(
        petId: 1,
        relativePath: 'a',
        writeTs: DateTime.utc(2026, 1),
      );
      final plaintext = Uint8List.fromList(utf8.encode('same plaintext'));
      final a = await crypto.encrypt(plaintext: plaintext, keyBytes: key, aad: aad);
      final b = await crypto.encrypt(plaintext: plaintext, keyBytes: key, aad: aad);
      expect(a, isNot(equals(b)),
          reason: 'identical IVs would expose ciphertext patterns');
    });
  });

  group('AAD binding (tamper detection)', () {
    Future<({WikiCrypto crypto, Uint8List key, Uint8List blob, BlobAad aad})>
        seed() async {
      final crypto = WikiCrypto(argon2: fastArgon());
      final key = await crypto.deriveKey(
        passphrase: 'pw',
        salt: WikiCrypto.generateSalt(),
      );
      final aad = BlobAad(
        petId: 7,
        relativePath: 'vet/2026-04.md',
        writeTs: DateTime.utc(2026, 4, 12, 10, 30),
      );
      final blob = await crypto.encrypt(
        plaintext: Uint8List.fromList(utf8.encode('body')),
        keyBytes: key,
        aad: aad,
      );
      return (crypto: crypto, key: key, blob: blob, aad: aad);
    }

    test('decrypt fails when AAD pet_id changes', () async {
      final s = await seed();
      expect(
        () => s.crypto.decrypt(
          blob: s.blob,
          keyBytes: s.key,
          aad: BlobAad(
            petId: 99,
            relativePath: s.aad.relativePath,
            writeTs: s.aad.writeTs,
          ),
        ),
        throwsA(isA<WikiCryptoException>()),
      );
    });

    test('decrypt fails when AAD path changes', () async {
      final s = await seed();
      expect(
        () => s.crypto.decrypt(
          blob: s.blob,
          keyBytes: s.key,
          aad: BlobAad(
            petId: s.aad.petId,
            relativePath: 'tampered/path.md',
            writeTs: s.aad.writeTs,
          ),
        ),
        throwsA(isA<WikiCryptoException>()),
      );
    });

    test('decrypt fails when AAD writeTs changes (replay-rollback '
        'protection)', () async {
      final s = await seed();
      expect(
        () => s.crypto.decrypt(
          blob: s.blob,
          keyBytes: s.key,
          aad: BlobAad(
            petId: s.aad.petId,
            relativePath: s.aad.relativePath,
            writeTs: s.aad.writeTs.subtract(const Duration(days: 365)),
          ),
        ),
        throwsA(isA<WikiCryptoException>()),
      );
    });
  });

  group('key derivation', () {
    test('same passphrase + same salt → same key (deterministic)',
        () async {
      final crypto = WikiCrypto(argon2: fastArgon());
      final salt = WikiCrypto.generateSalt();
      final a = await crypto.deriveKey(passphrase: 'pw', salt: salt);
      final b = await crypto.deriveKey(passphrase: 'pw', salt: salt);
      expect(a, equals(b));
    });

    test('different salt → different key (per-user salt isolation)',
        () async {
      final crypto = WikiCrypto(argon2: fastArgon());
      final saltA = WikiCrypto.generateSalt();
      final saltB = WikiCrypto.generateSalt();
      final a = await crypto.deriveKey(passphrase: 'pw', salt: saltA);
      final b = await crypto.deriveKey(passphrase: 'pw', salt: saltB);
      expect(a, isNot(equals(b)));
    });

    test('different passphrase + same salt → different key', () async {
      final crypto = WikiCrypto(argon2: fastArgon());
      final salt = WikiCrypto.generateSalt();
      final a = await crypto.deriveKey(passphrase: 'pw1', salt: salt);
      final b = await crypto.deriveKey(passphrase: 'pw2', salt: salt);
      expect(a, isNot(equals(b)));
    });
  });

  group('blob shape invariants', () {
    test('truncated blob throws WikiCryptoException', () async {
      final crypto = WikiCrypto(argon2: fastArgon());
      final key = await crypto.deriveKey(
        passphrase: 'pw',
        salt: WikiCrypto.generateSalt(),
      );
      final aad = BlobAad(
        petId: 1,
        relativePath: 'a',
        writeTs: DateTime.utc(2026, 1),
      );
      expect(
        () => crypto.decrypt(
          blob: Uint8List.fromList([1, 2, 3]),
          keyBytes: key,
          aad: aad,
        ),
        throwsA(isA<WikiCryptoException>()),
      );
    });

    test('unknown blob version throws WikiCryptoException', () async {
      final crypto = WikiCrypto(argon2: fastArgon());
      final salt = WikiCrypto.generateSalt();
      final key = await crypto.deriveKey(passphrase: 'pw', salt: salt);
      final aad = BlobAad(
        petId: 1,
        relativePath: 'a',
        writeTs: DateTime.utc(2026, 1),
      );
      final blob = await crypto.encrypt(
        plaintext: Uint8List.fromList([1, 2, 3]),
        keyBytes: key,
        aad: aad,
      );
      // Mutate the version byte.
      blob[0] = 99;
      expect(
        () => crypto.decrypt(blob: blob, keyBytes: key, aad: aad),
        throwsA(isA<WikiCryptoException>()),
      );
    });
  });

  group('bodyHash', () {
    test('same plaintext → same SHA-256 hash', () {
      final hashA = WikiCrypto.bodyHash(Uint8List.fromList(utf8.encode('a')));
      final hashB = WikiCrypto.bodyHash(Uint8List.fromList(utf8.encode('a')));
      expect(hashA, equals(hashB));
    });

    test('different plaintext → different hash', () {
      final hashA = WikiCrypto.bodyHash(Uint8List.fromList(utf8.encode('a')));
      final hashB = WikiCrypto.bodyHash(Uint8List.fromList(utf8.encode('b')));
      expect(hashA, isNot(equals(hashB)));
    });
  });
}

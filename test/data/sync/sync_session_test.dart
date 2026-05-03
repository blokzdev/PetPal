import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/sync/sync_session.dart';
import 'package:petpal/data/sync/wiki_crypto.dart';

/// Phase 7 task G.2 — passphrase challenge round-trip + locked-
/// state invariants.
///
/// Uses a fast Argon2id (m=8 KiB, t=1) for test speed; the
/// production starting params (m=64 MiB, t=3, p=4) are pinned in
/// `wiki_crypto_test.dart`.
void main() {
  WikiCrypto fastCrypto() => WikiCrypto(
        argon2: Argon2id(
          parallelism: 1,
          memory: 8,
          iterations: 1,
          hashLength: 32,
        ),
      );

  group('SyncSession.setup → unlock round-trip', () {
    test('first device sets up, second device unlocks with same '
        'passphrase', () async {
      final firstDevice = SyncSession(crypto: fastCrypto());
      final challenge = await firstDevice.setup(passphrase: 'correct horse');

      // Second device starts cold, pulls the challenge, unlocks.
      final secondDevice = SyncSession(crypto: fastCrypto());
      final ok = await secondDevice.unlock(
        passphrase: 'correct horse',
        challenge: challenge,
      );
      expect(ok, isTrue);
      expect(secondDevice.isUnlocked, isTrue);
      expect(secondDevice.derivedKey, equals(firstDevice.derivedKey));
    });

    test('wrong passphrase on second device returns false + leaves '
        'session locked', () async {
      final firstDevice = SyncSession(crypto: fastCrypto());
      final challenge = await firstDevice.setup(passphrase: 'right pw');

      final secondDevice = SyncSession(crypto: fastCrypto());
      final ok = await secondDevice.unlock(
        passphrase: 'wrong pw',
        challenge: challenge,
      );
      expect(ok, isFalse);
      expect(secondDevice.isUnlocked, isFalse);
    });
  });

  group('locked-state invariants', () {
    test('derivedKey getter throws StateError when locked', () {
      final session = SyncSession();
      expect(() => session.derivedKey, throwsA(isA<StateError>()));
    });

    test('salt getter throws StateError when locked', () {
      final session = SyncSession();
      expect(() => session.salt, throwsA(isA<StateError>()));
    });

    test('lock() drops the cached key + salt', () async {
      final session = SyncSession(crypto: fastCrypto());
      await session.setup(passphrase: 'pw');
      expect(session.isUnlocked, isTrue);
      session.lock();
      expect(session.isUnlocked, isFalse);
      expect(() => session.derivedKey, throwsA(isA<StateError>()));
    });
  });

  group('challenge JSON round-trip', () {
    test('toJson + fromJson preserves bytes', () async {
      final session = SyncSession(crypto: fastCrypto());
      final challenge = await session.setup(passphrase: 'pw');
      final json = challenge.toJson();
      final decoded = SyncChallenge.fromJson(json);
      expect(decoded.salt, equals(challenge.salt));
      expect(decoded.ciphertext, equals(challenge.ciphertext));
    });

    test('fromJson with missing fields throws FormatException', () {
      expect(
        () => SyncChallenge.fromJson({}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

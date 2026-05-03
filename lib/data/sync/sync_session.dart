import 'dart:convert';
import 'dart:typed_data';

import 'wiki_crypto.dart';

/// Phase 7 task G.2 — passphrase challenge + in-memory key cache.
///
/// First-device flow (passphrase setup):
///   1. User picks passphrase + acknowledges the modal "we cannot
///      recover this" warning.
///   2. Client generates a random salt + derives the Argon2id key.
///   3. Client encrypts the [_challengeConstant] under that key
///      (no AAD; the challenge is intentionally portable across
///      pet IDs / paths).
///   4. Salt + ciphertext upload to the user's `sync_challenges`
///      row on Supabase.
///
/// Second-device flow (passphrase unlock):
///   1. Client pulls the salt + ciphertext from `sync_challenges`.
///   2. User types their passphrase.
///   3. Client derives the key with that salt, attempts to decrypt
///      the challenge ciphertext.
///   4. Match (decrypted plaintext == [_challengeConstant]) →
///      cache the derived key in [SyncSession]; the user is unlocked.
///   5. Mismatch → wrong passphrase, surface inline error.
///
/// **The challenge plaintext is intentionally not secret.** It's a
/// known constant; the security comes from the fact that only a
/// holder of the right passphrase can produce ciphertext that
/// decrypts to it. The challenge ciphertext is uploaded; the
/// plaintext is not.
class SyncChallenge {
  const SyncChallenge({required this.salt, required this.ciphertext});

  /// 16-byte salt fed to Argon2id during key derivation.
  final Uint8List salt;

  /// Wire-format ciphertext (per [WikiCrypto]'s blob shape) of
  /// [_challengeConstant] encrypted under the derived key with
  /// [_challengeAad].
  final Uint8List ciphertext;

  Map<String, Object?> toJson() => {
        'salt_b64': base64.encode(salt),
        'ciphertext_b64': base64.encode(ciphertext),
      };

  static SyncChallenge fromJson(Map<String, Object?> json) {
    final saltStr = json['salt_b64'] as String?;
    final ctStr = json['ciphertext_b64'] as String?;
    if (saltStr == null || ctStr == null) {
      throw const FormatException('SyncChallenge JSON missing fields');
    }
    return SyncChallenge(
      salt: Uint8List.fromList(base64.decode(saltStr)),
      ciphertext: Uint8List.fromList(base64.decode(ctStr)),
    );
  }
}

/// Phase 7 task G.2 — derived-key cache + setup / unlock flow
/// helpers.
///
/// One [SyncSession] per app launch. The derived key lives only in
/// memory; the passphrase itself never leaves the input field. On
/// app close the OS reclaims memory and the key disappears — the
/// user re-enters their passphrase on next launch (or once after
/// sign-out). Future v1.x candidate: persist the key in
/// `flutter_secure_storage` behind a 6-digit PIN, so frequent users
/// don't re-derive every launch. Out of scope for v1.
class SyncSession {
  SyncSession({WikiCrypto? crypto}) : crypto = crypto ?? WikiCrypto();

  /// Known plaintext used for the passphrase challenge. Not a
  /// secret; the security comes from the fact that producing
  /// ciphertext that decrypts to this value requires the right
  /// derived key. The exact bytes are part of the wire protocol —
  /// changing this would invalidate every existing challenge in
  /// every user's account, so it's locked.
  static final Uint8List _challengeConstant = Uint8List.fromList(
    utf8.encode('petpal-e2ee-v1-challenge'),
  );

  /// AAD for the challenge encrypt / decrypt. Uses sentinel
  /// `pet_id = -1` and `path = "_challenge"` so it can never
  /// collide with a real wiki blob's AAD. Write-ts is fixed at the
  /// epoch — the challenge AAD is stable across regenerations of
  /// the same passphrase, so a user re-running setup with the same
  /// passphrase produces the same ciphertext (modulo IV).
  static final BlobAad _challengeAad = BlobAad(
    petId: -1,
    relativePath: '_challenge',
    writeTs: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  final WikiCrypto crypto;

  Uint8List? _derivedKey;
  Uint8List? _salt;

  /// True once a passphrase has been derived this session.
  bool get isUnlocked => _derivedKey != null;

  /// The derived 32-byte AES key. Throws [StateError] if not yet
  /// unlocked — callers should guard with [isUnlocked].
  Uint8List get derivedKey {
    final k = _derivedKey;
    if (k == null) {
      throw StateError('SyncSession is locked — call setup() or unlock() first');
    }
    return k;
  }

  /// The per-user salt loaded from (or generated for) the challenge.
  Uint8List get salt {
    final s = _salt;
    if (s == null) {
      throw StateError('SyncSession has no salt — call setup() or unlock() first');
    }
    return s;
  }

  /// First-device setup. Returns the [SyncChallenge] the caller
  /// uploads to Supabase. Locks the derived key into memory for
  /// this session.
  Future<SyncChallenge> setup({required String passphrase}) async {
    final salt = WikiCrypto.generateSalt();
    final key = await crypto.deriveKey(passphrase: passphrase, salt: salt);
    final ciphertext = await crypto.encrypt(
      plaintext: _challengeConstant,
      keyBytes: key,
      aad: _challengeAad,
    );
    _salt = salt;
    _derivedKey = key;
    return SyncChallenge(salt: salt, ciphertext: ciphertext);
  }

  /// Second-device unlock against an existing challenge. Returns
  /// `true` if the passphrase decrypts the challenge correctly,
  /// `false` if it doesn't (wrong passphrase). On `true` the
  /// derived key is cached for this session.
  Future<bool> unlock({
    required String passphrase,
    required SyncChallenge challenge,
  }) async {
    final key = await crypto.deriveKey(
      passphrase: passphrase,
      salt: challenge.salt,
    );
    try {
      final plaintext = await crypto.decrypt(
        blob: challenge.ciphertext,
        keyBytes: key,
        aad: _challengeAad,
      );
      // Constant-time comparison would be ideal here, but the
      // blob already authenticated via GCM mac — a successful
      // decrypt with matching plaintext is sufficient. Failed
      // decrypt throws above, which we catch and return false.
      if (_bytesEqual(plaintext, _challengeConstant)) {
        _salt = challenge.salt;
        _derivedKey = key;
        return true;
      }
      return false;
    } on WikiCryptoException {
      return false;
    }
  }

  /// Drop the cached key. Called on sign-out + on the explicit
  /// "lock sync" Settings action (v1.x candidate).
  void lock() {
    _derivedKey = null;
    _salt = null;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

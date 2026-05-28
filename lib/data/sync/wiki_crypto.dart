import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' show sha256;

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = random.nextInt(256);
  }
  return out;
}

/// Phase 7 task G.2 — wiki E2EE primitives.
///
/// Implements DECISIONS row 71's Argon2id passphrase-derivation +
/// AES-256-GCM body cipher. **Spec correction relative to row 83**
/// (filed in the G.2 commit's amendment row): the salt is **per-user**,
/// stored in the sync challenge once and reused for every blob in
/// that user's library. Per-object salt as row 83 originally
/// proposed would force a fresh Argon2id derivation (~500ms) per
/// encrypt — multi-minute first-sync wall time for a 500-entry
/// user. Per-user salt + per-object IV is the canonical AES-GCM
/// shape: same key, different IV per encryption is safe from
/// ciphertext-pattern analysis (that's GCM's whole point).
///
/// Wire format for an encrypted blob:
///
/// ```
///   [1 byte version = 1]
///   [12 bytes IV (random per encrypt)]
///   [N bytes ciphertext]
///   [16 bytes GCM mac (authentication tag)]
/// ```
///
/// AAD (associated authenticated data — authenticated but NOT
/// encrypted) is carried out-of-band: the caller supplies it on
/// both encrypt and decrypt, so a tampered `pet_id` / `path` /
/// `write_ts` in the sidecar metadata fails GCM verification.
/// The AAD shape is JSON-encoded `{"pet_id": int, "path": string,
/// "write_ts": int (millis since epoch)}` to keep it deterministic
/// across platforms.
///
/// **No backend recovery** (row 71 lock). The user loses the
/// passphrase → encrypted blobs are unrecoverable. PetPal cannot
/// recover them; that's the honest E2EE shape. The challenge
/// (encrypted-known-constant) lets a second device verify the
/// passphrase locally before any blob decrypt is attempted.
class WikiCrypto {
  WikiCrypto({Argon2id? argon2, AesGcm? aesGcm})
      : _argon2 = argon2 ??
            Argon2id(
              parallelism: 4,
              memory: 64 * 1024, // 64 MiB; row 71 starting param
              iterations: 3,
              hashLength: 32,
            ),
        _aesGcm = aesGcm ?? AesGcm.with256bits();

  static const int blobVersion = 1;
  static const int saltLengthBytes = 16;
  static const int ivLengthBytes = 12;
  static const int macLengthBytes = 16;

  /// Argon2id starting params per DECISIONS row 71. Tunable
  /// post-launch — the version byte at the front of every blob
  /// + a future `kdfParamsVersion` column on the challenge let us
  /// migrate without breaking old blobs.
  final Argon2id _argon2;
  final AesGcm _aesGcm;

  /// Generate a fresh per-user salt. Caller persists this in the
  /// sync challenge so other devices (and re-launches of this one)
  /// derive the same key from the passphrase.
  static Uint8List generateSalt() => _randomBytes(saltLengthBytes);

  /// Derive the AES-256 wrapping key from a passphrase + salt.
  /// Expensive — call once per session and cache the result on
  /// `SyncSession`. Returns the raw 32 bytes so the cache can hold
  /// them as a `Uint8List` rather than the package's opaque
  /// [SecretKey] handle (which complicates Riverpod state).
  Future<Uint8List> deriveKey({
    required String passphrase,
    required Uint8List salt,
  }) async {
    final secret = await _argon2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final bytes = await secret.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// Encrypt `plaintext` under the cached derived `keyBytes`. Returns
  /// the wire-format blob. AAD is authenticated (any tamper to
  /// pet_id / path / write_ts on decrypt fails GCM verification).
  Future<Uint8List> encrypt({
    required Uint8List plaintext,
    required Uint8List keyBytes,
    required BlobAad aad,
  }) async {
    if (keyBytes.length != 32) {
      throw ArgumentError('keyBytes must be 32 bytes (256-bit key)');
    }
    final iv = _randomBytes(ivLengthBytes);
    final aadBytes = aad.encode();
    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: SecretKey(keyBytes),
      nonce: iv,
      aad: aadBytes,
    );
    final out = BytesBuilder()
      ..addByte(blobVersion)
      ..add(iv)
      ..add(secretBox.cipherText)
      ..add(secretBox.mac.bytes);
    return out.toBytes();
  }

  /// Decrypt a wire-format blob. Returns the plaintext bytes.
  /// Throws [WikiCryptoException] on any failure — wrong key,
  /// tampered ciphertext, AAD mismatch, version mismatch, or
  /// truncation.
  Future<Uint8List> decrypt({
    required Uint8List blob,
    required Uint8List keyBytes,
    required BlobAad aad,
  }) async {
    if (keyBytes.length != 32) {
      throw ArgumentError('keyBytes must be 32 bytes (256-bit key)');
    }
    if (blob.length < 1 + ivLengthBytes + macLengthBytes) {
      throw const WikiCryptoException('blob is truncated');
    }
    final version = blob[0];
    if (version != blobVersion) {
      throw WikiCryptoException(
        'unknown blob version $version (expected $blobVersion)',
      );
    }
    const ivStart = 1;
    const ivEnd = ivStart + ivLengthBytes;
    final macStart = blob.length - macLengthBytes;
    if (macStart <= ivEnd) {
      throw const WikiCryptoException('blob is truncated');
    }
    final iv = blob.sublist(ivStart, ivEnd);
    final cipherText = blob.sublist(ivEnd, macStart);
    final mac = Mac(blob.sublist(macStart));
    try {
      final plaintext = await _aesGcm.decrypt(
        SecretBox(cipherText, nonce: iv, mac: mac),
        secretKey: SecretKey(keyBytes),
        aad: aad.encode(),
      );
      return Uint8List.fromList(plaintext);
    } on SecretBoxAuthenticationError catch (e) {
      throw WikiCryptoException(
        'authentication failed (wrong key, tampered ciphertext, '
        'or AAD mismatch): ${e.message}',
      );
    }
  }

  /// SHA-256 hex digest of the plaintext. Stored in the
  /// `wiki_sync_objects` sidecar so clients can compare without
  /// downloading + decrypting (server can't verify the hash matches
  /// — it's a trust-the-client field, used for client-side LWW
  /// comparison + dedup per DECISIONS row 83).
  static String bodyHash(Uint8List plaintext) {
    return sha256.convert(plaintext).toString();
  }
}

/// Associated authenticated data attached to each encrypted blob.
/// Encoded as deterministic JSON so the byte sequence matches
/// across platforms.
class BlobAad {
  const BlobAad({
    required this.petId,
    required this.relativePath,
    required this.writeTs,
  });

  final int petId;
  final String relativePath;
  final DateTime writeTs;

  /// Deterministic JSON encoding. Keys ordered alphabetically;
  /// timestamp serialized as integer milliseconds since Unix epoch
  /// to avoid time-zone formatting drift.
  Uint8List encode() {
    final payload = '{"path":${jsonEncode(relativePath)},'
        '"pet_id":$petId,'
        '"write_ts":${writeTs.toUtc().millisecondsSinceEpoch}}';
    return Uint8List.fromList(utf8.encode(payload));
  }
}

class WikiCryptoException implements Exception {
  const WikiCryptoException(this.message);
  final String message;
  @override
  String toString() => 'WikiCryptoException: $message';
}

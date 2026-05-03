import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'sync_backend.dart';
import 'sync_session.dart';

/// Phase 7 task H.1.b — production [SyncBackend] backed by Supabase.
///
/// Implementation is REST-direct against:
///   - Storage REST API (`/storage/v1/object/wiki/...`) for blob
///     upload + download
///   - PostgREST (`/rest/v1/sync_challenges`,
///     `/rest/v1/wiki_sync_objects`) for the per-user passphrase
///     challenge row + the per-object sidecar metadata
///
/// Uses a plain `http.Client` rather than the supabase package's
/// helpers so the test suite can drive every endpoint via
/// `http.testing.MockClient` without standing up a real Supabase.
/// Mirrors the [ProxyTransport] testability pattern from A.3.
///
/// **JWT freshness.** The accessToken is read lazily via [jwtSource]
/// on every request — `supabase_flutter` refreshes the token under
/// the hood, so re-reading per-call always gets the latest. If the
/// JWT goes stale (sign-out, expiry without refresh), [jwtSource]
/// returns the empty string and [isAuthenticated] flips false.
///
/// Per DECISIONS row 83 schema:
///   - object key: `<userId>/<petId>/<relativePath>.enc`
///   - sidecar fields: `(user_id, pet_id, relative_path, write_ts,
///     body_hash, deleted, updated_at)`
///   - challenge fields: `(user_id, salt_b64, ciphertext_b64,
///     created_at, updated_at)`
///
/// Per row 84: salt is per-user (single `sync_challenges` row), not
/// per-object. The wire format keys (`salt_b64`, `ciphertext_b64`)
/// match `SyncChallenge.toJson` / `fromJson` byte-for-byte.
class SupabaseSyncBackend implements SyncBackend {
  SupabaseSyncBackend({
    required String supabaseUrl,
    required String anonKey,
    required String userId,
    required String Function() jwtSource,
    http.Client? httpClient,
  })  : _url = _stripTrailingSlash(supabaseUrl),
        _anonKey = anonKey,
        _userId = userId,
        _jwtSource = jwtSource,
        _http = httpClient ?? http.Client();

  static const _bucket = 'wiki';

  final String _url;
  final String _anonKey;
  final String _userId;
  final String Function() _jwtSource;
  final http.Client _http;

  static String _stripTrailingSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  Map<String, String> _baseHeaders() {
    final jwt = _jwtSource();
    return <String, String>{
      'apikey': _anonKey,
      'Authorization': 'Bearer $jwt',
    };
  }

  Map<String, String> _jsonHeaders({String? prefer}) {
    final h = _baseHeaders();
    h['Content-Type'] = 'application/json';
    h['Accept'] = 'application/json';
    if (prefer != null) h['Prefer'] = prefer;
    return h;
  }

  @override
  bool get isAuthenticated => _jwtSource().isNotEmpty;

  // ─── sync_challenges ─────────────────────────────────────────────

  @override
  Future<SyncChallenge?> fetchChallenge() async {
    _enforceAuth('fetchChallenge');
    final uri = Uri.parse(
      '$_url/rest/v1/sync_challenges'
      '?user_id=eq.$_userId'
      '&select=salt_b64,ciphertext_b64',
    );
    final res = await _http.get(uri, headers: _jsonHeaders());
    if (res.statusCode != 200) {
      throw SyncBackendException(
        'fetchChallenge failed (${res.statusCode}): ${res.body}',
      );
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    if (list.isEmpty) return null;
    return SyncChallenge.fromJson(list.first as Map<String, Object?>);
  }

  @override
  Future<void> storeChallenge(SyncChallenge challenge) async {
    _enforceAuth('storeChallenge');
    final uri = Uri.parse('$_url/rest/v1/sync_challenges');
    final body = <String, Object?>{
      'user_id': _userId,
      ...challenge.toJson(),
    };
    final res = await _http.post(
      uri,
      headers: _jsonHeaders(
        prefer: 'resolution=merge-duplicates,return=minimal',
      ),
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 &&
        res.statusCode != 201 &&
        res.statusCode != 204) {
      throw SyncBackendException(
        'storeChallenge failed (${res.statusCode}): ${res.body}',
      );
    }
  }

  // ─── wiki_sync_objects ───────────────────────────────────────────

  @override
  Future<List<RemoteObjectMeta>> listSince({
    required int petId,
    required DateTime since,
  }) async {
    _enforceAuth('listSince');
    final sinceIso = since.toUtc().toIso8601String();
    final uri = Uri.parse(
      '$_url/rest/v1/wiki_sync_objects'
      '?user_id=eq.$_userId'
      '&pet_id=eq.$petId'
      '&updated_at=gt.$sinceIso'
      '&select=pet_id,relative_path,write_ts,body_hash,deleted',
    );
    final res = await _http.get(uri, headers: _jsonHeaders());
    if (res.statusCode != 200) {
      throw SyncBackendException(
        'listSince failed (${res.statusCode}): ${res.body}',
      );
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .cast<Map<String, Object?>>()
        .map(RemoteObjectMeta.fromJson)
        .toList(growable: false);
  }

  Future<void> _upsertSyncObject(RemoteObjectMeta meta) async {
    final uri = Uri.parse('$_url/rest/v1/wiki_sync_objects');
    final body = <String, Object?>{
      'user_id': _userId,
      ...meta.toJson(),
    };
    final res = await _http.post(
      uri,
      headers: _jsonHeaders(
        prefer: 'resolution=merge-duplicates,return=minimal',
      ),
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 &&
        res.statusCode != 201 &&
        res.statusCode != 204) {
      throw SyncBackendException(
        'wiki_sync_objects upsert failed (${res.statusCode}): ${res.body}',
      );
    }
  }

  // ─── Storage ─────────────────────────────────────────────────────

  @override
  Future<Uint8List> downloadObject(String objectKey) async {
    _enforceAuth('downloadObject');
    final uri = Uri.parse('$_url/storage/v1/object/$_bucket/$objectKey');
    final res = await _http.get(uri, headers: _baseHeaders());
    if (res.statusCode == 404) {
      throw SyncBackendException('object not found: $objectKey');
    }
    if (res.statusCode != 200) {
      throw SyncBackendException(
        'downloadObject failed (${res.statusCode}): ${res.body}',
      );
    }
    return res.bodyBytes;
  }

  @override
  Future<void> uploadObject({
    required String objectKey,
    required Uint8List blob,
    required RemoteObjectMeta meta,
  }) async {
    _enforceAuth('uploadObject');

    // Per the SyncBackend contract: storage upload first; only on
    // success do we upsert the sidecar row. Otherwise a failed upload
    // could leave the sidecar claiming a blob exists that doesn't.
    final storageUri = Uri.parse('$_url/storage/v1/object/$_bucket/$objectKey');
    final headers = _baseHeaders();
    headers['Content-Type'] = 'application/octet-stream';
    // x-upsert lets us re-upload an existing object; matches Storage's
    // S3 versioning model (the prior version is preserved as a delete
    // marker behind the scenes, per DECISIONS row 83's recovery floor).
    headers['x-upsert'] = 'true';

    final storageRes = await _http.post(
      storageUri,
      headers: headers,
      body: blob,
    );
    if (storageRes.statusCode != 200 && storageRes.statusCode != 201) {
      throw SyncBackendException(
        'storage upload failed (${storageRes.statusCode}): ${storageRes.body}',
      );
    }

    await _upsertSyncObject(meta);
  }

  @override
  Future<void> markDeleted({
    required String objectKey,
    required RemoteObjectMeta meta,
  }) async {
    _enforceAuth('markDeleted');
    // Per DECISIONS row 83: the blob STAYS (S3 versioning floor); we
    // only flip the sidecar row's `deleted` flag. Other devices
    // reconcile the deletion on next pull.
    final tombstone = RemoteObjectMeta(
      petId: meta.petId,
      relativePath: meta.relativePath,
      writeTs: meta.writeTs,
      bodyHash: meta.bodyHash,
      deleted: true,
    );
    await _upsertSyncObject(tombstone);
  }

  void _enforceAuth(String op) {
    if (!isAuthenticated) {
      throw SyncBackendException(
        '$op requires a signed-in user — JWT not available.',
      );
    }
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpal/data/sync/supabase_sync_backend.dart';
import 'package:petpal/data/sync/sync_backend.dart';
import 'package:petpal/data/sync/sync_session.dart';

/// Phase 7 task H.1.b — SupabaseSyncBackend HTTP wire-format tests.
///
/// Drives every endpoint via `MockClient` so the test suite can
/// verify URL / header / body construction without standing up a
/// real Supabase. Captures the [http.Request] passed to each
/// handler and asserts on it.
void main() {
  const url = 'https://abcdef.supabase.co';
  const anon = 'anon-key-stub';
  const userId = '00000000-0000-0000-0000-000000000aaa';

  group('isAuthenticated + JWT freshness', () {
    test('isAuthenticated reflects the JWT source closure', () {
      var jwt = '';
      final backend = _backend(
        jwtSource: () => jwt,
        client: MockClient((_) async => http.Response('[]', 200)),
      );
      expect(backend.isAuthenticated, isFalse);
      jwt = 'fresh-token';
      expect(backend.isAuthenticated, isTrue,
          reason: 'JWT freshness — backend re-reads the closure on '
              'every isAuthenticated call so token refresh in '
              'supabase_flutter is picked up without rebuilding.');
    });

    test('every request reads JWT from the closure', () async {
      var jwt = 'first-token';
      final captured = <String>[];
      final mock = MockClient((req) async {
        captured.add(req.headers['Authorization'] ?? '');
        return http.Response('[]', 200);
      });
      final backend = _backend(jwtSource: () => jwt, client: mock);

      await backend.fetchChallenge();
      jwt = 'rotated-token';
      await backend.fetchChallenge();

      expect(captured, ['Bearer first-token', 'Bearer rotated-token']);
    });

    test('all ops throw SyncBackendException when JWT is empty', () async {
      final mock = MockClient(
        (_) async => fail('Should not reach the network with empty JWT'),
      );
      final backend = _backend(jwtSource: () => '', client: mock);
      expect(backend.isAuthenticated, isFalse);

      await expectLater(
        backend.fetchChallenge(),
        throwsA(isA<SyncBackendException>()),
      );
      await expectLater(
        backend.listSince(petId: 1, since: DateTime(2020)),
        throwsA(isA<SyncBackendException>()),
      );
      await expectLater(
        backend.downloadObject('$userId/1/x.md.enc'),
        throwsA(isA<SyncBackendException>()),
      );
    });
  });

  group('fetchChallenge', () {
    test('returns null when the result array is empty', () async {
      final backend = _backend(
        client: MockClient((_) async => http.Response('[]', 200)),
      );
      expect(await backend.fetchChallenge(), isNull);
    });

    test('parses challenge from a populated row', () async {
      final body = jsonEncode([
        {
          'salt_b64': base64.encode(List<int>.filled(16, 7)),
          'ciphertext_b64': base64.encode(List<int>.filled(40, 9)),
        }
      ]);
      final backend = _backend(
        client: MockClient((_) async => http.Response(body, 200)),
      );

      final ch = await backend.fetchChallenge();

      expect(ch, isA<SyncChallenge>());
      expect(ch!.salt.length, 16);
      expect(ch.ciphertext.length, 40);
    });

    test('builds correct URL with user_id eq filter', () async {
      Uri? capturedUri;
      final mock = MockClient((req) async {
        capturedUri = req.url;
        return http.Response('[]', 200);
      });
      final backend = _backend(client: mock);

      await backend.fetchChallenge();

      expect(capturedUri.toString(),
          contains('/rest/v1/sync_challenges'));
      expect(capturedUri.toString(),
          contains('user_id=eq.$userId'));
      expect(capturedUri.toString(),
          contains('select=salt_b64,ciphertext_b64'));
    });

    test('throws SyncBackendException on non-200', () async {
      final backend = _backend(
        client: MockClient((_) async =>
            http.Response('{"message":"row level security"}', 401)),
      );
      await expectLater(
        backend.fetchChallenge(),
        throwsA(isA<SyncBackendException>()),
      );
    });
  });

  group('storeChallenge', () {
    test('POSTs body with user_id + Prefer merge-duplicates', () async {
      http.Request? capturedReq;
      final mock = MockClient((req) async {
        capturedReq = req;
        return http.Response('', 201);
      });
      final backend = _backend(client: mock);
      final challenge = SyncChallenge(
        salt: Uint8List.fromList(List.filled(16, 1)),
        ciphertext: Uint8List.fromList(List.filled(40, 2)),
      );

      await backend.storeChallenge(challenge);

      expect(capturedReq, isNotNull);
      expect(capturedReq!.method, 'POST');
      expect(capturedReq!.url.toString(),
          '$url/rest/v1/sync_challenges');
      expect(capturedReq!.headers['Content-Type'], 'application/json');
      expect(capturedReq!.headers['Prefer'],
          'resolution=merge-duplicates,return=minimal');
      final body = jsonDecode(capturedReq!.body) as Map<String, Object?>;
      expect(body['user_id'], userId);
      expect(body['salt_b64'], isA<String>());
      expect(body['ciphertext_b64'], isA<String>());
    });

    test('accepts 200/201/204 as success', () async {
      for (final status in [200, 201, 204]) {
        final backend = _backend(
          client: MockClient((_) async => http.Response('', status)),
        );
        await backend.storeChallenge(SyncChallenge(
          salt: Uint8List(16),
          ciphertext: Uint8List(40),
        ));
      }
    });

    test('throws on 5xx', () async {
      final backend = _backend(
        client:
            MockClient((_) async => http.Response('boom', 500)),
      );
      await expectLater(
        backend.storeChallenge(SyncChallenge(
          salt: Uint8List(16),
          ciphertext: Uint8List(40),
        )),
        throwsA(isA<SyncBackendException>()),
      );
    });
  });

  group('listSince', () {
    test('builds URL with pet_id + updated_at filters in ISO-8601', () async {
      Uri? capturedUri;
      final mock = MockClient((req) async {
        capturedUri = req.url;
        return http.Response('[]', 200);
      });
      final backend = _backend(client: mock);
      final since = DateTime.utc(2026, 5, 1, 12);

      await backend.listSince(petId: 42, since: since);

      final s = capturedUri.toString();
      expect(s, contains('/rest/v1/wiki_sync_objects'));
      expect(s, contains('user_id=eq.$userId'));
      expect(s, contains('pet_id=eq.42'));
      expect(s, contains('updated_at=gt.${since.toIso8601String()}'));
    });

    test('parses RemoteObjectMeta rows from response', () async {
      final ts = DateTime.utc(2026, 5, 3, 10).millisecondsSinceEpoch;
      final body = jsonEncode([
        {
          'pet_id': 7,
          'relative_path': 'vet/2026-05-03-checkup.md',
          'write_ts': ts,
          'body_hash': 'a' * 64,
          'deleted': false,
        },
        {
          'pet_id': 7,
          'relative_path': 'food/log.md',
          'write_ts': ts + 1000,
          'body_hash': 'b' * 64,
          'deleted': true,
        },
      ]);
      final backend = _backend(
        client: MockClient((_) async => http.Response(body, 200)),
      );

      final rows =
          await backend.listSince(petId: 7, since: DateTime(2020));

      expect(rows.length, 2);
      expect(rows[0].petId, 7);
      expect(rows[0].relativePath, 'vet/2026-05-03-checkup.md');
      expect(rows[0].deleted, isFalse);
      expect(rows[1].deleted, isTrue);
    });
  });

  group('downloadObject', () {
    test('GETs the storage object path + returns body bytes', () async {
      http.BaseRequest? capturedReq;
      final blob = Uint8List.fromList([1, 2, 3, 4, 5]);
      final mock = MockClient((req) async {
        capturedReq = req;
        return http.Response.bytes(blob, 200);
      });
      final backend = _backend(client: mock);

      final got = await backend.downloadObject('$userId/1/vet/x.md.enc');

      expect(capturedReq!.method, 'GET');
      expect(
        capturedReq!.url.toString(),
        '$url/storage/v1/object/wiki/$userId/1/vet/x.md.enc',
      );
      expect(got, blob);
    });

    test('throws "not found" on 404', () async {
      final backend = _backend(
        client: MockClient((_) async => http.Response('', 404)),
      );
      await expectLater(
        backend.downloadObject('$userId/1/missing.md.enc'),
        throwsA(
          isA<SyncBackendException>().having(
            (e) => e.message,
            'message',
            contains('not found'),
          ),
        ),
      );
    });

    test('throws on other non-200', () async {
      final backend = _backend(
        client: MockClient((_) async => http.Response('', 500)),
      );
      await expectLater(
        backend.downloadObject('$userId/1/x.md.enc'),
        throwsA(isA<SyncBackendException>()),
      );
    });
  });

  group('uploadObject', () {
    test('POSTs blob to Storage, then upserts sidecar — in order',
        () async {
      final calls = <String>[];
      final mock = MockClient((req) async {
        if (req.url.path.startsWith('/storage/v1/object/wiki/')) {
          calls.add('storage');
          expect(req.headers['Content-Type'], 'application/octet-stream');
          expect(req.headers['x-upsert'], 'true');
          expect(req.bodyBytes, [1, 2, 3]);
          return http.Response('', 200);
        }
        if (req.url.path == '/rest/v1/wiki_sync_objects') {
          calls.add('sidecar');
          return http.Response('', 201);
        }
        fail('Unexpected URL: ${req.url}');
      });
      final backend = _backend(client: mock);
      final ts = DateTime.utc(2026, 5, 3);

      await backend.uploadObject(
        objectKey: '$userId/1/vet/x.md.enc',
        blob: Uint8List.fromList([1, 2, 3]),
        meta: RemoteObjectMeta(
          petId: 1,
          relativePath: 'vet/x.md',
          writeTs: ts,
          bodyHash: 'h' * 64,
        ),
      );

      expect(calls, ['storage', 'sidecar'],
          reason: 'Storage upload must succeed before the sidecar '
              'upsert — otherwise a failed upload could leave the '
              'sidecar claiming a blob exists that doesn\'t.');
    });

    test('does NOT upsert sidecar when Storage upload fails', () async {
      var sidecarCalled = false;
      final mock = MockClient((req) async {
        if (req.url.path.startsWith('/storage/v1/object/wiki/')) {
          return http.Response('quota exceeded', 413);
        }
        if (req.url.path == '/rest/v1/wiki_sync_objects') {
          sidecarCalled = true;
        }
        return http.Response('', 200);
      });
      final backend = _backend(client: mock);

      await expectLater(
        backend.uploadObject(
          objectKey: '$userId/1/x.md.enc',
          blob: Uint8List.fromList([1, 2]),
          meta: RemoteObjectMeta(
            petId: 1,
            relativePath: 'x.md',
            writeTs: DateTime.utc(2026, 5, 3),
            bodyHash: 'h' * 64,
          ),
        ),
        throwsA(isA<SyncBackendException>()),
      );

      expect(sidecarCalled, isFalse);
    });
  });

  group('markDeleted', () {
    test('upserts sidecar with deleted=true, makes NO storage call',
        () async {
      var storageCalled = false;
      Map<String, Object?>? sidecarBody;
      final mock = MockClient((req) async {
        if (req.url.path.startsWith('/storage/v1/object/wiki/')) {
          storageCalled = true;
          return http.Response('', 200);
        }
        if (req.url.path == '/rest/v1/wiki_sync_objects' &&
            req.method == 'POST') {
          sidecarBody = jsonDecode(req.body) as Map<String, Object?>;
          return http.Response('', 204);
        }
        fail('Unexpected: ${req.method} ${req.url}');
      });
      final backend = _backend(client: mock);

      await backend.markDeleted(
        objectKey: '$userId/1/x.md.enc',
        meta: RemoteObjectMeta(
          petId: 1,
          relativePath: 'x.md',
          writeTs: DateTime.utc(2026, 5, 3),
          bodyHash: 'h' * 64,
        ),
      );

      expect(storageCalled, isFalse,
          reason: 'Per row 83: blob STAYS (S3 versioning floor). '
              'markDeleted only flips the sidecar `deleted` flag.');
      expect(sidecarBody, isNotNull);
      expect(sidecarBody!['deleted'], isTrue);
      expect(sidecarBody!['relative_path'], 'x.md');
      expect(sidecarBody!['pet_id'], 1);
    });
  });

  group('URL hygiene', () {
    test('strips trailing slash from supabaseUrl', () async {
      Uri? capturedUri;
      final mock = MockClient((req) async {
        capturedUri = req.url;
        return http.Response('[]', 200);
      });
      final backend = SupabaseSyncBackend(
        supabaseUrl: '$url/',
        anonKey: anon,
        userId: userId,
        jwtSource: () => 'jwt',
        httpClient: mock,
      );

      await backend.fetchChallenge();

      expect(
        capturedUri!.toString(),
        startsWith('$url/rest/'),
        reason: 'No double-slash between origin and path even when '
            'caller passes URL with trailing /',
      );
    });

    test('apikey + Authorization headers on every request', () async {
      Map<String, String>? capturedHeaders;
      final mock = MockClient((req) async {
        capturedHeaders = req.headers;
        return http.Response('[]', 200);
      });
      final backend = _backend(client: mock);

      await backend.fetchChallenge();

      expect(capturedHeaders!['apikey'], anon);
      expect(capturedHeaders!['Authorization'], 'Bearer jwt');
    });
  });
}

SupabaseSyncBackend _backend({
  String Function()? jwtSource,
  http.Client? client,
}) {
  return SupabaseSyncBackend(
    supabaseUrl: 'https://abcdef.supabase.co',
    anonKey: 'anon-key-stub',
    userId: '00000000-0000-0000-0000-000000000aaa',
    jwtSource: jwtSource ?? () => 'jwt',
    httpClient: client,
  );
}

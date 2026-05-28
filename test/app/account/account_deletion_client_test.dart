import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpal/app/account/account_deletion_client.dart';

/// Phase 7 task H.1.d — SupabaseAccountDeletionClient HTTP wire tests.
void main() {
  const url = 'https://abcdef.supabase.co';
  const anon = 'anon-key-stub';

  group('requestDeletion — happy path', () {
    test('POSTs to /functions/v1/account-delete with auth headers',
        () async {
      http.Request? captured;
      final retention = DateTime.utc(2026, 6, 2, 10);
      final client = _client(
        mock: MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({
              'retention_window_ends_at': retention.toIso8601String(),
            }),
            200,
          );
        }),
      );

      final got = await client.requestDeletion();

      expect(captured!.method, 'POST');
      expect(
        captured!.url.toString(),
        '$url/functions/v1/account-delete',
      );
      expect(captured!.headers['apikey'], anon);
      expect(captured!.headers['Authorization'], 'Bearer jwt-stub');
      expect(captured!.headers['Content-Type'], 'application/json');
      expect(got, retention);
    });
  });

  group('requestDeletion — error mapping', () {
    test('throws AccountDeletionException on 401', () async {
      final client = _client(
        mock: MockClient(
          (_) async => http.Response('{"error":"invalid_jwt"}', 401),
        ),
      );
      await expectLater(
        client.requestDeletion(),
        throwsA(isA<AccountDeletionException>()),
      );
    });

    test('throws on 500', () async {
      final client = _client(
        mock: MockClient((_) async => http.Response('boom', 500)),
      );
      await expectLater(
        client.requestDeletion(),
        throwsA(isA<AccountDeletionException>()),
      );
    });

    test('throws when JWT is empty (short-circuits — no network call)',
        () async {
      final client = _client(
        jwtSource: () => '',
        mock: MockClient(
          (_) async => fail('Should not reach the network with empty JWT'),
        ),
      );
      await expectLater(
        client.requestDeletion(),
        throwsA(isA<AccountDeletionException>()),
      );
    });

    test('throws on missing retention_window_ends_at in 200 response',
        () async {
      final client = _client(
        mock: MockClient(
          (_) async => http.Response('{}', 200),
        ),
      );
      await expectLater(
        client.requestDeletion(),
        throwsA(
          isA<AccountDeletionException>().having(
            (e) => e.message,
            'message',
            contains('retention_window_ends_at'),
          ),
        ),
      );
    });

    test('throws on malformed timestamp in response', () async {
      final client = _client(
        mock: MockClient(
          (_) async => http.Response(
            '{"retention_window_ends_at":"not-a-date"}',
            200,
          ),
        ),
      );
      await expectLater(
        client.requestDeletion(),
        throwsA(isA<AccountDeletionException>()),
      );
    });
  });

  group('Wire format hygiene', () {
    test('strips trailing slash from supabaseUrl', () async {
      Uri? captured;
      final client = SupabaseAccountDeletionClient(
        supabaseUrl: '$url/',
        anonKey: anon,
        jwtSource: () => 'jwt-stub',
        httpClient: MockClient((req) async {
          captured = req.url;
          return http.Response(
            '{"retention_window_ends_at":"2026-06-02T00:00:00Z"}',
            200,
          );
        }),
      );

      await client.requestDeletion();

      expect(captured!.toString(), '$url/functions/v1/account-delete');
    });

    test('every request reads JWT from the closure', () async {
      var jwt = 'first-token';
      final captured = <String>[];
      final client = _client(
        jwtSource: () => jwt,
        mock: MockClient((req) async {
          captured.add(req.headers['Authorization'] ?? '');
          return http.Response(
            '{"retention_window_ends_at":"2026-06-02T00:00:00Z"}',
            200,
          );
        }),
      );

      await client.requestDeletion();
      jwt = 'rotated-token';
      await client.requestDeletion();

      expect(captured, ['Bearer first-token', 'Bearer rotated-token']);
    });
  });

  group('FakeAccountDeletionClient', () {
    test('returns scripted retention end + counts calls', () async {
      final fake = FakeAccountDeletionClient(
        retentionEnd: DateTime.utc(2026, 6),
      );

      expect(await fake.requestDeletion(), DateTime.utc(2026, 6));
      expect(fake.callCount, 1);

      fake.scriptRetentionEnd(DateTime.utc(2026, 7));
      expect(await fake.requestDeletion(), DateTime.utc(2026, 7));
      expect(fake.callCount, 2);
    });

    test('throws scripted error then clears for the next call', () async {
      final fake = FakeAccountDeletionClient();
      const err = AccountDeletionException('forced');
      fake.scriptError(err);

      expect(() => fake.requestDeletion(), throwsA(same(err)));

      // Second call returns the default retention end.
      expect(await fake.requestDeletion(), isA<DateTime>());
      expect(fake.callCount, 2);
    });

    test('cancelDeletion default — no pending', () async {
      final fake = FakeAccountDeletionClient();
      expect(await fake.cancelDeletion(), isFalse);
      expect(fake.cancelCallCount, 1);
    });

    test('cancelDeletion — scripted pending state', () async {
      final fake = FakeAccountDeletionClient(wasPending: true);
      expect(await fake.cancelDeletion(), isTrue);
      fake.scriptCancelWasPending(false);
      expect(await fake.cancelDeletion(), isFalse);
    });

    test('cancelDeletion — scripted error then clears', () async {
      final fake = FakeAccountDeletionClient();
      const err = AccountDeletionException('cancel-forced');
      fake.scriptCancelError(err);
      expect(() => fake.cancelDeletion(), throwsA(same(err)));
      expect(await fake.cancelDeletion(), isFalse);
      expect(fake.cancelCallCount, 2);
    });
  });

  // Phase 7 task H.1.d.undo — proactive client-driven cancel.
  group('cancelDeletion — Supabase wire', () {
    test('POSTs to /functions/v1/cancel-account-delete and parses '
        'was_pending=true', () async {
      http.Request? captured;
      final client = _client(
        mock: MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({'was_pending': true}),
            200,
          );
        }),
      );

      final wasPending = await client.cancelDeletion();
      expect(wasPending, isTrue);

      expect(captured!.method, 'POST');
      expect(
        captured!.url.toString(),
        '$url/functions/v1/cancel-account-delete',
      );
      expect(captured!.headers['apikey'], anon);
      expect(captured!.headers['Authorization'], 'Bearer jwt-stub');
    });

    test('parses was_pending=false (idempotent no-op)', () async {
      final client = _client(
        mock: MockClient(
          (_) async => http.Response('{"was_pending":false}', 200),
        ),
      );
      expect(await client.cancelDeletion(), isFalse);
    });

    test('throws on 401', () async {
      final client = _client(
        mock: MockClient(
          (_) async => http.Response('{"error":"invalid_jwt"}', 401),
        ),
      );
      await expectLater(
        client.cancelDeletion(),
        throwsA(isA<AccountDeletionException>()),
      );
    });

    test('throws when JWT empty — no network call', () async {
      final client = _client(
        jwtSource: () => '',
        mock: MockClient(
          (_) async => fail('cancelDeletion should short-circuit on empty JWT'),
        ),
      );
      await expectLater(
        client.cancelDeletion(),
        throwsA(isA<AccountDeletionException>()),
      );
    });
  });
}

SupabaseAccountDeletionClient _client({
  String Function()? jwtSource,
  http.Client? mock,
}) {
  return SupabaseAccountDeletionClient(
    supabaseUrl: 'https://abcdef.supabase.co',
    anonKey: 'anon-key-stub',
    jwtSource: jwtSource ?? () => 'jwt-stub',
    httpClient: mock,
  );
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/app/entitlement/supabase_entitlements_client.dart';

/// Phase 7 task H.1.c.2 — SupabaseEntitlementsClient HTTP wire tests.
///
/// Drives PostgREST `GET /rest/v1/entitlements` via MockClient.
/// Mirrors the SupabaseSyncBackend test pattern.
void main() {
  const url = 'https://abcdef.supabase.co';
  const anon = 'anon-key-stub';
  const userId = '00000000-0000-0000-0000-000000000aaa';

  group('fetch — happy path', () {
    test('parses a populated row into Entitlement', () async {
      final body = jsonEncode([
        {
          'user_id': userId,
          'state': 'pro_monthly',
          'renewal_date': '2026-06-15T00:00:00+00:00',
          'grace_until': null,
          'photo_credits_balance': 25,
          'monthly_text_count': 17,
          'monthly_vision_count': 4,
          'counter_period_start': '2026-05-01T00:00:00+00:00',
        }
      ]);
      final client = _client(
        mock: MockClient((_) async => http.Response(body, 200)),
      );

      final ent = await client.fetch(userId);

      expect(ent, isNotNull);
      expect(ent!.state, EntitlementState.proMonthly);
      expect(ent.userId, userId);
      expect(ent.photoCreditsBalance, 25);
      expect(ent.monthlyTextCount, 17);
      expect(ent.monthlyVisionCount, 4);
      expect(ent.renewalDate, DateTime.utc(2026, 6, 15));
      expect(ent.graceUntil, isNull);
      expect(ent.fetchedAt, isNotNull);
    });

    test('returns null when the result array is empty (no row yet)',
        () async {
      final client = _client(
        mock: MockClient((_) async => http.Response('[]', 200)),
      );
      expect(await client.fetch(userId), isNull);
    });

    test('builds correct URL with user_id eq filter', () async {
      Uri? captured;
      final client = _client(
        mock: MockClient((req) async {
          captured = req.url;
          return http.Response('[]', 200);
        }),
      );

      await client.fetch(userId);

      final s = captured.toString();
      expect(s, contains('/rest/v1/entitlements'));
      expect(s, contains('user_id=eq.$userId'));
      expect(s, contains('select=user_id,state,renewal_date'));
    });

    test('apikey + Authorization headers on every request', () async {
      Map<String, String>? headers;
      final client = _client(
        mock: MockClient((req) async {
          headers = req.headers;
          return http.Response('[]', 200);
        }),
      );

      await client.fetch(userId);

      expect(headers!['apikey'], anon);
      expect(headers!['Authorization'], 'Bearer jwt-stub');
      expect(headers!['Accept'], 'application/json');
    });
  });

  group('fetch — error mapping', () {
    test('throws EntitlementsClientException on 401', () async {
      final client = _client(
        mock: MockClient(
          (_) async => http.Response('{"message":"jwt expired"}', 401),
        ),
      );
      await expectLater(
        client.fetch(userId),
        throwsA(isA<EntitlementsClientException>()),
      );
    });

    test('throws on 500', () async {
      final client = _client(
        mock: MockClient((_) async => http.Response('boom', 500)),
      );
      await expectLater(
        client.fetch(userId),
        throwsA(isA<EntitlementsClientException>()),
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
        client.fetch(userId),
        throwsA(isA<EntitlementsClientException>()),
      );
    });
  });

  group('JWT freshness', () {
    test('every fetch reads JWT from the closure', () async {
      var jwt = 'first-token';
      final captured = <String>[];
      final client = _client(
        jwtSource: () => jwt,
        mock: MockClient((req) async {
          captured.add(req.headers['Authorization'] ?? '');
          return http.Response('[]', 200);
        }),
      );

      await client.fetch(userId);
      jwt = 'rotated-token';
      await client.fetch(userId);

      expect(captured, ['Bearer first-token', 'Bearer rotated-token']);
    });
  });

  group('Wire format hygiene', () {
    test('strips trailing slash from supabaseUrl', () async {
      Uri? captured;
      final client = SupabaseEntitlementsClient(
        supabaseUrl: '$url/',
        anonKey: anon,
        jwtSource: () => 'jwt-stub',
        httpClient: MockClient((req) async {
          captured = req.url;
          return http.Response('[]', 200);
        }),
      );

      await client.fetch(userId);

      expect(captured!.toString(), startsWith('$url/rest/'));
    });

    test('falls back to safe defaults when row fields are missing',
        () async {
      final body = jsonEncode([
        {
          'user_id': userId,
          'state': 'free',
          // renewal_date / grace_until omitted
          // counters omitted (default to 0)
          'counter_period_start': '2026-05-01T00:00:00+00:00',
        }
      ]);
      final client = _client(
        mock: MockClient((_) async => http.Response(body, 200)),
      );

      final ent = await client.fetch(userId);

      expect(ent!.state, EntitlementState.free);
      expect(ent.renewalDate, isNull);
      expect(ent.graceUntil, isNull);
      expect(ent.photoCreditsBalance, 0);
      expect(ent.monthlyTextCount, 0);
      expect(ent.monthlyVisionCount, 0);
    });

    test('unknown server state falls through to free per fromWire', () async {
      final body = jsonEncode([
        {
          'user_id': userId,
          'state': 'unknown_future_tier',
          'counter_period_start': '2026-05-01T00:00:00+00:00',
        }
      ]);
      final client = _client(
        mock: MockClient((_) async => http.Response(body, 200)),
      );

      final ent = await client.fetch(userId);
      expect(ent!.state, EntitlementState.free,
          reason: 'fromWire treats unknown values as free, never '
              'auto-upgrades to Pro.');
    });
  });

  group('FakeEntitlementsClient (test fake)', () {
    test('returns scripted row + records fetched userId + counts',
        () async {
      final fake = FakeEntitlementsClient();
      final pro = Entitlement(
        state: EntitlementState.proMonthly,
        userId: 'u1',
        counterPeriodStart: DateTime(2026, 5),
      );
      fake.scriptRow(pro);

      final got = await fake.fetch('u1');

      expect(got, pro);
      expect(fake.lastFetchedUserId, 'u1');
      expect(fake.fetchCount, 1);
    });

    test('throws scripted error then clears for the next call', () async {
      final fake = FakeEntitlementsClient();
      const err = EntitlementsClientException('forced');
      fake.scriptError(err);

      expect(() => fake.fetch('u1'), throwsA(same(err)));

      // Second call returns whatever scriptRow last set (null by default).
      expect(await fake.fetch('u1'), isNull);
      expect(fake.fetchCount, 2);
    });
  });
}

SupabaseEntitlementsClient _client({
  String Function()? jwtSource,
  http.Client? mock,
}) {
  return SupabaseEntitlementsClient(
    supabaseUrl: 'https://abcdef.supabase.co',
    anonKey: 'anon-key-stub',
    jwtSource: jwtSource ?? () => 'jwt-stub',
    httpClient: mock,
  );
}

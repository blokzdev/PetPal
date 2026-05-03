import 'dart:convert';

import 'package:http/http.dart' as http;

import 'entitlement.dart';

/// Phase 7 task H.1.c.2 — abstract entitlements fetch surface.
///
/// Production: [SupabaseEntitlementsClient] (REST against PostgREST).
/// Tests: a fake that returns scripted Entitlements / errors. The
/// abstraction lets the notifier's auth-aware refresh path stay
/// testable without `http.testing.MockClient` plumbing in every
/// notifier test.
abstract class EntitlementsClient {
  /// Fetch the entitlement row for [userId]. Returns `null` when
  /// the row does not exist yet (first sign-in before the
  /// play-billing-webhook or auth.users insert trigger has
  /// populated the row).
  ///
  /// Throws [EntitlementsClientException] on auth / network /
  /// parse failures.
  Future<Entitlement?> fetch(String userId);
}

/// Phase 7 task H.1.c.2 — REST client for the canonical
/// `entitlements` Postgres table on Supabase (DECISIONS rows 78 + 82).
///
/// Per row 78: signed-in users read their entitlement state from
/// Supabase as the source of truth. The local Drift cache is the
/// fallback when network / server is unavailable so transient
/// failures don't strand the user on the wrong tier.
///
/// Per row 82: the row schema is
///   `(user_id, state, renewal_date, grace_until,
///     photo_credits_balance, monthly_text_count,
///     monthly_vision_count, counter_period_start, ...)`
/// queried via PostgREST: `GET /rest/v1/entitlements?user_id=eq.<id>`.
///
/// Uses the same REST-direct + http.Client pattern as
/// [SupabaseSyncBackend] so tests drive every endpoint via
/// `http.testing.MockClient` without standing up real Supabase.
///
/// **JWT freshness.** [jwtSource] is read on every request so token
/// refresh inside `supabase_flutter` is picked up without
/// re-instantiating the client.
class SupabaseEntitlementsClient implements EntitlementsClient {
  SupabaseEntitlementsClient({
    required String supabaseUrl,
    required String anonKey,
    required String Function() jwtSource,
    http.Client? httpClient,
  })  : _url = _stripTrailingSlash(supabaseUrl),
        _anonKey = anonKey,
        _jwtSource = jwtSource,
        _http = httpClient ?? http.Client();

  static String _stripTrailingSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  final String _url;
  final String _anonKey;
  final String Function() _jwtSource;
  final http.Client _http;

  /// Fetch the entitlement row for [userId]. Returns:
  ///   - the parsed [Entitlement] when the row exists
  ///   - `null` when the row does not exist yet (e.g., first sign-in
  ///     before the play-billing-webhook or auth.users insert
  ///     trigger has populated the row). Caller treats this as
  ///     "free signed-in" with default counters.
  ///
  /// Throws [EntitlementsClientException] on 4xx / 5xx / network
  /// failure. The notifier's auth-aware build path catches this
  /// exception and falls back to the local Drift cache so transient
  /// backend failures don't drop the user to anonymous.
  @override
  Future<Entitlement?> fetch(String userId) async {
    final jwt = _jwtSource();
    if (jwt.isEmpty) {
      throw const EntitlementsClientException(
        'fetch requires a signed-in user — JWT not available.',
      );
    }

    final uri = Uri.parse(
      '$_url/rest/v1/entitlements'
      '?user_id=eq.$userId'
      '&select=user_id,state,renewal_date,grace_until,'
      'photo_credits_balance,monthly_text_count,monthly_vision_count,'
      'counter_period_start',
    );
    final res = await _http.get(uri, headers: {
      'apikey': _anonKey,
      'Authorization': 'Bearer $jwt',
      'Accept': 'application/json',
    });

    if (res.statusCode != 200) {
      throw EntitlementsClientException(
        'fetch failed (${res.statusCode}): ${res.body}',
      );
    }

    final list = jsonDecode(res.body) as List<dynamic>;
    if (list.isEmpty) return null;
    return _decode(list.first as Map<String, Object?>);
  }

  Entitlement _decode(Map<String, Object?> row) {
    final stateWire = row['state'] as String? ?? 'free';
    final state = EntitlementState.fromWire(stateWire);

    return Entitlement(
      state: state,
      userId: row['user_id'] as String?,
      renewalDate: _parseTs(row['renewal_date']),
      graceUntil: _parseTs(row['grace_until']),
      photoCreditsBalance: (row['photo_credits_balance'] as int?) ?? 0,
      monthlyTextCount: (row['monthly_text_count'] as int?) ?? 0,
      monthlyVisionCount: (row['monthly_vision_count'] as int?) ?? 0,
      counterPeriodStart: _parseTs(row['counter_period_start']) ??
          DateTime.now().toUtc(),
      fetchedAt: DateTime.now().toUtc(),
      // Care pack ownership is a local-only field today (Drift schema
      // v3 column `owned_care_pack_skill_ids_json`). The play-billing-
      // verify Edge Function will mirror it server-side in a later
      // commit; until then, server fetch leaves it empty and the
      // notifier merges the cached value back in.
      ownedCarePackSkillIds: const <String>{},
    );
  }

  static DateTime? _parseTs(Object? raw) {
    if (raw is! String) return null;
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toUtc();
    } on FormatException {
      return null;
    }
  }
}

class EntitlementsClientException implements Exception {
  const EntitlementsClientException(this.message);
  final String message;
  @override
  String toString() => 'EntitlementsClientException: $message';
}

/// Test fake — returns scripted [Entitlement] rows or throws
/// scripted errors. Counts fetches for invariant assertions.
class FakeEntitlementsClient implements EntitlementsClient {
  FakeEntitlementsClient();

  Entitlement? _scriptedRow;
  Object? _scriptedError;
  String? _lastFetchedUserId;
  int _fetchCount = 0;

  /// Pre-arrange the next [fetch] response.
  void scriptRow(Entitlement? row) {
    _scriptedRow = row;
    _scriptedError = null;
  }

  /// Pre-arrange the next [fetch] to throw [error].
  void scriptError(Object error) {
    _scriptedError = error;
  }

  String? get lastFetchedUserId => _lastFetchedUserId;
  int get fetchCount => _fetchCount;

  @override
  Future<Entitlement?> fetch(String userId) async {
    _fetchCount++;
    _lastFetchedUserId = userId;
    final err = _scriptedError;
    if (err != null) {
      _scriptedError = null;
      throw err;
    }
    return _scriptedRow;
  }
}

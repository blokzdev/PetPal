import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_session_notifier.dart';
import '../sync/supabase_runtime_config.dart';

/// Phase 7 task H.1.d — abstract account-deletion surface.
///
/// Production: [SupabaseAccountDeletionClient] — POSTs to the
/// `/functions/v1/account-delete` Edge Function. Tests: scripted
/// fake. Same testability seam pattern as
/// [SupabaseEntitlementsClient] / [SupabaseSyncBackend] / etc.
///
/// **Server-side cascade (per DECISIONS row 77 Option e):** the
/// Edge Function inserts a `deleted_accounts_log` audit row with
/// `retention_window_ends_at = now() + 30 days` and signs the
/// user out of the active session. The actual hard-purge runs on
/// the daily cron at the end of the retention window — that
/// implementation lands alongside the cron commit. Until then,
/// the audit log row is the contract: it proves to the user (via
/// the returned timestamp) that their data is scheduled for
/// deletion, and proves to a regulator (via the
/// `deleted_accounts_log` table) that PetPal honoured the request.
abstract class AccountDeletionClient {
  /// Initiate account deletion for the signed-in user.
  ///
  /// Returns the `retention_window_ends_at` timestamp — the date
  /// after which all of the user's data will be hard-purged from
  /// PetPal's servers. The UI surfaces this so the user knows the
  /// undo window.
  ///
  /// Throws [AccountDeletionException] on auth / network /
  /// server-error. The UI maps this onto VOICE.md-compatible
  /// error copy.
  Future<DateTime> requestDeletion();
}

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);
  final String message;
  @override
  String toString() => 'AccountDeletionException: $message';
}

/// Production [AccountDeletionClient]. POSTs to the
/// `account-delete` Edge Function with the user's JWT in the
/// Authorization header. Anonymous users cannot delete an account
/// (there's nothing to delete) — the Settings tile only renders
/// for signed-in users.
class SupabaseAccountDeletionClient implements AccountDeletionClient {
  SupabaseAccountDeletionClient({
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

  @override
  Future<DateTime> requestDeletion() async {
    final jwt = _jwtSource();
    if (jwt.isEmpty) {
      throw const AccountDeletionException(
        'requestDeletion requires a signed-in user — JWT not available.',
      );
    }

    final uri = Uri.parse('$_url/functions/v1/account-delete');
    final res = await _http.post(
      uri,
      headers: {
        'apikey': _anonKey,
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
      },
      // Body intentionally empty — user_id is read from the JWT
      // server-side. Nothing else to specify.
      body: '{}',
    );

    if (res.statusCode != 200) {
      throw AccountDeletionException(
        'account-delete failed (${res.statusCode}): ${res.body}',
      );
    }

    try {
      final body = jsonDecode(res.body) as Map<String, Object?>;
      final iso = body['retention_window_ends_at'] as String?;
      if (iso == null || iso.isEmpty) {
        throw const AccountDeletionException(
          'account-delete response missing retention_window_ends_at',
        );
      }
      return DateTime.parse(iso).toUtc();
    } on FormatException catch (e) {
      throw AccountDeletionException(
        'account-delete response malformed: $e',
      );
    }
  }
}

/// Test fake. Scripted retention-window timestamp or scripted
/// error; counts requestDeletion calls.
class FakeAccountDeletionClient implements AccountDeletionClient {
  FakeAccountDeletionClient({DateTime? retentionEnd})
      : _retentionEnd = retentionEnd ??
            DateTime.now().add(const Duration(days: 30));

  DateTime _retentionEnd;
  Object? _scriptedError;
  int _callCount = 0;

  void scriptRetentionEnd(DateTime t) => _retentionEnd = t;
  void scriptError(Object error) => _scriptedError = error;

  int get callCount => _callCount;

  @override
  Future<DateTime> requestDeletion() async {
    _callCount++;
    final err = _scriptedError;
    if (err != null) {
      _scriptedError = null;
      throw err;
    }
    return _retentionEnd;
  }
}

/// Phase 7 task H.1.d — client provider.
///
/// Returns null when Supabase isn't configured (dev `flutter run`
/// without --dart-define). The Settings tile that opens the delete
/// flow already guards on `authSessionProvider`, so this null
/// branch is the defensive fallback for the dev case.
final accountDeletionClientProvider =
    Provider<AccountDeletionClient?>((ref) {
  final config = ref.watch(supabaseRuntimeConfigProvider);
  if (config == null) return null;
  return SupabaseAccountDeletionClient(
    supabaseUrl: config.url,
    anonKey: config.anonKey,
    jwtSource: () =>
        ref.read(authSessionProvider).value?.accessToken ?? '',
  );
});

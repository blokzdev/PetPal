import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Phase 7 task F.1 — BYOK key validation per DECISIONS row 74.
///
/// Two-stage flow:
///
///   1. **Format check** — regex `sk-ant-[A-Za-z0-9_-]{40,}` (per
///      row 74). Cheap; rejects typos before any network call.
///   2. **Live ping** — `GET https://api.anthropic.com/v1/models`
///      with `x-api-key: <key>` + `anthropic-version: 2023-06-01`.
///      The endpoint returns the user's accessible models. 200 ⇒
///      Accepted. 401 / 403 ⇒ RejectedAuth. Other 4xx / 5xx ⇒
///      NetworkError (treated as soft-warning per row 74 — store
///      anyway; user finds out at first chat if the key is bad).
///
/// **Why both checks** (locked by row 74): format-only would let
/// confident-typos through ("sk-ant-typo123…" → confusing first-
/// chat failure with no audit trail). Ping-only accepts garbage the
/// regex catches in microseconds. Belt-and-braces; one-time ~200ms
/// at toggle activation.
///
/// **Why `/v1/models`** (locked by row 74): cheapest authenticated
/// Anthropic endpoint that confirms the key is valid + has model
/// access. Not `/v1/messages` (would charge a token); not
/// `/v1/messages/count_tokens` (more about request validation).
sealed class ByokValidationResult {
  const ByokValidationResult();
}

final class ByokAccepted extends ByokValidationResult {
  const ByokAccepted();
}

final class ByokRejectedFormat extends ByokValidationResult {
  const ByokRejectedFormat();
}

final class ByokRejectedAuth extends ByokValidationResult {
  const ByokRejectedAuth();
}

/// Network failure (timeout, DNS, transient Anthropic outage). Per
/// row 74 — soft warning, store anyway. Caller surfaces a "couldn't
/// verify the key, saving anyway" snackbar.
final class ByokNetworkError extends ByokValidationResult {
  const ByokNetworkError(this.message);
  final String message;
}

/// Anthropic API key format regex per DECISIONS row 74.
final RegExp byokKeyPattern = RegExp(r'^sk-ant-[A-Za-z0-9_-]{40,}$');

class ByokValidator {
  ByokValidator({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  static const _modelsEndpoint = 'https://api.anthropic.com/v1/models';
  static const _apiVersion = '2023-06-01';
  static const _timeout = Duration(seconds: 10);

  final http.Client _http;

  /// Validate [apiKey]. Always trims input first.
  Future<ByokValidationResult> validate(String apiKey) async {
    final trimmed = apiKey.trim();
    if (!byokKeyPattern.hasMatch(trimmed)) {
      return const ByokRejectedFormat();
    }
    try {
      final response = await _http.get(
        Uri.parse(_modelsEndpoint),
        headers: {
          'x-api-key': trimmed,
          'anthropic-version': _apiVersion,
        },
      ).timeout(_timeout);
      if (response.statusCode == 200) {
        return const ByokAccepted();
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return const ByokRejectedAuth();
      }
      return ByokNetworkError(
        'Anthropic returned HTTP ${response.statusCode}.',
      );
    } catch (e) {
      return ByokNetworkError('$e');
    }
  }

  void close() => _http.close();
}

/// Phase 7 task F.1 — singleton validator. Tests override with a
/// fake that injects a scripted [http.Client].
final byokValidatorProvider = Provider<ByokValidator>((ref) {
  final v = ByokValidator();
  ref.onDispose(v.close);
  return v;
});

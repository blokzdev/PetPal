/// Phase 7 task H.2 — `sk-ant-*` redaction layer.
///
/// Risk-mitigation lock from DECISIONS Stage 1 review: every
/// analytics payload + crash report MUST scrub anything matching
/// the Anthropic API key shape before it leaves the device, so a
/// BYOK user's key can never leak through telemetry.
///
/// **Pattern.** Anthropic's keys ship in the `sk-ant-…` shape with
/// a trailing run of base64url characters. Real keys are 40+
/// characters (the BYOK validator at `lib/app/byok/byok_validator.dart`
/// pins this); the redaction filter is more permissive (20+) so a
/// stray prefix or partial match still gets caught — false-positive-
/// tolerant per the same defense-in-depth thesis as the red-flag
/// screener.
///
/// Used by:
///   - [CrashAnalytics] before any error report goes out
///   - Any future analytics-event payload before send
///   - Test harness assertions for "no key leaked" invariants
///
/// **Pure function.** No I/O, no provider wiring; safe to call from
/// any layer.
String redactSkAnt(String input) {
  if (input.isEmpty) return input;
  return input.replaceAll(skAntPattern, '[REDACTED-API-KEY]');
}

/// Same redaction applied to a structured map. Recursively walks
/// keys + values; redacts any string value that matches the
/// pattern. Used when analytics SDKs accept `Map<String, Object?>`
/// payload shapes.
Map<String, Object?> redactSkAntInMap(Map<String, Object?> input) {
  final out = <String, Object?>{};
  input.forEach((k, v) {
    out[k] = _redactValue(v);
  });
  return out;
}

Object? _redactValue(Object? v) {
  if (v is String) return redactSkAnt(v);
  if (v is Map<String, Object?>) return redactSkAntInMap(v);
  if (v is List) return v.map(_redactValue).toList(growable: false);
  return v;
}

/// Locked redaction pattern. Public for tests + for any layer that
/// wants to assert directly against the regex (e.g., a unit test
/// scraping captured analytics-payload bytes for leaks).
///
/// 20-character minimum trail is intentional: real keys are 40+,
/// but partial prefixes (debug logs that truncated mid-key,
/// concatenated env-var dumps, etc.) should still be caught.
final RegExp skAntPattern = RegExp(r'sk-ant-[A-Za-z0-9_-]{20,}');

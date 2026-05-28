import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/platform/analytics/sk_ant_redaction.dart';

/// Phase 7 task H.2 — sk-ant- redaction layer tests.
///
/// Load-bearing risk-mitigation: every analytics payload + crash
/// report MUST scrub anything matching the Anthropic key shape
/// before it leaves the device. This test pins the contract.
void main() {
  group('redactSkAnt — single-string', () {
    test('plain text passes through unchanged', () {
      const input = 'NullPointerException at chat_screen.dart:42';
      expect(redactSkAnt(input), input);
    });

    test('empty string returns empty string', () {
      expect(redactSkAnt(''), '');
    });

    test('redacts a 40-char real-shape Anthropic key', () {
      const key = 'sk-ant-abcdefghijklmnopqrstuvwxyz0123456789';
      const input = 'Authorization: $key';
      final got = redactSkAnt(input);
      expect(got, isNot(contains('abcdef')));
      expect(got, contains('[REDACTED-API-KEY]'));
    });

    test('redacts a partial 20-char prefix (defense-in-depth)', () {
      const partial = 'sk-ant-abcdefghijklmnopqrst';
      const input = 'Truncated log: $partial...';
      final got = redactSkAnt(input);
      expect(got, isNot(contains('abcdef')));
      expect(got, contains('[REDACTED-API-KEY]'));
    });

    test('does NOT redact a < 20-char trail (false-negative gap is '
        'intentional — too short to be a real key fragment)', () {
      const tooShort = 'sk-ant-abcdef';
      expect(redactSkAnt(tooShort), tooShort);
    });

    test('redacts every match in the string (no early-return)', () {
      const input = 'first sk-ant-abcdefghijklmnopqrstuvwxyz0123 and '
          'second sk-ant-zyxwvutsrqponmlkjihgfedcba9876';
      final got = redactSkAnt(input);
      // Both matches replaced.
      expect(got, isNot(contains('abcdef')));
      expect(got, isNot(contains('zyxwvu')));
      expect(
        '[REDACTED-API-KEY]'.allMatches(got).length,
        2,
      );
    });

    test('handles base64url-style chars (_, -) in the trail', () {
      const key = 'sk-ant-abc-def_ghijklmnopqrstuv_-XYZ789';
      const input = 'Bearer $key';
      final got = redactSkAnt(input);
      expect(got, isNot(contains('abc-def')));
      expect(got, contains('[REDACTED-API-KEY]'));
    });

    test('does NOT match unrelated sk-* prefixes (e.g. OpenAI)', () {
      const openai = 'sk-aaaabbbbccccddddeeeeffff';
      // No "sk-ant-" prefix → no match.
      expect(redactSkAnt(openai), openai);
    });
  });

  group('redactSkAntInMap — structured payload', () {
    test('redacts string values nested in maps', () {
      final input = <String, Object?>{
        'event': 'auth_error',
        'detail': 'Bearer sk-ant-abcdefghijklmnopqrstuvwxyz0123',
        'count': 42,
      };
      final out = redactSkAntInMap(input);
      expect(out['event'], 'auth_error');
      expect(out['detail'], isNot(contains('abcdef')));
      expect((out['detail'] as String), contains('[REDACTED-API-KEY]'));
      expect(out['count'], 42);
    });

    test('recurses through nested maps', () {
      final input = <String, Object?>{
        'context': {
          'request': {
            'headers': 'Authorization: Bearer sk-ant-aaaaaaaaaaaaaaaaaaaaaa',
          },
        },
      };
      final out = redactSkAntInMap(input);
      final headers = (((out['context'] as Map)['request']
          as Map)['headers']) as String;
      expect(headers, contains('[REDACTED-API-KEY]'));
      expect(headers, isNot(contains('aaaaaaaaaa')));
    });

    test('walks list values', () {
      final input = <String, Object?>{
        'breadcrumbs': [
          'first',
          'sk-ant-abcdefghijklmnopqrstuvwxyz1234',
          'last',
        ],
      };
      final out = redactSkAntInMap(input);
      final list = out['breadcrumbs'] as List;
      expect(list[0], 'first');
      expect(list[1], contains('[REDACTED-API-KEY]'));
      expect(list[2], 'last');
    });

    test('preserves non-string scalars (int/bool/null)', () {
      final input = <String, Object?>{
        'count': 5,
        'active': true,
        'reason': null,
      };
      final out = redactSkAntInMap(input);
      expect(out, input);
    });
  });

  group('skAntPattern — load-bearing regex', () {
    test('pattern is exactly sk-ant-[A-Za-z0-9_-]{20,}', () {
      // Any change to the pattern is a deliberate decision that
      // must update DECISIONS — pin it here so a casual edit gets
      // caught.
      expect(skAntPattern.pattern, r'sk-ant-[A-Za-z0-9_-]{20,}');
    });
  });
}

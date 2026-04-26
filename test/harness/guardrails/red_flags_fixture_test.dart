import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/guardrails/red_flags.dart';
import 'package:petpal/harness/guardrails/red_flag_screener.dart';

import 'red_flags_fixture.dart';

/// Parameterised coverage of the fixture in `red_flags_fixture.dart`.
/// Walks every (category, phrase) pair so a regression on any one
/// category surfaces with the exact phrase that broke. Built up
/// incrementally — only categories present in the fixture are
/// asserted; missing categories are treated as "not yet rounded out"
/// and skipped (the per-category coverage-floor test below catches
/// them once they land).
void main() {
  final screener = RedFlagScreener();

  group('positives — every fixture phrase must flag the named category', () {
    positives.forEach((categoryId, phrases) {
      for (final phrase in phrases) {
        test('"$phrase" → $categoryId', () {
          final match = screener.screen(phrase);
          expect(match, isNotNull, reason: phrase);
          expect(match!.category.id, categoryId, reason: phrase);
        });
      }
    });
  });

  group('negatives — fixture phrase must NOT flag the named category', () {
    negatives.forEach((categoryId, phrases) {
      for (final phrase in phrases) {
        test('"$phrase" must not flag $categoryId', () {
          final match = screener.screen(phrase);
          // Either no flag at all, or a flag for some other category
          // (we only assert this category isn't matched). The
          // false-positive-tolerant principle (DECISIONS row 29)
          // accepts cross-category overflow as long as targeted
          // adversarial cases stay clean.
          if (match != null) {
            expect(
              match.category.id,
              isNot(categoryId),
              reason: 'expected NOT to flag $categoryId for "$phrase"',
            );
          }
        });
      }
    });
  });

  group('coverage floor — every category in the fixture meets CLAUDE.md §10',
      () {
    for (final entry in positives.entries) {
      test('${entry.key} has ≥30 positive phrasings', () {
        expect(entry.value.length, greaterThanOrEqualTo(30));
      });
    }
    for (final entry in negatives.entries) {
      test('${entry.key} has ≥20 negative phrasings', () {
        expect(entry.value.length, greaterThanOrEqualTo(20));
      });
    }
  });

  test('every category covered by the fixture is one of the canonical 11',
      () {
    final canonical = redFlagPatterns.map((p) => p.id).toSet();
    for (final id in {...positives.keys, ...negatives.keys}) {
      expect(canonical, contains(id), reason: id);
    }
  });
}

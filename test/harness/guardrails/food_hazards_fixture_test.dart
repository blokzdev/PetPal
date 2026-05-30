import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/guardrails/food_hazard_screener.dart';

import 'food_hazards_fixture.dart';

/// Phase 8 task 8.3 — parameterised walk of the food-hazard fixture.
/// Asserts:
///   1. Every positive phrase in `foodHazardPositives` flags the
///      expected category (and only that category in iteration
///      order).
///   2. Every negative phrase in `foodHazardNegatives` does NOT flag
///      any category — protects the word-boundary contract that the
///      screener_test exercises in single-case form.
///   3. Floor enforcement: every category in the asset has ≥10
///      positive phrasings (DECISIONS row 100).
///   4. Asset round-trip: the bundled `assets/hazards/food_toxins.yaml`
///      parses through `parseFoodToxinYaml` cleanly and the
///      fixture's category ids match the asset's category ids
///      (no fixtures for missing categories; no categories without
///      fixtures).

const _kAssetPath = 'assets/hazards/food_toxins.yaml';

/// Read the asset directly from disk (test runs from the package
/// root; bypasses Flutter's rootBundle so this test doesn't need
/// `TestWidgetsFlutterBinding.ensureInitialized`).
String _readAsset() => File(_kAssetPath).readAsStringSync();

void main() {
  group('Phase 8 task 8.3 — food hazards fixture coverage', () {
    final assetCategories = parseFoodToxinYaml(_readAsset());
    final screener = FoodHazardScreener(categories: assetCategories);

    test('every asset category has ≥10 fixture positives (DECISIONS '
        'row 100 floor)', () {
      for (final category in assetCategories) {
        final positives = foodHazardPositives[category.id];
        expect(positives, isNotNull,
            reason: 'category `${category.id}` has no fixture entry');
        expect(positives!.length, greaterThanOrEqualTo(10),
            reason: 'category `${category.id}` has only '
                '${positives.length} positives (floor: 10)');
      }
    });

    test('fixture has no orphan category ids (every fixture key must '
        'exist in the asset)', () {
      final assetIds = {for (final c in assetCategories) c.id};
      for (final fixtureId in foodHazardPositives.keys) {
        expect(assetIds, contains(fixtureId),
            reason: 'fixture references unknown category `$fixtureId`');
      }
    });

    group('positives flag the expected category', () {
      for (final entry in foodHazardPositives.entries) {
        final categoryId = entry.key;
        final positives = entry.value;
        final categoryRow =
            assetCategories.firstWhere((c) => c.id == categoryId);
        // Use a species this category applies to (first in its list,
        // or null for empty-species → fires for all).
        final species = categoryRow.species.isEmpty
            ? null
            : categoryRow.species.first;

        for (final phrase in positives) {
          test('[$categoryId] flags: $phrase', () {
            final match = screener.screen(
              identifiedItems: [phrase],
              petSpecies: species,
            );
            expect(match, isNotNull,
                reason: 'positive `$phrase` did not flag any category');
            expect(match!.category.id, categoryId,
                reason: 'positive `$phrase` flagged '
                    '`${match.category.id}` instead of `$categoryId`');
          });
        }
      }
    });

    group('negatives do NOT flag any category (word-boundary control)',
        () {
      // Use null species so the negative would fire for ALL categories
      // if the word boundary failed — strictest test of the
      // false-positive control.
      for (final phrase in foodHazardNegatives) {
        test('does not flag: $phrase', () {
          final match = screener.screen(
            identifiedItems: [phrase],
            // Explicit null to test strictest false-positive control:
            // a category with empty `species` would otherwise fire
            // for any pet, but the negative phrasings must not flag
            // for any species — including unknown.
            // ignore: avoid_redundant_argument_values
            petSpecies: null,
          );
          expect(match, isNull,
              reason: 'negative `$phrase` unexpectedly flagged '
                  '`${match?.category.id}` via `${match?.matchedPhrase}`');
        });
      }
    });
  });
}

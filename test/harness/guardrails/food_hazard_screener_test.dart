import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/guardrails/food_hazard_screener.dart';

/// Phase 8 task 8.3 — focused unit tests for the food-hazard screener.
/// Pairs with the fixture-driven walk in `food_hazards_fixture_test.dart`
/// (parameterised per-category coverage) — the cases here cover the
/// source priority, species filtering, word-boundary behavior, and
/// null-safety contract the fixture walk doesn't exercise.

/// Small in-memory category list — covers two species, two categories.
/// Keeps unit tests independent of the asset YAML (the YAML round-trip
/// is asserted in `food_hazards_fixture_test.dart`).
List<FoodHazardCategory> _testCategories() => [
      FoodHazardCategory(
        id: 'chocolate',
        species: const ['dog', 'cat'],
        aiSummary: 'Chocolate (theobromine)',
        phrases: const ['chocolate', 'cocoa'],
      ),
      FoodHazardCategory(
        id: 'grapes',
        species: const ['dog'],
        aiSummary: 'Grapes (nephrotoxic to dogs)',
        phrases: const ['grape', 'grapes', 'raisin'],
      ),
      FoodHazardCategory(
        id: 'cannabis',
        species: const ['dog', 'cat'],
        aiSummary: 'Cannabis (THC)',
        phrases: const ['pot brownie', 'cannabis'],
      ),
    ];

void main() {
  group('Phase 8 task 8.3 — FoodHazardScreener', () {
    test('empty inputs return null (no match)', () {
      final screener = FoodHazardScreener(categories: _testCategories());
      expect(
        screener.screen(identifiedItems: const []),
        isNull,
      );
      expect(
        screener.screen(
          identifiedItems: const [],
          freeformCaption: '',
        ),
        isNull,
      );
      expect(
        screener.screen(
          identifiedItems: const [],
          freeformCaption: '   ',
        ),
        isNull,
      );
    });

    test('single-item identifiedItems hit returns identifiedItems source',
        () {
      final screener = FoodHazardScreener(categories: _testCategories());
      final match = screener.screen(
        identifiedItems: const ['chocolate'],
        petSpecies: 'dog',
      );
      expect(match, isNotNull);
      expect(match!.category.id, 'chocolate');
      expect(match.matchedPhrase, 'chocolate');
      expect(match.source, FoodHazardSource.identifiedItems);
    });

    test('multi-item identifiedItems hit — flagged item among benign items',
        () {
      final screener = FoodHazardScreener(categories: _testCategories());
      final match = screener.screen(
        identifiedItems: const ['chicken', 'rice', 'chocolate', 'carrot'],
        petSpecies: 'dog',
      );
      expect(match, isNotNull);
      expect(match!.category.id, 'chocolate');
    });

    test('clean identified items + flagged caption returns freeformCaption '
        'source (secondary signal)', () {
      final screener = FoodHazardScreener(categories: _testCategories());
      final match = screener.screen(
        identifiedItems: const ['chicken'],
        freeformCaption: 'I think there might be onion in this, not sure',
        petSpecies: 'dog',
      );
      // 'onion' is not in our test categories, so this clean caption
      // shouldn't flag. Re-running with a caption that mentions
      // 'chocolate' — that should flag via freeformCaption.
      expect(match, isNull);

      final match2 = screener.screen(
        identifiedItems: const ['chicken'],
        freeformCaption: 'A small piece of chocolate on the floor',
        petSpecies: 'dog',
      );
      expect(match2, isNotNull);
      expect(match2!.category.id, 'chocolate');
      expect(match2.source, FoodHazardSource.freeformCaption);
    });

    test('both hit → identifiedItems wins (parallel to RedFlagSource '
        'chat-over-vision posture)', () {
      final screener = FoodHazardScreener(categories: _testCategories());
      final match = screener.screen(
        // chocolate in items; cannabis in caption. items wins.
        identifiedItems: const ['chocolate'],
        freeformCaption: 'and there was a pot brownie too',
        petSpecies: 'dog',
      );
      expect(match, isNotNull);
      expect(match!.category.id, 'chocolate');
      expect(match.source, FoodHazardSource.identifiedItems);
    });

    test('species filter: grapes flags dog, NOT cat', () {
      final screener = FoodHazardScreener(categories: _testCategories());
      final dogMatch = screener.screen(
        identifiedItems: const ['grape'],
        petSpecies: 'dog',
      );
      expect(dogMatch, isNotNull);
      expect(dogMatch!.category.id, 'grapes');

      final catMatch = screener.screen(
        identifiedItems: const ['grape'],
        petSpecies: 'cat',
      );
      expect(catMatch, isNull,
          reason: 'grapes is dog-only — cat must not flag');
    });

    test('null species fires for ALL categories (over-warn posture per '
        'DECISIONS row 29 + 100)', () {
      final screener = FoodHazardScreener(categories: _testCategories());
      // grape is dog-only, but null species is unknown — fire anyway.
      final match = screener.screen(
        identifiedItems: const ['grape'],
        // ignore: avoid_redundant_argument_values
        petSpecies: null,
      );
      expect(match, isNotNull);
      expect(match!.category.id, 'grapes');
    });

    test('word-boundary: chocolatey does NOT match chocolate', () {
      final screener = FoodHazardScreener(categories: _testCategories());
      final match = screener.screen(
        identifiedItems: const ['chocolatey aroma'],
        petSpecies: 'dog',
      );
      expect(match, isNull,
          reason: 'word-bounded regex must not flag chocolatey');
    });

    test('word-boundary: grapefruit does NOT match grape', () {
      final screener = FoodHazardScreener(categories: _testCategories());
      final match = screener.screen(
        identifiedItems: const ['grapefruit'],
        petSpecies: 'dog',
      );
      expect(match, isNull,
          reason: 'word-bounded regex must not flag grapefruit');
    });

    test('case-insensitivity: CHOCOLATE matches chocolate', () {
      final screener = FoodHazardScreener(categories: _testCategories());
      final match = screener.screen(
        identifiedItems: const ['CHOCOLATE'],
        petSpecies: 'dog',
      );
      expect(match, isNotNull);
      expect(match!.category.id, 'chocolate');
    });

    test('multi-word phrase: pot brownie flags cannabis', () {
      final screener = FoodHazardScreener(categories: _testCategories());
      final match = screener.screen(
        identifiedItems: const ['pot brownie'],
        petSpecies: 'dog',
      );
      expect(match, isNotNull);
      expect(match!.category.id, 'cannabis');
      expect(match.matchedPhrase, 'pot brownie');
    });

    test('matchedPhrase determinism: returns the first matching phrase '
        'in YAML order (audit determinism)', () {
      final screener = FoodHazardScreener(categories: _testCategories());
      // grapes category has phrases [grape, grapes, raisin].
      // Input matches grapes (plural) at index 1.
      final match = screener.screen(
        identifiedItems: const ['grapes'],
        petSpecies: 'dog',
      );
      expect(match, isNotNull);
      // Note: 'grape' (singular) also has \bgrape\b which DOES match
      // 'grapes' (word boundary between e and s? No — \b after grape
      // requires non-word char; s is word char, so \bgrape\b does NOT
      // match 'grapes'). First matching phrase is 'grapes'.
      expect(match!.matchedPhrase, 'grapes');
    });

    test('first-match-wins across categories: iteration order decides '
        'when two categories would both fire', () {
      // Build a screener where alliums comes before chocolate in the
      // category list; a hybrid input ('garlic chocolate') should
      // flag alliums first.
      final categories = [
        FoodHazardCategory(
          id: 'alliums',
          species: const ['dog', 'cat'],
          aiSummary: 'Allium',
          phrases: const ['garlic'],
        ),
        FoodHazardCategory(
          id: 'chocolate',
          species: const ['dog', 'cat'],
          aiSummary: 'Chocolate',
          phrases: const ['chocolate'],
        ),
      ];
      final screener = FoodHazardScreener(categories: categories);
      final match = screener.screen(
        identifiedItems: const ['garlic', 'chocolate'],
        petSpecies: 'dog',
      );
      expect(match, isNotNull);
      expect(match!.category.id, 'alliums',
          reason: 'iteration order wins on a multi-category hit');
    });

    test('InMemoryFoodHazardCategorySource round-trips the typed list',
        () async {
      final cats = _testCategories();
      final source = InMemoryFoodHazardCategorySource(cats);
      final loaded = await source.load();
      expect(loaded, same(cats));
    });

    test('parseFoodToxinYaml parses a well-formed minimal asset', () {
      const yaml = '''
categories:
  - id: chocolate
    species: [dog, cat]
    ai_summary: "Chocolate"
    phrases:
      - chocolate
      - cocoa
''';
      final cats = parseFoodToxinYaml(yaml);
      expect(cats, hasLength(1));
      expect(cats.first.id, 'chocolate');
      expect(cats.first.species, ['dog', 'cat']);
      expect(cats.first.aiSummary, 'Chocolate');
      expect(cats.first.phrases, ['chocolate', 'cocoa']);
    });

    test('parseFoodToxinYaml drift-tolerates unknown extra keys', () {
      const yaml = '''
categories:
  - id: chocolate
    species: [dog]
    ai_summary: "Chocolate"
    phrases: [chocolate]
    future_key: "ignored without throwing"
extra_root_key: "also ignored"
''';
      final cats = parseFoodToxinYaml(yaml);
      expect(cats, hasLength(1));
    });

    test('parseFoodToxinYaml rejects malformed asset shapes', () {
      // Missing required `phrases` list.
      const missingPhrases = '''
categories:
  - id: chocolate
    species: [dog]
    ai_summary: "Chocolate"
''';
      expect(
        () => parseFoodToxinYaml(missingPhrases),
        throwsA(isA<FormatException>()),
      );

      // Wrong root type.
      const rootList = '- foo\n- bar\n';
      expect(
        () => parseFoodToxinYaml(rootList),
        throwsA(isA<FormatException>()),
      );

      // Empty id.
      const emptyId = '''
categories:
  - id: ""
    species: [dog]
    ai_summary: "x"
    phrases: [x]
''';
      expect(
        () => parseFoodToxinYaml(emptyId),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

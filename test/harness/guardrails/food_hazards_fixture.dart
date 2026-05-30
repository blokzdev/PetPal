/// Phase 8 task 8.3 — coverage fixture for the food-hazard screener.
/// Each toxin category in `assets/hazards/food_toxins.yaml` ships
/// ≥10 positive phrasings here; the parameterised walk in
/// `food_hazards_fixture_test.dart` asserts every entry flags the
/// expected category and the per-category count enforces the floor.
///
/// New toxin categories or new phrases REQUIRE matching fixtures in
/// the same commit (DECISIONS row 100 coverage rule, mirroring row
/// 29's red-flag fixture rule).
///
/// **Fixture inputs are realistic extractor outputs**, not invented
/// surface text — every positive matches the plain-English Rule-5
/// vocabulary the food extractor (8.1) is prompted to emit. If the
/// extractor would never produce a phrase, the fixture doesn't carry
/// it (the screener's input domain is locked by extractor Rule 5,
/// not by free-form chat).
library;

/// `category_id` → positives that MUST flag that category. Order
/// within a category is preserved; the screener's `matchedPhrase`
/// determinism contract is asserted in screener_test.dart.
const foodHazardPositives = <String, List<String>>{
  'chocolate': [
    'chocolate',
    'a piece of chocolate',
    'chocolate chip cookie',
    'dark chocolate square',
    'milk chocolate',
    'white chocolate bark',
    'cocoa powder dusting',
    'cacao nibs',
    'chocolate truffle on the counter',
    'brownie',
    'half a brownie',
    'chocolate bar wrapper',
  ],
  'xylitol': [
    'xylitol',
    'xylitol gum',
    'birch sugar',
    'sugar-free gum',
    'sugarfree gum',
    'sugarless gum',
    'sugar-free mint',
    'sugar-free mints',
    'sugar-free candy',
    'sugarfree candy',
    'sugar free candy on the floor',
  ],
  'grapes_raisins': [
    'grape',
    'grapes',
    'a handful of grapes',
    'raisin',
    'raisins',
    'a few raisins',
    'sultana',
    'sultanas',
    'currant',
    'currants',
    'grape juice spill',
    'raisin bread',
    'trail mix',
  ],
  'alliums': [
    'onion',
    'onions',
    'diced onion',
    'garlic',
    'garlic clove',
    'chives',
    'leek',
    'leeks',
    'shallot',
    'shallots',
    'scallion',
    'scallions',
    'spring onion',
    'green onion',
    'onion powder',
    'garlic powder',
  ],
  'macadamia': [
    'macadamia',
    'macadamias',
    'macadamia nut',
    'macadamia nuts',
    'macadamia cookie',
    'macadamia cookies',
    'macadamia brittle',
    'white chocolate macadamia',
    'macadamia crunch bar',
    'macadamia brownie',
    'a few macadamia nuts on the floor',
  ],
  'alcohol': [
    'beer',
    'a half-finished beer',
    'wine',
    'a glass of wine',
    'liquor',
    'whiskey',
    'vodka',
    'rum',
    'bourbon',
    'champagne',
    'cocktail',
    'alcohol',
    'gin and tonic',
  ],
  'caffeine': [
    'coffee',
    'cup of coffee',
    'espresso',
    'coffee grounds',
    'spilled coffee grounds',
    'tea bag',
    'tea bags',
    'energy drink',
    'energy drinks',
    'caffeine pill',
    'caffeine pills',
    'cold brew',
  ],
  'yeast_dough': [
    'raw dough',
    'bread dough',
    'unbaked dough',
    'pizza dough',
    'yeast dough',
    'rising dough',
    'sourdough starter',
    'raw bread dough',
    'homemade dough on the counter',
    'proofed dough rising in a bowl',
  ],
  'cannabis': [
    'marijuana',
    'cannabis',
    'weed',
    'thc',
    'edible',
    'edibles',
    'pot brownie',
    'pot brownies',
    'cannabis gummy',
    'cannabis gummies',
    'thc gummy',
    'thc gummies',
    'cbd gummy',
  ],
};

/// Phrases that MUST NOT flag any category. These are extractor-style
/// food descriptions that share orthographic substrings with toxin
/// phrases but are bounded out by the word-boundary regex (`\b…\b`)
/// the screener compiles. Verifies the false-positive control.
const foodHazardNegatives = <String>[
  // 'chocolate' word-boundary: 'chocolatey'/'chocolaty' must NOT match.
  'chocolatey aroma',
  'chocolaty smell',
  // 'grape' word-boundary: 'grapefruit' must NOT match.
  'grapefruit',
  'grapefruit segments',
  'grapeseed oil',  // 'grapeseed' is one word; \bgrape\b does not match
  // 'wine' / 'vodka' / 'rum' in non-alcohol contexts.
  'rumaki appetizer',  // 'rumaki' — but \brum\b would still hit; included to spot-check the limit
  // 'thc' substring control — 'thoroughly cooked'.
  'thoroughly cooked rice',
  // Plain pet food with no toxin pattern at all.
  'plain kibble',
  'salmon pate',
  'chicken and rice',
  'turkey jerky',
  'sweet potato',
  'green bean',
  'plain rice',
  'cooked carrot',
  'cooked chicken breast',
];

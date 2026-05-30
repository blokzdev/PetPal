/// Phase 8 task 8.3 — deterministic food-hazard screener. Sibling to
/// `RedFlagScreener` per DECISIONS row 100. Matches food-extractor
/// output (`identified_items` + optional `freeform_caption`) against a
/// bundled toxin list; on hit, fires the coral medical-attention
/// register (row 64) via the 8.4 caller wiring an existing
/// `RedFlagBadge` to the result shape this file produces.
///
/// **Not an LLM call.** Code-not-prompts per CLAUDE.md §10 + row 29.
/// The screener is the deterministic safety floor; the agent loop
/// never opines on whether food is "safe."
///
/// **Over-warn posture** per row 29 — false-positive-tolerant.
/// Catch every known toxin; an occasional benign match is preferable
/// to a missed xylitol.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

/// Where a [FoodHazardMatch] originated. Parallels
/// [RedFlagSource.chat]/`vision` from the row 64 6.7 vision extension
/// but uses food-domain-specific values — `identified_items` is the
/// extractor's structured Rule-5 vocabulary (the higher-confidence
/// primary signal), `freeform_caption` is the prose secondary.
enum FoodHazardSource {
  /// Matched a phrase in the joined `identified_items` list — the
  /// extractor's plain-English Rule-5 vocabulary (DECISIONS row 105).
  identifiedItems,

  /// Matched the `freeform_caption` body — prose secondary signal.
  freeformCaption,
}

/// A single toxin category from `assets/hazards/food_toxins.yaml`.
/// Phrases are owner-authored plain English; the screener compiles
/// each to a case-insensitive word-bounded regex at load time so the
/// hot-path `matches()` call is a cheap regex sweep.
///
/// `species` filters the category at match time — `grapes: [dog]`
/// skips entirely for a cat photo. Empty list = all species. Null
/// pet species = unknown pet → fire for all categories (over-warn).
class FoodHazardCategory {
  FoodHazardCategory({
    required this.id,
    required this.species,
    required this.aiSummary,
    required this.phrases,
  }) : _regexes = phrases
            .map((p) => RegExp(r'\b' + RegExp.escape(p) + r'\b',
                caseSensitive: false))
            .toList(growable: false);

  /// Stable identifier surfaced in audit logs (and used by the
  /// fixture-walk test to assert category-level coverage). Snake-case
  /// ASCII; never localised.
  final String id;

  /// Species this category fires for. Empty = all species. Compared
  /// case-sensitively against the pet's `SOUL.md`-frontmatter
  /// `species` value (typically 'dog', 'cat'; see `PetRepo`).
  final List<String> species;

  /// One-line clinical-neutral phrase for audit / UI escalation
  /// (rendered in the badge / escalation surface by 8.4).
  final String aiSummary;

  /// Owner-authored phrase list. The matched phrase is returned on a
  /// hit so the UI can show "We spotted 'chocolate' in this photo."
  /// Order matters: the first matching phrase wins in
  /// [_firstMatchingPhrase], so list higher-specificity phrases first
  /// when the category benefits from it (currently irrelevant — v1
  /// categories don't have ordering-sensitive matches).
  final List<String> phrases;

  /// Compiled regexes — one per phrase, in [phrases] order.
  final List<RegExp> _regexes;

  /// True iff any phrase matches [input]. Input is a free-form string
  /// (the caller joins `identified_items` with spaces; the secondary
  /// pass screens the caption directly).
  bool matches(String input) => _regexes.any((r) => r.hasMatch(input));

  /// True iff this category applies to [petSpecies]. Null pet species
  /// fires for ALL categories (over-warn posture).
  bool appliesToSpecies(String? petSpecies) {
    if (species.isEmpty) return true;
    if (petSpecies == null) return true;
    return species.contains(petSpecies);
  }
}

/// Result of a food-hazard screen. Surfaces enough context for the
/// 8.4 capture flow to render the badge + the escalation surface
/// without re-running the screener.
class FoodHazardMatch {
  const FoodHazardMatch({
    required this.category,
    required this.matchedPhrase,
    required this.source,
  });

  final FoodHazardCategory category;

  /// The specific phrase from [FoodHazardCategory.phrases] that fired.
  /// Used in audit logs + the UI's `We spotted '<the phrase>'` rendering.
  final String matchedPhrase;

  final FoodHazardSource source;
}

/// Deterministic phrase screener over the food extractor's output.
/// **Not an LLM call.** Self-contained around a typed
/// `List<FoodHazardCategory>` (injected for testability; the
/// production provider in `lib/app/providers.dart` loads from
/// `assets/hazards/food_toxins.yaml`).
class FoodHazardScreener {
  FoodHazardScreener({required List<FoodHazardCategory> categories})
      : _categories = categories;

  final List<FoodHazardCategory> _categories;

  /// Screen an extraction for known hazards. Returns the first matching
  /// category, preferring `identified_items` matches over
  /// `freeform_caption` matches (the items list went through the
  /// extractor's plain-English Rule 5; the caption is free-form prose
  /// — same primary/secondary posture as RedFlagSource.chat/vision).
  ///
  /// [petSpecies] filters the toxin list. Null = unknown pet → fire
  /// for all categories.
  ///
  /// Returns null when no category matches.
  FoodHazardMatch? screen({
    required List<String> identifiedItems,
    String? freeformCaption,
    String? petSpecies,
  }) {
    // Pass 1: identifiedItems (primary signal). Joined with spaces so
    // multi-word phrases like 'pot brownie' can still match a list
    // like ['pot brownie'] (single token, joined trivially) without
    // breaking single-token matches.
    final itemsJoined = identifiedItems.join(' ');
    if (itemsJoined.trim().isNotEmpty) {
      for (final category in _categories) {
        if (!category.appliesToSpecies(petSpecies)) continue;
        if (category.matches(itemsJoined)) {
          return FoodHazardMatch(
            category: category,
            matchedPhrase: _firstMatchingPhrase(category, itemsJoined),
            source: FoodHazardSource.identifiedItems,
          );
        }
      }
    }

    // Pass 2: freeformCaption (secondary).
    if (freeformCaption != null && freeformCaption.trim().isNotEmpty) {
      for (final category in _categories) {
        if (!category.appliesToSpecies(petSpecies)) continue;
        if (category.matches(freeformCaption)) {
          return FoodHazardMatch(
            category: category,
            matchedPhrase: _firstMatchingPhrase(category, freeformCaption),
            source: FoodHazardSource.freeformCaption,
          );
        }
      }
    }

    return null;
  }

  String _firstMatchingPhrase(FoodHazardCategory category, String input) {
    for (var i = 0; i < category._regexes.length; i++) {
      if (category._regexes[i].hasMatch(input)) return category.phrases[i];
    }
    // matches() returned true upstream so a regex must hit; fallback
    // to the first phrase for defensive completeness.
    return category.phrases.first;
  }
}

/// Source for the toxin category list. Production reads from Flutter
/// assets; tests inject an in-memory list so they don't need a
/// Flutter binding (mirrors `notification_template.dart`'s
/// `AssetNotificationTemplates` / `InMemoryNotificationTemplates`
/// split).
abstract class FoodHazardCategorySource {
  Future<List<FoodHazardCategory>> load();
}

/// Production loader — reads `assets/hazards/food_toxins.yaml` via
/// `rootBundle`. Same pattern as `AssetNotificationTemplates` at
/// `lib/harness/scheduling/notification_template.dart:33-57`.
class AssetFoodHazardCategorySource implements FoodHazardCategorySource {
  const AssetFoodHazardCategorySource();

  @override
  Future<List<FoodHazardCategory>> load() async {
    final raw = await rootBundle.loadString('assets/hazards/food_toxins.yaml');
    return _parseToxinYaml(raw);
  }
}

/// In-memory loader for tests. Holds the typed category list
/// directly — no YAML parse, no rootBundle dep.
class InMemoryFoodHazardCategorySource implements FoodHazardCategorySource {
  InMemoryFoodHazardCategorySource(this._categories);
  final List<FoodHazardCategory> _categories;

  @override
  Future<List<FoodHazardCategory>> load() async => _categories;
}

/// Parse the `assets/hazards/food_toxins.yaml` shape into typed
/// categories. Top-level `categories:` list; each entry has `id`,
/// `species` (list), `ai_summary`, `phrases` (list).
///
/// Throws [FormatException] on missing required keys or wrong types.
/// Unknown extra keys are silently ignored (forward compatibility —
/// future schema additions don't break older readers).
///
/// Exposed for the fixture test that asserts the asset parses cleanly
/// without going through `rootBundle`.
List<FoodHazardCategory> _parseToxinYaml(String raw) {
  final parsed = loadYaml(raw);
  if (parsed is! Map) {
    throw const FormatException(
      'food_toxins.yaml: root must be a YAML map with a `categories:` key.',
    );
  }
  final cats = parsed['categories'];
  if (cats is! List) {
    throw const FormatException(
      'food_toxins.yaml: `categories:` must be a YAML list.',
    );
  }
  return [
    for (final raw in cats) _parseCategory(raw),
  ];
}

FoodHazardCategory _parseCategory(Object? raw) {
  if (raw is! Map) {
    throw const FormatException(
      'food_toxins.yaml: each category must be a YAML map.',
    );
  }
  final id = raw['id'];
  if (id is! String || id.isEmpty) {
    throw const FormatException(
      'food_toxins.yaml: each category needs a non-empty string `id`.',
    );
  }
  final species = raw['species'];
  final phrases = raw['phrases'];
  final aiSummary = raw['ai_summary'];
  if (species is! List) {
    throw FormatException(
      'food_toxins.yaml: category `$id` needs `species:` as a list.',
    );
  }
  if (phrases is! List || phrases.isEmpty) {
    throw FormatException(
      'food_toxins.yaml: category `$id` needs `phrases:` as a non-empty list.',
    );
  }
  if (aiSummary is! String || aiSummary.isEmpty) {
    throw FormatException(
      'food_toxins.yaml: category `$id` needs a non-empty string `ai_summary`.',
    );
  }
  return FoodHazardCategory(
    id: id,
    species: [for (final s in species) s.toString()],
    aiSummary: aiSummary,
    phrases: [for (final p in phrases) p.toString()],
  );
}

/// Test-only re-export of the private parser for fixture tests that
/// want to assert the asset YAML parses cleanly without exercising
/// the full provider stack.
@visibleForTesting
List<FoodHazardCategory> parseFoodToxinYaml(String raw) => _parseToxinYaml(raw);

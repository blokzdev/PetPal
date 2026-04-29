import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// One entry in a category's species JSON. Schema locked in DECISIONS row 46
/// + 48: `display_name`, `scientific_name`, `category`, `inat_taxon_id`,
/// `common_alternatives`, optional `breeds: {name, alternatives[]}[]` for
/// Tier 1 species (Dog / Cat / Rabbit / Guinea Pig / Chicken).
class SpeciesEntry {
  const SpeciesEntry({
    required this.displayName,
    required this.scientificName,
    required this.category,
    required this.inatTaxonId,
    required this.commonAlternatives,
    required this.breeds,
  });

  final String displayName;
  final String scientificName;
  final String category;
  final int? inatTaxonId;
  final List<String> commonAlternatives;

  /// `null` for non-Tier-1 species; populated for Dog / Cat / Rabbit /
  /// Guinea Pig / Chicken with the registry breed list.
  final List<BreedEntry>? breeds;

  /// Whether this species reveals the breed sub-picker (Tier 1 species
  /// per DECISIONS row 46).
  bool get hasBreeds => breeds != null && breeds!.isNotEmpty;

  static SpeciesEntry fromJson(Map<String, dynamic> json) {
    return SpeciesEntry(
      displayName: json['display_name'] as String,
      scientificName: json['scientific_name'] as String,
      category: json['category'] as String,
      inatTaxonId: json['inat_taxon_id'] as int?,
      commonAlternatives:
          (json['common_alternatives'] as List? ?? []).cast<String>(),
      breeds: (json['breeds'] as List?)
          ?.map((e) => BreedEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One breed within a Tier 1 species's `breeds[]` array. DECISIONS row 48
/// schema: `{name, alternatives[]}`.
class BreedEntry {
  const BreedEntry({required this.name, required this.alternatives});

  final String name;
  final List<String> alternatives;

  static BreedEntry fromJson(Map<String, dynamic> json) {
    return BreedEntry(
      name: json['name'] as String,
      alternatives: (json['alternatives'] as List? ?? []).cast<String>(),
    );
  }
}

/// One ranked search hit. Carries the entry plus which field the search
/// matched on, so the picker can render `Display name (also: matched
/// alt)` when the hit was on `commonAlternatives` rather than
/// `display_name` (DECISIONS row 46 picker UX rule + Decision 2 A from
/// 5.5.3 design lock).
class SpeciesSearchHit {
  const SpeciesSearchHit({
    required this.entry,
    required this.matchedAlternative,
  });

  final SpeciesEntry entry;

  /// `null` when the search hit on [SpeciesEntry.displayName]; otherwise
  /// the specific alternative string that matched.
  final String? matchedAlternative;
}

/// One ranked breed search hit. Same shape as [SpeciesSearchHit].
class BreedSearchHit {
  const BreedSearchHit({
    required this.breed,
    required this.matchedAlternative,
  });

  final BreedEntry breed;
  final String? matchedAlternative;
}

/// Per-category species data loaded lazily from `assets/species/<id>.json`
/// (DECISIONS row 46 — search dataset is scoped to the user's category
/// pick at the top level; categories are committed structural choices,
/// not search filters).
abstract class SpeciesCatalog {
  Future<List<SpeciesEntry>> entriesFor(String category);

  /// Search [query] against the entries in [category]. Empty query
  /// returns all entries in JSON order. Non-empty query returns ranked
  /// hits — exact display-name match first, then prefix matches on
  /// display_name, then prefix matches on alternatives, then substring
  /// matches. Each hit includes the matched alternative when the hit
  /// landed there rather than on display_name.
  Future<List<SpeciesSearchHit>> search({
    required String category,
    required String query,
  });

  /// Search breeds within a Tier 1 species's `breeds[]` array. Same
  /// ranking as species search.
  static List<BreedSearchHit> searchBreeds({
    required List<BreedEntry> breeds,
    required String query,
  }) {
    if (query.trim().isEmpty) {
      return [for (final b in breeds) BreedSearchHit(breed: b, matchedAlternative: null)];
    }
    final q = query.toLowerCase().trim();
    final exact = <BreedSearchHit>[];
    final prefixName = <BreedSearchHit>[];
    final prefixAlt = <BreedSearchHit>[];
    final containsName = <BreedSearchHit>[];
    final containsAlt = <BreedSearchHit>[];
    for (final b in breeds) {
      final name = b.name.toLowerCase();
      if (name == q) {
        exact.add(BreedSearchHit(breed: b, matchedAlternative: null));
        continue;
      }
      if (name.startsWith(q)) {
        prefixName.add(BreedSearchHit(breed: b, matchedAlternative: null));
        continue;
      }
      String? altPrefix;
      String? altContains;
      for (final a in b.alternatives) {
        final al = a.toLowerCase();
        if (al == q || al.startsWith(q)) {
          altPrefix ??= a;
          break;
        }
        if (al.contains(q)) altContains ??= a;
      }
      if (altPrefix != null) {
        prefixAlt.add(BreedSearchHit(breed: b, matchedAlternative: altPrefix));
        continue;
      }
      if (name.contains(q)) {
        containsName.add(BreedSearchHit(breed: b, matchedAlternative: null));
        continue;
      }
      if (altContains != null) {
        containsAlt.add(BreedSearchHit(breed: b, matchedAlternative: altContains));
      }
    }
    return [...exact, ...prefixName, ...prefixAlt, ...containsName, ...containsAlt];
  }
}

/// Production [SpeciesCatalog] backed by `assets/species/<category>.json`.
/// Tests inject [InMemorySpeciesCatalog].
class AssetSpeciesCatalog implements SpeciesCatalog {
  AssetSpeciesCatalog();

  final Map<String, List<SpeciesEntry>> _cache = {};

  @override
  Future<List<SpeciesEntry>> entriesFor(String category) async {
    final cached = _cache[category];
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/species/$category.json');
    final list = (json.decode(raw) as List).cast<Map<String, dynamic>>();
    final parsed = list.map(SpeciesEntry.fromJson).toList(growable: false);
    _cache[category] = parsed;
    return parsed;
  }

  @override
  Future<List<SpeciesSearchHit>> search({
    required String category,
    required String query,
  }) async {
    final entries = await entriesFor(category);
    return _rankedSearch(entries: entries, query: query);
  }
}

/// In-memory [SpeciesCatalog] for tests. Construct from a category-keyed
/// map of entry lists.
class InMemorySpeciesCatalog implements SpeciesCatalog {
  InMemorySpeciesCatalog(this._byCategory);
  final Map<String, List<SpeciesEntry>> _byCategory;

  @override
  Future<List<SpeciesEntry>> entriesFor(String category) async =>
      _byCategory[category] ?? const [];

  @override
  Future<List<SpeciesSearchHit>> search({
    required String category,
    required String query,
  }) async {
    return _rankedSearch(
      entries: _byCategory[category] ?? const [],
      query: query,
    );
  }
}

/// Shared ranking — exposed at top level so AssetSpeciesCatalog and
/// InMemorySpeciesCatalog stay byte-identical.
List<SpeciesSearchHit> _rankedSearch({
  required List<SpeciesEntry> entries,
  required String query,
}) {
  if (query.trim().isEmpty) {
    return [for (final e in entries) SpeciesSearchHit(entry: e, matchedAlternative: null)];
  }
  final q = query.toLowerCase().trim();
  final exact = <SpeciesSearchHit>[];
  final prefixName = <SpeciesSearchHit>[];
  final prefixAlt = <SpeciesSearchHit>[];
  final containsName = <SpeciesSearchHit>[];
  final containsAlt = <SpeciesSearchHit>[];
  for (final e in entries) {
    final name = e.displayName.toLowerCase();
    if (name == q) {
      exact.add(SpeciesSearchHit(entry: e, matchedAlternative: null));
      continue;
    }
    if (name.startsWith(q)) {
      prefixName.add(SpeciesSearchHit(entry: e, matchedAlternative: null));
      continue;
    }
    String? altPrefix;
    String? altContains;
    for (final a in e.commonAlternatives) {
      final al = a.toLowerCase();
      if (al == q || al.startsWith(q)) {
        altPrefix ??= a;
        break;
      }
      if (al.contains(q)) altContains ??= a;
    }
    if (altPrefix != null) {
      prefixAlt.add(SpeciesSearchHit(entry: e, matchedAlternative: altPrefix));
      continue;
    }
    if (name.contains(q)) {
      containsName.add(SpeciesSearchHit(entry: e, matchedAlternative: null));
      continue;
    }
    if (altContains != null) {
      containsAlt.add(SpeciesSearchHit(entry: e, matchedAlternative: altContains));
    }
  }
  return [...exact, ...prefixName, ...prefixAlt, ...containsName, ...containsAlt];
}

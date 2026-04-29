import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/species_catalog.dart';

SpeciesEntry _entry({
  required String displayName,
  String scientificName = 'Test scientific',
  String category = 'cat',
  int? inatTaxonId,
  List<String> alternatives = const [],
  List<BreedEntry>? breeds,
}) {
  return SpeciesEntry(
    displayName: displayName,
    scientificName: scientificName,
    category: category,
    inatTaxonId: inatTaxonId,
    commonAlternatives: alternatives,
    breeds: breeds,
  );
}

void main() {
  group('SpeciesEntry.fromJson', () {
    test('parses a row with breeds (Tier 1 shape per row 48)', () {
      final entry = SpeciesEntry.fromJson({
        'display_name': 'Dog',
        'scientific_name': 'Canis familiaris',
        'category': 'dog',
        'inat_taxon_id': 47144,
        'common_alternatives': ['dog', 'puppy'],
        'breeds': [
          {'name': 'Mixed breed', 'alternatives': <String>[]},
          {'name': 'Labrador Retriever', 'alternatives': ['Lab', 'Labrador']},
        ],
      });
      expect(entry.displayName, 'Dog');
      expect(entry.scientificName, 'Canis familiaris');
      expect(entry.category, 'dog');
      expect(entry.inatTaxonId, 47144);
      expect(entry.commonAlternatives, ['dog', 'puppy']);
      expect(entry.hasBreeds, isTrue);
      expect(entry.breeds, hasLength(2));
      expect(entry.breeds![1].name, 'Labrador Retriever');
      expect(entry.breeds![1].alternatives, ['Lab', 'Labrador']);
    });

    test('parses a row without breeds (non-Tier-1 species)', () {
      final entry = SpeciesEntry.fromJson({
        'display_name': 'Bearded Dragon',
        'scientific_name': 'Pogona vitticeps',
        'category': 'reptile',
        'inat_taxon_id': null,
        'common_alternatives': ['beardie'],
      });
      expect(entry.hasBreeds, isFalse);
      expect(entry.breeds, isNull);
    });

    test('handles null inat_taxon_id', () {
      final entry = SpeciesEntry.fromJson({
        'display_name': 'Cockatiel',
        'scientific_name': 'Nymphicus hollandicus',
        'category': 'bird',
        'inat_taxon_id': null,
        'common_alternatives': <String>[],
      });
      expect(entry.inatTaxonId, isNull);
    });
  });

  group('InMemorySpeciesCatalog.search ranking', () {
    final entries = [
      _entry(displayName: 'Cat', alternatives: ['kitten', 'kitty']),
      _entry(displayName: 'Domestic Shorthair', alternatives: ['DSH', 'tabby', 'calico']),
      _entry(displayName: 'Persian'),
      _entry(displayName: 'Maine Coon', alternatives: ['Coon cat', 'Maine Cat']),
      _entry(displayName: 'Sphynx', alternatives: ['Sphinx', 'hairless cat']),
      _entry(displayName: 'Scottish Fold', alternatives: ['Highland Fold']),
    ];
    final catalog = InMemorySpeciesCatalog({'cat': entries});

    test('empty query returns all entries in JSON order', () async {
      final hits = await catalog.search(category: 'cat', query: '');
      expect(hits.map((h) => h.entry.displayName), [
        'Cat', 'Domestic Shorthair', 'Persian', 'Maine Coon', 'Sphynx', 'Scottish Fold',
      ]);
      expect(hits.every((h) => h.matchedAlternative == null), isTrue);
    });

    test('exact display_name match outranks prefix matches', () async {
      final hits = await catalog.search(category: 'cat', query: 'cat');
      // "Cat" is exact, "Maine Coon"'s "Coon cat" alt contains "cat",
      // "Sphynx"'s "hairless cat" alt contains "cat" — exact wins
      expect(hits.first.entry.displayName, 'Cat');
    });

    test('prefix match on display_name ranks above alternative match', () async {
      final hits = await catalog.search(category: 'cat', query: 'sc');
      // "Scottish Fold" prefix on display_name should beat alts
      expect(hits.first.entry.displayName, 'Scottish Fold');
    });

    test('matched alternative is surfaced in the hit', () async {
      final hits = await catalog.search(category: 'cat', query: 'tabby');
      expect(hits, isNotEmpty);
      final hit = hits.first;
      expect(hit.entry.displayName, 'Domestic Shorthair');
      expect(hit.matchedAlternative, 'tabby');
    });

    test('alternative search is case-insensitive', () async {
      final hits = await catalog.search(category: 'cat', query: 'DSH');
      expect(hits.first.entry.displayName, 'Domestic Shorthair');
      expect(hits.first.matchedAlternative, 'DSH');
    });

    test('substring match on display_name when no prefix hit', () async {
      // "yhair" is in "Domestic Shorthair" but not at any prefix
      final hits = await catalog.search(category: 'cat', query: 'thair');
      expect(hits, isNotEmpty);
      expect(hits.first.entry.displayName, 'Domestic Shorthair');
      // Substring match on display_name → matched_alternative null
      expect(hits.first.matchedAlternative, isNull);
    });

    test('no match returns empty list', () async {
      final hits = await catalog.search(category: 'cat', query: 'platypus');
      expect(hits, isEmpty);
    });

    test('unknown category returns empty list (no throw)', () async {
      final hits = await catalog.search(category: 'unicorn', query: 'cat');
      expect(hits, isEmpty);
    });
  });

  group('SpeciesCatalog.searchBreeds ranking', () {
    final breeds = [
      const BreedEntry(name: 'Mixed breed', alternatives: []),
      const BreedEntry(name: 'Not sure', alternatives: []),
      const BreedEntry(name: 'Labrador Retriever', alternatives: ['Lab', 'Labrador']),
      const BreedEntry(name: 'French Bulldog', alternatives: ['Frenchie']),
      const BreedEntry(name: 'German Shepherd Dog', alternatives: ['GSD', 'German Shepherd']),
      const BreedEntry(name: 'Beagle', alternatives: []),
    ];

    test('empty query returns all breeds in array order', () {
      final hits = SpeciesCatalog.searchBreeds(breeds: breeds, query: '');
      expect(hits.map((h) => h.breed.name), [
        'Mixed breed', 'Not sure', 'Labrador Retriever', 'French Bulldog',
        'German Shepherd Dog', 'Beagle',
      ]);
    });

    test('display_name prefix outranks alt match (matchedAlternative null)', () {
      // "Lab" prefixes the display_name "Labrador Retriever" — that's a
      // direct hit on the breed name itself, not a hit on the alternative
      // "Lab", so matchedAlternative is null. This matches the picker UX:
      // user typed "Lab" and gets "Labrador Retriever", no "(also: Lab)"
      // chrome because "Lab" is a sub-string of the breed itself.
      final hits = SpeciesCatalog.searchBreeds(breeds: breeds, query: 'Lab');
      expect(hits.first.breed.name, 'Labrador Retriever');
      expect(hits.first.matchedAlternative, isNull);
    });

    test('prefix on breed name outranks substring match', () {
      // "Be" prefixes "Beagle"; nothing else
      final hits = SpeciesCatalog.searchBreeds(breeds: breeds, query: 'be');
      expect(hits.first.breed.name, 'Beagle');
    });

    test('Frenchie alternative finds French Bulldog', () {
      final hits = SpeciesCatalog.searchBreeds(breeds: breeds, query: 'Frenchie');
      expect(hits.first.breed.name, 'French Bulldog');
      expect(hits.first.matchedAlternative, 'Frenchie');
    });

    test('GSD acronym alternative finds German Shepherd Dog', () {
      final hits = SpeciesCatalog.searchBreeds(breeds: breeds, query: 'gsd');
      expect(hits.first.breed.name, 'German Shepherd Dog');
      expect(hits.first.matchedAlternative, 'GSD');
    });
  });
}

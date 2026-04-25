import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/skills/skill_loader.dart';
import 'package:petpal/harness/skills/skill_manifest.dart';
import 'package:petpal/harness/skills/skill_source.dart';

/// In-memory [SkillSource] for tests. Construct from a list of
/// `(manifest, fragments)` pairs — fragments is a filename → body map.
class _FakeSkillSource implements SkillSource {
  _FakeSkillSource(this._entries);
  final List<({SkillManifest manifest, Map<String, String> fragments})>
      _entries;

  @override
  Future<List<SkillSourceEntry>> list() async {
    return [
      for (final e in _entries)
        SkillSourceEntry(
          manifest: e.manifest,
          readFragment: (filename) async {
            final body = e.fragments[filename];
            if (body == null) {
              throw StateError('${e.manifest.id}: no fragment "$filename"');
            }
            return body;
          },
        ),
    ];
  }
}

SkillManifest _manifest({
  required String id,
  List<String> species = const [],
  List<String> triggers = const [],
  List<String> loads = const [],
}) {
  return SkillManifest(
    id: id,
    name: id,
    version: 1,
    species: species,
    triggers: triggers,
    loads: loads,
    requiresPro: false,
  );
}

void main() {
  test('empty source produces no fragments', () async {
    final loader = SkillLoader(source: _FakeSkillSource(const []));
    final out = await loader.match(petSpecies: 'dog', userInput: 'anything');
    expect(out, isEmpty);
  });

  test('species mismatch filters the skill out before trigger matching',
      () async {
    final loader = SkillLoader(
      source: _FakeSkillSource([
        (
          manifest: _manifest(
            id: 'puppy',
            species: ['dog'],
            triggers: ['puppy'],
            loads: ['overview.md'],
          ),
          fragments: {'overview.md': 'Puppy basics.'},
        ),
      ]),
    );
    final out = await loader.match(
      petSpecies: 'cat',
      userInput: 'I have a puppy that nips',
    );
    expect(out, isEmpty);
  });

  test('species hit + trigger hit returns every fragment in `loads:` in '
      'declaration order', () async {
    final loader = SkillLoader(
      source: _FakeSkillSource([
        (
          manifest: _manifest(
            id: 'puppy',
            species: ['dog'],
            triggers: ['puppy', 'house training'],
            loads: ['overview.md', 'house-training.md'],
          ),
          fragments: {
            'overview.md': 'Puppy overview.',
            'house-training.md': 'House training tips.',
          },
        ),
      ]),
    );
    final out = await loader.match(
      petSpecies: 'dog',
      userInput: 'How do I house train my puppy?',
    );
    expect(out.map((f) => f.filename), [
      'overview.md',
      'house-training.md',
    ]);
    expect(out[0].skillId, 'puppy');
    expect(out[0].text, 'Puppy overview.');
    expect(out[1].text, 'House training tips.');
  });

  test('trigger matching is case-insensitive', () async {
    final loader = SkillLoader(
      source: _FakeSkillSource([
        (
          manifest: _manifest(
            id: 'cat-101',
            species: ['cat'],
            triggers: ['litter box'],
            loads: ['x.md'],
          ),
          fragments: {'x.md': 'cat tips'},
        ),
      ]),
    );
    final out = await loader.match(
      petSpecies: 'cat',
      userInput: 'My LITTER Box situation is dire',
    );
    expect(out, hasLength(1));
  });

  test('skill with empty species (universal) passes species filter for any '
      'species', () async {
    final loader = SkillLoader(
      source: _FakeSkillSource([
        (
          manifest: _manifest(
            id: 'weight',
            triggers: ['weight'],
            loads: ['x.md'],
          ),
          fragments: {'x.md': 'weight tracking'},
        ),
      ]),
    );
    final dog = await loader.match(
      petSpecies: 'dog',
      userInput: 'tracking weight',
    );
    final parakeet = await loader.match(
      petSpecies: 'parakeet',
      userInput: 'tracking weight',
    );
    expect(dog, hasLength(1));
    expect(parakeet, hasLength(1));
  });

  test('species hit but no trigger match returns nothing', () async {
    final loader = SkillLoader(
      source: _FakeSkillSource([
        (
          manifest: _manifest(
            id: 'puppy',
            species: ['dog'],
            triggers: ['puppy', 'teething'],
            loads: ['x.md'],
          ),
          fragments: {'x.md': 'body'},
        ),
      ]),
    );
    final out = await loader.match(
      petSpecies: 'dog',
      userInput: 'Just a normal walk today',
    );
    expect(out, isEmpty);
  });

  test('multiple matching skills concatenate fragments in source order',
      () async {
    final loader = SkillLoader(
      source: _FakeSkillSource([
        (
          manifest: _manifest(
            id: 'puppy',
            species: ['dog'],
            triggers: ['puppy'],
            loads: ['p1.md'],
          ),
          fragments: {'p1.md': 'puppy fragment'},
        ),
        (
          manifest: _manifest(
            id: 'weight',
            triggers: ['puppy'],
            loads: ['w1.md'],
          ),
          fragments: {'w1.md': 'weight fragment'},
        ),
      ]),
    );
    final out = await loader.match(
      petSpecies: 'dog',
      userInput: 'my puppy',
    );
    expect(out.map((f) => f.skillId), ['puppy', 'weight']);
  });

  test('non-matching skills do not have their fragments read (lazy)',
      () async {
    var dogReads = 0;
    var catReads = 0;
    final source = _DelegatedSource([
      SkillSourceEntry(
        manifest: _manifest(
          id: 'puppy',
          species: ['dog'],
          triggers: ['puppy'],
          loads: ['p.md'],
        ),
        readFragment: (_) async {
          dogReads += 1;
          return 'dog body';
        },
      ),
      SkillSourceEntry(
        manifest: _manifest(
          id: 'kitten',
          species: ['cat'],
          triggers: ['kitten'],
          loads: ['k.md'],
        ),
        readFragment: (_) async {
          catReads += 1;
          return 'cat body';
        },
      ),
    ]);
    final loader = SkillLoader(source: source);
    await loader.match(petSpecies: 'dog', userInput: 'my puppy');
    expect(dogReads, 1);
    expect(catReads, 0, reason: 'cat skill filtered out before read');
  });
}

class _DelegatedSource implements SkillSource {
  _DelegatedSource(this.entries);
  final List<SkillSourceEntry> entries;
  @override
  Future<List<SkillSourceEntry>> list() async => entries;
}

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
  List<String> category = const [],
  List<String> triggers = const [],
  List<String> loads = const [],
  bool requiresPro = false,
}) {
  return SkillManifest(
    id: id,
    name: id,
    version: 1,
    category: category,
    triggers: triggers,
    loads: loads,
    requiresPro: requiresPro,
  );
}

void main() {
  test('empty source produces no fragments', () async {
    final loader = SkillLoader(source: _FakeSkillSource(const []));
    final out = await loader.match(petCategory: 'dog', userInput: 'anything');
    expect(out, isEmpty);
  });

  test('category mismatch filters the skill out before trigger matching',
      () async {
    final loader = SkillLoader(
      source: _FakeSkillSource([
        (
          manifest: _manifest(
            id: 'puppy',
            category: ['dog'],
            triggers: ['puppy'],
            loads: ['overview.md'],
          ),
          fragments: {'overview.md': 'Puppy basics.'},
        ),
      ]),
    );
    final out = await loader.match(
      petCategory: 'cat',
      userInput: 'I have a puppy that nips',
    );
    expect(out, isEmpty);
  });

  test('category hit + trigger hit returns every fragment in `loads:` in '
      'declaration order', () async {
    final loader = SkillLoader(
      source: _FakeSkillSource([
        (
          manifest: _manifest(
            id: 'puppy',
            category: ['dog'],
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
      petCategory: 'dog',
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
            category: ['cat'],
            triggers: ['litter box'],
            loads: ['x.md'],
          ),
          fragments: {'x.md': 'cat tips'},
        ),
      ]),
    );
    final out = await loader.match(
      petCategory: 'cat',
      userInput: 'My LITTER Box situation is dire',
    );
    expect(out, hasLength(1));
  });

  test('skill with empty category (universal) passes category filter for any '
      'category', () async {
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
      petCategory: 'dog',
      userInput: 'tracking weight',
    );
    final parakeet = await loader.match(
      petCategory: 'parakeet',
      userInput: 'tracking weight',
    );
    expect(dog, hasLength(1));
    expect(parakeet, hasLength(1));
  });

  test('category hit but no trigger match returns nothing', () async {
    final loader = SkillLoader(
      source: _FakeSkillSource([
        (
          manifest: _manifest(
            id: 'puppy',
            category: ['dog'],
            triggers: ['puppy', 'teething'],
            loads: ['x.md'],
          ),
          fragments: {'x.md': 'body'},
        ),
      ]),
    );
    final out = await loader.match(
      petCategory: 'dog',
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
            category: ['dog'],
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
      petCategory: 'dog',
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
          category: ['dog'],
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
          category: ['cat'],
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
    await loader.match(petCategory: 'dog', userInput: 'my puppy');
    expect(dogReads, 1);
    expect(catReads, 0, reason: 'cat skill filtered out before read');
  });

  // ── Phase 7 task C.3 — entitlement gate on requires_pro skills ──────

  group('Phase 7 task C.3 — entitlement gate on requires_pro skills', () {
    final paid = _manifest(
      id: 'reactive-dog',
      category: ['dog'],
      triggers: ['reactive'],
      loads: ['overview.md'],
      requiresPro: true,
    );
    final free = _manifest(
      id: 'puppy',
      category: ['dog'],
      triggers: ['puppy'],
      loads: ['overview.md'],
    );
    final source = _FakeSkillSource([
      (manifest: paid, fragments: const {'overview.md': 'paid content'}),
      (manifest: free, fragments: const {'overview.md': 'free content'}),
    ]);

    test('non-Pro + no care-pack ownership → requires_pro skill is dropped',
        () async {
      final loader = SkillLoader(source: source);
      final result = await loader.match(
        petCategory: 'dog',
        userInput: 'my reactive dog',
      );
      expect(result, hasLength(0),
          reason: 'requires_pro skill must be gated; trigger "reactive" '
              'matches but the skill is locked');
    });

    test('non-Pro + matching care-pack ownership → skill loads', () async {
      final loader = SkillLoader(
        source: source,
        ownedCarePackSkillIds: const {'reactive-dog'},
      );
      final result = await loader.match(
        petCategory: 'dog',
        userInput: 'my reactive dog',
      );
      expect(result, hasLength(1));
      expect(result.first.skillId, 'reactive-dog');
      expect(result.first.text, 'paid content');
    });

    test('Pro user → all requires_pro skills load regardless of '
        'ownership set', () async {
      final loader = SkillLoader(source: source, isPro: true);
      final result = await loader.match(
        petCategory: 'dog',
        userInput: 'my reactive dog',
      );
      expect(result, hasLength(1));
      expect(result.first.skillId, 'reactive-dog');
    });

    test('free skill (requires_pro: false) loads regardless of '
        'entitlement state', () async {
      final loader = SkillLoader(source: source);
      final result = await loader.match(
        petCategory: 'dog',
        userInput: 'puppy training',
      );
      expect(result, hasLength(1));
      expect(result.first.skillId, 'puppy');
    });

    test('mismatched care-pack ownership ID does NOT unlock other paid '
        'skills (only the matching skill ID counts)', () async {
      final loader = SkillLoader(
        source: source,
        ownedCarePackSkillIds: const {'senior-dog'}, // wrong skill
      );
      final result = await loader.match(
        petCategory: 'dog',
        userInput: 'my reactive dog',
      );
      expect(result, hasLength(0),
          reason: 'owning senior-dog must NOT unlock reactive-dog');
    });
  });
}

class _DelegatedSource implements SkillSource {
  _DelegatedSource(this.entries);
  final List<SkillSourceEntry> entries;
  @override
  Future<List<SkillSourceEntry>> list() async => entries;
}

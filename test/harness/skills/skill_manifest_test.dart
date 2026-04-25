import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/skills/skill_manifest.dart';

void main() {
  group('parseSkillManifest', () {
    test('parses the canonical CLAUDE.md §9 example', () {
      const text = '''
---
id: puppy
name: Puppy Care
version: 1
species: [dog]
triggers: ["puppy", "teething", "house training", "socialization"]
loads: ["overview.md", "house-training.md", "socialization.md"]
requires_pro: false
---

# Puppy
Skill body — unused; loaded fragments come from `loads:`.
''';
      final m = parseSkillManifest(text);
      expect(m.id, 'puppy');
      expect(m.name, 'Puppy Care');
      expect(m.version, 1);
      expect(m.species, ['dog']);
      expect(
        m.triggers,
        ['puppy', 'teething', 'house training', 'socialization'],
      );
      expect(m.loads, [
        'overview.md',
        'house-training.md',
        'socialization.md',
      ]);
      expect(m.requiresPro, isFalse);
    });

    test('omitted species list is treated as "any species" (CLAUDE.md §9)',
        () {
      const text = '''
---
id: weight-tracking
name: Weight tracking
version: 1
triggers: ["weight"]
loads: []
---
''';
      final m = parseSkillManifest(text);
      expect(m.species, isEmpty);
      expect(m.matchesSpecies('dog'), isTrue);
      expect(m.matchesSpecies('cat'), isTrue);
      expect(m.matchesSpecies('parakeet'), isTrue);
    });

    test('species: [dog, cat] matches both, rejects bird', () {
      const text = '''
---
id: mammal-grooming
name: Mammal grooming
version: 1
species: [dog, cat]
triggers: []
loads: []
---
''';
      final m = parseSkillManifest(text);
      expect(m.matchesSpecies('dog'), isTrue);
      expect(m.matchesSpecies('cat'), isTrue);
      expect(m.matchesSpecies('bird'), isFalse);
    });

    test('requires_pro defaults to false when omitted', () {
      const text = '''
---
id: x
name: x
version: 1
---
''';
      final m = parseSkillManifest(text);
      expect(m.requiresPro, isFalse);
    });

    test('throws on missing id', () {
      const text = '''
---
name: x
version: 1
---
''';
      expect(
        () => parseSkillManifest(text),
        throwsA(
          isA<SkillManifestException>()
              .having((e) => e.message, 'message', contains('id')),
        ),
      );
    });

    test('throws on missing name', () {
      const text = '''
---
id: x
version: 1
---
''';
      expect(
        () => parseSkillManifest(text),
        throwsA(
          isA<SkillManifestException>()
              .having((e) => e.message, 'message', contains('name')),
        ),
      );
    });

    test('throws on non-int version', () {
      const text = '''
---
id: x
name: x
version: "1.0"
---
''';
      expect(
        () => parseSkillManifest(text),
        throwsA(
          isA<SkillManifestException>()
              .having((e) => e.message, 'message', contains('version')),
        ),
      );
    });
  });
}

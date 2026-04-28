import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/soul_file.dart';

void main() {
  group('parseSoul', () {
    test('extracts frontmatter map and body from the canonical layout', () {
      const text = '''
---
category: dog
breed: mixed
dob: 2022-06-12
weight_kg: 14.2
allergies: [chicken]
meds: []
vet_contact: 'Dr. Patel'
temperament: [anxious, food-motivated]
---

# Milo
Milo is a rescue mutt.
''';
      final parsed = parseSoul(text);
      expect(parsed.frontmatter['category'], 'dog');
      expect(parsed.frontmatter['breed'], 'mixed');
      expect(parsed.frontmatter['dob'], '2022-06-12');
      expect(parsed.frontmatter['weight_kg'], 14.2);
      expect(parsed.frontmatter['allergies'], ['chicken']);
      expect(parsed.frontmatter['meds'], isEmpty);
      expect(parsed.frontmatter['vet_contact'], 'Dr. Patel');
      expect(parsed.frontmatter['temperament'],
          ['anxious', 'food-motivated']);
      expect(parsed.body, contains('# Milo'));
    });

    test('handles missing frontmatter — returns empty map and full body',
        () {
      const text = 'Just a body.\nNo frontmatter here.\n';
      final parsed = parseSoul(text);
      expect(parsed.frontmatter, isEmpty);
      expect(parsed.body, text);
    });

    test('handles malformed (no closing ---) by treating as body-only', () {
      const text = '---\ncategory: dog\nMilo lives here.\n';
      final parsed = parseSoul(text);
      expect(parsed.frontmatter, isEmpty);
    });
  });

  group('serializeSoul', () {
    test('emits keys in the canonical CLAUDE.md order, then anything else',
        () {
      final out = serializeSoul(
        frontmatter: {
          'extra_key': 'first-in-input',
          'breed': 'mixed',
          'category': 'dog',
        },
        body: '\n# Milo\n',
      );
      // species comes before breed because of keyOrder; extra_key trails.
      final speciesIdx = out.indexOf('category:');
      final breedIdx = out.indexOf('breed:');
      final extraIdx = out.indexOf('extra_key:');
      expect(speciesIdx, lessThan(breedIdx));
      expect(breedIdx, lessThan(extraIdx));
    });

    test('round-trips through parseSoul', () {
      const original = '''
---
category: dog
breed: mixed
dob: 2022-06-12
weight_kg: 14.2
allergies: [chicken]
meds: []
vet_contact: Dr. Patel
temperament: [anxious]
---

# Milo
A rescue.
''';
      final parsed = parseSoul(original);
      final reemitted = serializeSoul(
        frontmatter: parsed.frontmatter,
        body: parsed.body,
      );
      final reparsed = parseSoul(reemitted);
      expect(reparsed.frontmatter['category'], 'dog');
      expect(reparsed.frontmatter['allergies'], ['chicken']);
      expect(reparsed.frontmatter['weight_kg'], 14.2);
      expect(reparsed.body, parsed.body);
    });
  });

  group('mergeFrontmatter', () {
    test('overwrites scalars and replaces lists, leaves untouched keys',
        () {
      final base = <String, Object?>{
        'category': 'dog',
        'weight_kg': 14.2,
        'allergies': ['chicken'],
        'breed': 'mixed',
      };
      final patch = <String, Object?>{
        'weight_kg': 14.5,
        'allergies': ['chicken', 'beef'],
      };
      final merged = mergeFrontmatter(base, patch);
      expect(merged['category'], 'dog');
      expect(merged['breed'], 'mixed');
      expect(merged['weight_kg'], 14.5);
      expect(merged['allergies'], ['chicken', 'beef']);
    });
  });
}

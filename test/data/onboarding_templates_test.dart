import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/onboarding_templates.dart';
import 'package:petpal/data/soul_file.dart';

void main() {
  group('Species', () {
    test('all 8 species are unique by id', () {
      final ids = Species.values.map((s) => s.id).toSet();
      expect(ids, hasLength(Species.values.length));
    });

    test('fromId round-trips known species', () {
      for (final s in Species.values) {
        expect(Species.fromId(s.id), s);
      }
    });

    test('fromId returns null for unknown', () {
      expect(Species.fromId('platypus'), isNull);
    });
  });

  group('renderTemplate', () {
    test('substitutes {name}, {breed}, {dob} placeholders', () {
      const tpl = '---\nspecies: dog\nbreed: {breed}\ndob: {dob}\n---\n# {name}\n';
      final out = renderTemplate(
        tpl,
        name: 'Milo',
        breed: 'mixed',
        dob: DateTime(2022, 6, 12),
      );
      expect(out, contains('breed: mixed'));
      expect(out, contains('dob: 2022-06-12'));
      expect(out, contains('# Milo'));
    });

    test('omitted breed/dob render as empty strings', () {
      const tpl = 'breed: {breed}; dob: {dob}; name: {name}';
      expect(
        renderTemplate(tpl, name: 'Luna'),
        'breed: ; dob: ; name: Luna',
      );
    });
  });

  group('InMemoryOnboardingTemplates', () {
    test('returns rendered template for a known species', () async {
      final t = InMemoryOnboardingTemplates({
        Species.cat: '---\nspecies: cat\n---\n# {name}\n',
      });
      final out = await t.seedSoulFor(species: Species.cat, name: 'Whiskers');
      expect(out, contains('species: cat'));
      expect(out, contains('# Whiskers'));
    });

    test('throws for missing species (no silent fallback)', () async {
      final t = InMemoryOnboardingTemplates(const {});
      await expectLater(
        () => t.seedSoulFor(species: Species.fish, name: 'Bubbles'),
        throwsStateError,
      );
    });

    test('the rendered SOUL.md round-trips through parseSoul with species '
        'preserved in frontmatter', () async {
      final t = InMemoryOnboardingTemplates({
        Species.bird: '---\nspecies: bird\nweight_g:\n---\n# {name}\n',
      });
      final out = await t.seedSoulFor(species: Species.bird, name: 'Pip');
      final parsed = parseSoul(out);
      expect(parsed.frontmatter['species'], 'bird');
      expect(parsed.body, contains('# Pip'));
    });
  });
}

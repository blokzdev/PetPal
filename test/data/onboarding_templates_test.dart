import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/onboarding_templates.dart';
import 'package:petpal/data/soul_file.dart';

void main() {
  group('Category', () {
    test('all 8 categories are unique by id', () {
      final ids = Category.values.map((s) => s.id).toSet();
      expect(ids, hasLength(Category.values.length));
    });

    test('fromId round-trips known categories', () {
      for (final s in Category.values) {
        expect(Category.fromId(s.id), s);
      }
    });

    test('fromId returns null for unknown', () {
      expect(Category.fromId('platypus'), isNull);
    });
  });

  group('renderTemplate', () {
    test('substitutes {name}, {breed}, {dob} placeholders', () {
      const tpl = '---\ncategory: dog\nbreed: {breed}\ndob: {dob}\n---\n# {name}\n';
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
    test('returns rendered template for a known category', () async {
      final t = InMemoryOnboardingTemplates({
        Category.cat: '---\ncategory: cat\n---\n# {name}\n',
      });
      final out = await t.seedSoulFor(category: Category.cat, name: 'Whiskers');
      expect(out, contains('category: cat'));
      expect(out, contains('# Whiskers'));
    });

    test('throws for missing category (no silent fallback)', () async {
      final t = InMemoryOnboardingTemplates(const {});
      await expectLater(
        () => t.seedSoulFor(category: Category.fish, name: 'Bubbles'),
        throwsStateError,
      );
    });

    test('the rendered SOUL.md round-trips through parseSoul with category '
        'preserved in frontmatter', () async {
      final t = InMemoryOnboardingTemplates({
        Category.bird: '---\ncategory: bird\nweight_g:\n---\n# {name}\n',
      });
      final out = await t.seedSoulFor(category: Category.bird, name: 'Pip');
      final parsed = parseSoul(out);
      expect(parsed.frontmatter['category'], 'bird');
      expect(parsed.body, contains('# Pip'));
    });
  });
}

import 'package:flutter/services.dart' show rootBundle;

/// The eight categories the add-pet flow recognises. Picking one of these
/// triggers a category-specific `SOUL.md` template that seeds the
/// frontmatter keys the harness will track from day one.
///
/// Anything not in this list falls through to the [exotic] template —
/// the harness still works (skill filter is the only category-aware
/// path; see CLAUDE.md §3), but the SOUL frontmatter is plain.
enum Category {
  dog('dog'),
  cat('cat'),
  bird('bird'),
  rabbit('rabbit'),
  reptile('reptile'),
  fish('fish'),
  smallMammal('small-mammal'),
  exotic('exotic');

  const Category(this.id);

  /// Lowercase identifier. Used as the SOUL.md `category:` value AND as
  /// the asset filename (`assets/onboarding/<id>.md`). Skill manifests
  /// match against this.
  final String id;

  /// Human-readable label for the category picker.
  String get label {
    switch (this) {
      case Category.dog:
        return 'Dog';
      case Category.cat:
        return 'Cat';
      case Category.bird:
        return 'Bird';
      case Category.rabbit:
        return 'Rabbit';
      case Category.reptile:
        return 'Reptile';
      case Category.fish:
        return 'Fish';
      case Category.smallMammal:
        return 'Small mammal';
      case Category.exotic:
        return 'Other / exotic';
    }
  }

  static Category? fromId(String id) {
    for (final c in Category.values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Source of onboarding templates. Production reads from Flutter assets;
/// tests inject an in-memory map so they don't need a Flutter binding.
abstract class OnboardingTemplates {
  /// Return a rendered SOUL.md for a new pet of [category]. Substitutes
  /// {species}, {name}, {breed}, {dob} placeholders in the template;
  /// category-specific frontmatter keys come from the template itself.
  Future<String> seedSoulFor({
    required Category category,
    required String name,
    String? species,
    String? breed,
    DateTime? dob,
  });
}

/// Production [OnboardingTemplates] backed by `assets/onboarding/<id>.md`.
class AssetOnboardingTemplates implements OnboardingTemplates {
  const AssetOnboardingTemplates();

  @override
  Future<String> seedSoulFor({
    required Category category,
    required String name,
    String? species,
    String? breed,
    DateTime? dob,
  }) async {
    final raw = await rootBundle.loadString(
      'assets/onboarding/${category.id}.md',
    );
    return renderTemplate(raw, name: name, species: species, breed: breed, dob: dob);
  }
}

/// Pure substitution: replaces `{species}`, `{name}`, `{breed}`, `{dob}`
/// in [template] with the provided values. Empty values leave the
/// placeholder (frontmatter parsing already tolerates `key:` with no
/// value).
///
/// Exposed at top level so tests and the in-memory implementation can
/// share the same renderer.
String renderTemplate(
  String template, {
  required String name,
  String? species,
  String? breed,
  DateTime? dob,
}) {
  final dobStr = dob == null
      ? ''
      : '${dob.year.toString().padLeft(4, '0')}-'
          '${dob.month.toString().padLeft(2, '0')}-'
          '${dob.day.toString().padLeft(2, '0')}';
  return template
      .replaceAll('{species}', species ?? '')
      .replaceAll('{name}', name)
      .replaceAll('{breed}', breed ?? '')
      .replaceAll('{dob}', dobStr);
}

/// In-memory [OnboardingTemplates] for tests.
class InMemoryOnboardingTemplates implements OnboardingTemplates {
  InMemoryOnboardingTemplates(this._templates);
  final Map<Category, String> _templates;

  @override
  Future<String> seedSoulFor({
    required Category category,
    required String name,
    String? species,
    String? breed,
    DateTime? dob,
  }) async {
    final tpl = _templates[category] ??
        (throw StateError('no template for ${category.id}'));
    return renderTemplate(tpl, name: name, species: species, breed: breed, dob: dob);
  }
}

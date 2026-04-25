import 'package:flutter/services.dart' show rootBundle;

/// The eight species the add-pet flow recognises. Picking one of these
/// triggers a species-specific `SOUL.md` template that seeds the
/// frontmatter keys the harness will track from day one.
///
/// Anything not in this list falls through to the [generic] template —
/// the harness still works (skill filter is the only species-aware
/// path; see CLAUDE.md §3), but the SOUL frontmatter is plain.
enum Species {
  dog('dog'),
  cat('cat'),
  bird('bird'),
  rabbit('rabbit'),
  reptile('reptile'),
  fish('fish'),
  smallMammal('small-mammal'),
  exotic('exotic');

  const Species(this.id);

  /// Lowercase identifier. Used as the SOUL.md `species:` value AND as
  /// the asset filename (`assets/onboarding/<id>.md`). Skill manifests
  /// match against this.
  final String id;

  /// Human-readable label for the species picker.
  String get label {
    switch (this) {
      case Species.dog:
        return 'Dog';
      case Species.cat:
        return 'Cat';
      case Species.bird:
        return 'Bird';
      case Species.rabbit:
        return 'Rabbit';
      case Species.reptile:
        return 'Reptile';
      case Species.fish:
        return 'Fish';
      case Species.smallMammal:
        return 'Small mammal';
      case Species.exotic:
        return 'Other / exotic';
    }
  }

  static Species? fromId(String id) {
    for (final s in Species.values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// Source of onboarding templates. Production reads from Flutter assets;
/// tests inject an in-memory map so they don't need a Flutter binding.
abstract class OnboardingTemplates {
  /// Return a rendered SOUL.md for a new pet of [species]. Substitutes
  /// {name}, {breed}, {dob} placeholders in the template; species-
  /// specific frontmatter keys come from the template itself.
  Future<String> seedSoulFor({
    required Species species,
    required String name,
    String? breed,
    DateTime? dob,
  });
}

/// Production [OnboardingTemplates] backed by `assets/onboarding/<id>.md`.
class AssetOnboardingTemplates implements OnboardingTemplates {
  const AssetOnboardingTemplates();

  @override
  Future<String> seedSoulFor({
    required Species species,
    required String name,
    String? breed,
    DateTime? dob,
  }) async {
    final raw = await rootBundle.loadString(
      'assets/onboarding/${species.id}.md',
    );
    return renderTemplate(raw, name: name, breed: breed, dob: dob);
  }
}

/// Pure substitution: replaces `{name}`, `{breed}`, `{dob}` in [template]
/// with the provided values. Empty values leave the placeholder
/// (frontmatter parsing already tolerates `key:` with no value).
///
/// Exposed at top level so tests and the in-memory implementation can
/// share the same renderer.
String renderTemplate(
  String template, {
  required String name,
  String? breed,
  DateTime? dob,
}) {
  final dobStr = dob == null
      ? ''
      : '${dob.year.toString().padLeft(4, '0')}-'
          '${dob.month.toString().padLeft(2, '0')}-'
          '${dob.day.toString().padLeft(2, '0')}';
  return template
      .replaceAll('{name}', name)
      .replaceAll('{breed}', breed ?? '')
      .replaceAll('{dob}', dobStr);
}

/// In-memory [OnboardingTemplates] for tests.
class InMemoryOnboardingTemplates implements OnboardingTemplates {
  InMemoryOnboardingTemplates(this._templates);
  final Map<Species, String> _templates;

  @override
  Future<String> seedSoulFor({
    required Species species,
    required String name,
    String? breed,
    DateTime? dob,
  }) async {
    final tpl = _templates[species] ??
        (throw StateError('no template for ${species.id}'));
    return renderTemplate(tpl, name: name, breed: breed, dob: dob);
  }
}

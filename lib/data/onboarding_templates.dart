import 'package:flutter/services.dart' show rootBundle;

import 'relationship.dart';

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
  /// Return a rendered SOUL.md for a new pet of [category]. All of the
  /// optional fields below substitute into placeholders in the template;
  /// when a value is null/empty AND the key is on the optional-strip
  /// list (variety, sex, neutered, working_role, rehab_context,
  /// care_context, dob_approx, adoption_date, intake_date,
  /// expected_release_date), the entire frontmatter line is removed
  /// from the rendered output per DECISIONS row 45 default-omitted rule.
  Future<String> seedSoulFor({
    required Category category,
    required String name,
    String? species,
    String? variety,
    String? breed,
    PetSex? sex,
    NeuteredStatus? neutered,
    Relationship? relationship,
    WorkingRole? workingRole,
    RehabContext? rehabContext,
    CareContext? careContext,
    DateTime? dob,
    String? dobApprox,
    DateTime? adoptionDate,
    DateTime? intakeDate,
    DateTime? expectedReleaseDate,
    double? weightKg,
    String? aboutPetPalShouldKnow,
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
    String? variety,
    String? breed,
    PetSex? sex,
    NeuteredStatus? neutered,
    Relationship? relationship,
    WorkingRole? workingRole,
    RehabContext? rehabContext,
    CareContext? careContext,
    DateTime? dob,
    String? dobApprox,
    DateTime? adoptionDate,
    DateTime? intakeDate,
    DateTime? expectedReleaseDate,
    double? weightKg,
    String? aboutPetPalShouldKnow,
  }) async {
    final raw = await rootBundle.loadString(
      'assets/onboarding/${category.id}.md',
    );
    return renderTemplate(
      raw,
      name: name,
      species: species,
      variety: variety,
      breed: breed,
      sex: sex,
      neutered: neutered,
      relationship: relationship,
      workingRole: workingRole,
      rehabContext: rehabContext,
      careContext: careContext,
      dob: dob,
      dobApprox: dobApprox,
      adoptionDate: adoptionDate,
      intakeDate: intakeDate,
      expectedReleaseDate: expectedReleaseDate,
      weightKg: weightKg,
      aboutPetPalShouldKnow: aboutPetPalShouldKnow,
    );
  }
}

/// Welcome-prose forks per relationship — VOICE.md §5.5 + 5.5.5 lock.
/// Pet reuses the category-specific welcome already in the template;
/// the other three replace it with relationship-specific framing
/// (clinical-respectful for rescue/rehab, dignified-of-purpose for
/// permanent wildlife, observer-naturalist for wildlife observation).
/// Each branch keeps the `{name}` placeholder so the standard
/// substitution pass below still hits.
const String _rescueRehabBody = '# {name}\n'
    '{name} is in your care while their next chapter takes shape. '
    'Track intake notes, medical milestones, and progress toward '
    'release or placement. Dates and observations travel with the '
    'animal — log carefully. The bond is real; the goal is the '
    'handoff.\n\n';

const String _permanentWildlifeBody = '# {name}\n'
    '{name} is a permanent resident — non-releasable, in your '
    'long-term care. Track diet, enclosure changes, behavior, and '
    'the slow patterns that come with years rather than weeks. '
    'PetPal accumulates a record worthy of the responsibility.\n\n';

const String _wildlifeObservationBody = '# {name}\n'
    '{name} is on your radar — an animal you watch, not one you '
    'keep. Log sightings, behaviors, seasonal patterns, and what '
    "the territory looks like through {name}'s presence. The "
    'record is the relationship.\n\n';

/// Body fork: when [r] is anything other than [Relationship.pet],
/// replace the segment from the template's first `# {name}` heading up
/// to the `{about_petpal_should_know}` placeholder with the
/// relationship-specific welcome. The `{name}` placeholder is
/// preserved for the standard substitution pass to fill in. Returns
/// [template] unchanged when [r] is null or pet.
String _applyBodyFork(String template, Relationship? r) {
  if (r == null || r == Relationship.pet) return template;
  final body = switch (r) {
    Relationship.pet => '', // unreachable — handled above
    Relationship.rescueRehab => _rescueRehabBody,
    Relationship.permanentWildlife => _permanentWildlifeBody,
    Relationship.wildlifeObservation => _wildlifeObservationBody,
  };
  // Match from `# {name}` up to (but not including) the
  // `{about_petpal_should_know}` placeholder — dotAll so the welcome
  // can span multiple lines. Templates without the placeholder still
  // get the swap (regex falls through to end-of-string).
  final swapper =
      RegExp(r'# \{name\}.*?(?=\{about_petpal_should_know\}|$)', dotAll: true);
  if (swapper.hasMatch(template)) {
    return template.replaceFirst(swapper, body);
  }
  return template;
}

/// Pure substitution + post-process strip. Replaces all of the `{key}`
/// placeholders in [template] with the provided values. After
/// substitution, any line matching `^<key>:\s*$` for an optional-strip
/// key is removed from the rendered output (DECISIONS row 45 default-
/// omitted rule).
///
/// When [relationship] is non-pet, the welcome paragraph is swapped
/// for a relationship-specific body **before** the substitution pass
/// — see [_applyBodyFork] + the four `_<...>Body` constants above.
///
/// Exposed at top level so tests and the in-memory implementation can
/// share the same renderer.
String renderTemplate(
  String template, {
  required String name,
  String? species,
  String? variety,
  String? breed,
  PetSex? sex,
  NeuteredStatus? neutered,
  Relationship? relationship,
  WorkingRole? workingRole,
  RehabContext? rehabContext,
  CareContext? careContext,
  DateTime? dob,
  String? dobApprox,
  DateTime? adoptionDate,
  DateTime? intakeDate,
  DateTime? expectedReleaseDate,
  double? weightKg,
  String? aboutPetPalShouldKnow,
}) {
  // Body fork happens BEFORE substitution so the relationship-specific
  // body still has live `{name}` / `{about_petpal_should_know}`
  // placeholders for the substitution pass to fill in.
  template = _applyBodyFork(template, relationship);
  String fmtDate(DateTime? d) => d == null
      ? ''
      : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  // Default-omitted: write empty when the user picked the default
  // (none/unknown) so the post-strip pass can remove the line.
  String roleId(WorkingRole? r) =>
      (r == null || r == WorkingRole.none) ? '' : r.id;
  String rehabId(RehabContext? r) =>
      (r == null || r == RehabContext.none) ? '' : r.id;
  String careId(CareContext? r) =>
      (r == null || r == CareContext.none) ? '' : r.id;
  String sexId(PetSex? s) =>
      (s == null || s == PetSex.unknown) ? '' : s.id;
  String neuteredId(NeuteredStatus? n) =>
      (n == null || n == NeuteredStatus.unknown) ? '' : n.id;

  String rendered = template
      .replaceAll('{species}', species ?? '')
      .replaceAll('{variety}', variety ?? '')
      .replaceAll('{breed}', breed ?? '')
      .replaceAll('{sex}', sexId(sex))
      .replaceAll('{neutered}', neuteredId(neutered))
      .replaceAll('{relationship}', relationship?.id ?? Relationship.pet.id)
      .replaceAll('{working_role}', roleId(workingRole))
      .replaceAll('{rehab_context}', rehabId(rehabContext))
      .replaceAll('{care_context}', careId(careContext))
      .replaceAll('{dob}', fmtDate(dob))
      .replaceAll('{dob_approx}', dobApprox ?? '')
      .replaceAll('{adoption_date}', fmtDate(adoptionDate))
      .replaceAll('{intake_date}', fmtDate(intakeDate))
      .replaceAll('{expected_release_date}', fmtDate(expectedReleaseDate))
      .replaceAll('{weight_kg}', weightKg == null ? '' : weightKg.toStringAsFixed(1))
      .replaceAll('{name}', name)
      .replaceAll(
        '{about_petpal_should_know}',
        aboutPetPalShouldKnow == null || aboutPetPalShouldKnow.trim().isEmpty
            ? ''
            : aboutPetPalShouldKnow.trim(),
      );

  // Strip empty-value lines for optional keys per DECISIONS row 45.
  // Each pattern matches a frontmatter line where the key has no value
  // (just a trailing space or nothing). Multi-line regex; remove the
  // entire line including its newline.
  const optionalKeys = [
    'variety',
    'sex',
    'neutered',
    'working_role',
    'rehab_context',
    'care_context',
    'dob',
    'dob_approx',
    'adoption_date',
    'intake_date',
    'expected_release_date',
  ];
  for (final key in optionalKeys) {
    rendered = rendered.replaceAll(
      RegExp('^$key:\\s*\\n', multiLine: true),
      '',
    );
  }

  // Body insertion of the "In your words" prose: the templates have a
  // `{about_petpal_should_know}` placeholder at the end of the welcome
  // prose. After substitution, if the user provided text, it sits as
  // a second paragraph. If empty, the placeholder rendered to nothing
  // and we strip any orphan blank line at that position.
  rendered = rendered.replaceAll(RegExp(r'\n\n\n+'), '\n\n');

  return rendered;
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
    String? variety,
    String? breed,
    PetSex? sex,
    NeuteredStatus? neutered,
    Relationship? relationship,
    WorkingRole? workingRole,
    RehabContext? rehabContext,
    CareContext? careContext,
    DateTime? dob,
    String? dobApprox,
    DateTime? adoptionDate,
    DateTime? intakeDate,
    DateTime? expectedReleaseDate,
    double? weightKg,
    String? aboutPetPalShouldKnow,
  }) async {
    final tpl = _templates[category] ??
        (throw StateError('no template for ${category.id}'));
    return renderTemplate(
      tpl,
      name: name,
      species: species,
      variety: variety,
      breed: breed,
      sex: sex,
      neutered: neutered,
      relationship: relationship,
      workingRole: workingRole,
      rehabContext: rehabContext,
      careContext: careContext,
      dob: dob,
      dobApprox: dobApprox,
      adoptionDate: adoptionDate,
      intakeDate: intakeDate,
      expectedReleaseDate: expectedReleaseDate,
      weightKg: weightKg,
      aboutPetPalShouldKnow: aboutPetPalShouldKnow,
    );
  }
}

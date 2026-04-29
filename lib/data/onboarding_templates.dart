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

/// Pure substitution + post-process strip. Replaces all of the `{key}`
/// placeholders in [template] with the provided values. After
/// substitution, any line matching `^<key>:\s*$` for an optional-strip
/// key is removed from the rendered output (DECISIONS row 45 default-
/// omitted rule).
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

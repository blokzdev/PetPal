import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/onboarding_templates.dart';
import 'package:petpal/data/relationship.dart';

/// Phase 5.5.4 / Commit A — invariants for the relationship + sub-
/// classification enums and the renderTemplate strip-empty pass that
/// turns "default" sub-classification picks into omitted frontmatter
/// lines per DECISIONS rows 44, 45, 47.
void main() {
  group('Relationship', () {
    test('all four ids are unique', () {
      final ids = Relationship.values.map((r) => r.id).toSet();
      expect(ids, hasLength(Relationship.values.length));
      expect(ids, {
        'pet',
        'rescue-rehab',
        'permanent-wildlife',
        'wildlife-observation',
      });
    });

    test('fromId round-trips every value', () {
      for (final r in Relationship.values) {
        expect(Relationship.fromId(r.id), r);
      }
    });

    test('fromId returns null on unknown / null', () {
      expect(Relationship.fromId(null), isNull);
      expect(Relationship.fromId('llm-pet-friend'), isNull);
    });

    test('every value has a non-empty user-facing label', () {
      for (final r in Relationship.values) {
        expect(r.label, isNotEmpty);
      }
    });
  });

  group('WorkingRole', () {
    test('locked at 7 values per DECISIONS row 47', () {
      expect(WorkingRole.values, hasLength(7));
    });
    test('ids are unique and lowercase', () {
      final ids = WorkingRole.values.map((r) => r.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        expect(id, equals(id.toLowerCase()));
      }
    });
    test('first value is the omitted-on-disk default', () {
      expect(WorkingRole.values.first, WorkingRole.none);
    });
  });

  group('RehabContext', () {
    test('locked at 9 values per DECISIONS row 47', () {
      expect(RehabContext.values, hasLength(9));
    });
    test('ids include conditioning + quarantine', () {
      final ids = RehabContext.values.map((r) => r.id).toSet();
      expect(ids, containsAll(['conditioning', 'quarantine']));
    });
    test('first value is the omitted-on-disk default', () {
      expect(RehabContext.values.first, RehabContext.none);
    });
  });

  group('CareContext', () {
    test('locked at 5 values per DECISIONS row 45', () {
      expect(CareContext.values, hasLength(5));
    });
    test('non-releasable id keeps the hyphen', () {
      expect(CareContext.nonReleasable.id, 'non-releasable');
    });
    test('first value is the omitted-on-disk default', () {
      expect(CareContext.values.first, CareContext.none);
    });
  });

  group('PetSex / NeuteredStatus', () {
    test('three-state, last is unknown (the omitted-on-disk default)', () {
      expect(PetSex.values.last, PetSex.unknown);
      expect(NeuteredStatus.values.last, NeuteredStatus.unknown);
    });
  });

  group('renderTemplate strip-empty for default sub-classifications', () {
    String tpl() => [
          '---',
          'category: dog',
          'sex: {sex}',
          'neutered: {neutered}',
          'relationship: {relationship}',
          'working_role: {working_role}',
          'rehab_context: {rehab_context}',
          'care_context: {care_context}',
          'dob: {dob}',
          'dob_approx: {dob_approx}',
          'adoption_date: {adoption_date}',
          'intake_date: {intake_date}',
          'expected_release_date: {expected_release_date}',
          '---',
          '# {name}',
          '',
        ].join('\n');

    test('all defaults / nulls collapse to a clean frontmatter', () {
      final out = renderTemplate(tpl(), name: 'Loki');
      expect(out, contains('category: dog'));
      expect(out, contains('relationship: pet'));
      expect(out, contains('# Loki'));
      // Default-omitted keys should not appear at all.
      for (final k in const [
        'sex',
        'neutered',
        'working_role',
        'rehab_context',
        'care_context',
        'dob_approx',
        'adoption_date',
        'intake_date',
        'expected_release_date',
      ]) {
        expect(out, isNot(contains('$k:')),
            reason: '$k must be omitted when the user picked the default');
      }
    });

    test('non-default sub-classification persists to disk', () {
      final out = renderTemplate(
        tpl(),
        name: 'Service',
        sex: PetSex.male,
        neutered: NeuteredStatus.yes,
        relationship: Relationship.pet,
        workingRole: WorkingRole.service,
      );
      expect(out, contains('sex: male'));
      expect(out, contains('neutered: yes'));
      expect(out, contains('working_role: service'));
      // Untouched fields still strip.
      expect(out, isNot(contains('rehab_context:')));
      expect(out, isNot(contains('care_context:')));
    });

    test('rescue-rehab fields persist when supplied', () {
      final out = renderTemplate(
        tpl(),
        name: 'Patch',
        relationship: Relationship.rescueRehab,
        rehabContext: RehabContext.conditioning,
        intakeDate: DateTime(2026, 4, 3),
        expectedReleaseDate: DateTime(2026, 6, 17),
      );
      expect(out, contains('relationship: rescue-rehab'));
      expect(out, contains('rehab_context: conditioning'));
      expect(out, contains('intake_date: 2026-04-03'));
      expect(out, contains('expected_release_date: 2026-06-17'));
    });

    test('about_petpal_should_know substitutes when provided', () {
      const body = 'Body: {about_petpal_should_know}';
      final out = renderTemplate(
        body,
        name: 'Loki',
        aboutPetPalShouldKnow: '  Loves frozen carrots.  ',
      );
      expect(out, 'Body: Loves frozen carrots.');
    });

    test('about_petpal_should_know empty does not leave triple-newlines', () {
      const body = 'Top.\n\n{about_petpal_should_know}\n';
      final out = renderTemplate(body, name: 'Loki');
      expect(out, isNot(contains('\n\n\n')));
    });
  });
}

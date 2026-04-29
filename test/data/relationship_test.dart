import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/onboarding_templates.dart';
import 'package:petpal/data/relationship.dart';
import 'package:petpal/data/soul_file.dart';

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

  group('renderTemplate weight + lifecycle dates (Commit B)', () {
    String tpl() => [
          '---',
          'category: dog',
          'dob: {dob}',
          'dob_approx: {dob_approx}',
          'adoption_date: {adoption_date}',
          'weight_kg: {weight_kg}',
          '---',
          '# {name}',
          '',
        ].join('\n');

    test('DOB substitutes; the other two strip', () {
      final out = renderTemplate(
        tpl(),
        name: 'Loki',
        dob: DateTime(2022, 6, 12),
      );
      expect(out, contains('dob: 2022-06-12'));
      expect(out, isNot(contains('dob_approx:')));
      expect(out, isNot(contains('adoption_date:')));
    });

    test('approxAge substitutes; dob + adoption_date strip', () {
      final out = renderTemplate(
        tpl(),
        name: 'Loki',
        dobApprox: 'about 3 years',
      );
      expect(out, contains('dob_approx: about 3 years'));
      expect(out, isNot(contains(RegExp(r'^dob:', multiLine: true))));
      expect(out, isNot(contains('adoption_date:')));
    });

    test('weight_kg renders to one decimal when supplied; stays empty '
        'on disk when omitted (treated as "unknown" by the harness, '
        'matching the legacy weight_g: / tank_litres: hint pattern)', () {
      final withWeight = renderTemplate(
        tpl(),
        name: 'Loki',
        weightKg: 12.345,
      );
      expect(withWeight, contains('weight_kg: 12.3'));

      final without = renderTemplate(tpl(), name: 'Loki');
      expect(without, isNot(contains(RegExp(r'weight_kg: \d'))));
      expect(without, contains('weight_kg:'));
    });
  });

  group('5.5.5 body fork on relationship (VOICE.md §5.5)', () {
    String tpl() => '---\n'
        'category: dog\n'
        'relationship: {relationship}\n'
        '---\n'
        '\n'
        '# {name}\n'
        '{name} is a dog. Tell PetPal about {name}. The journal grows.\n'
        '\n'
        '{about_petpal_should_know}\n';

    test('pet leaves the existing welcome prose intact', () {
      final out = renderTemplate(
        tpl(),
        name: 'Loki',
        relationship: Relationship.pet,
      );
      // The category-specific welcome survives.
      expect(out, contains('Loki is a dog.'));
      expect(out, contains('The journal grows.'));
      // None of the alt-relationship anchors appear.
      expect(out, isNot(contains('next chapter takes shape')));
      expect(out, isNot(contains('permanent resident')));
      expect(out, isNot(contains('on your radar')));
    });

    test('rescueRehab swaps to the rehab welcome (clinical-respectful, '
        'progress-toward-outcome register)', () {
      final out = renderTemplate(
        tpl(),
        name: 'Patch',
        relationship: Relationship.rescueRehab,
      );
      // Rehab-specific opening + progress framing + handoff aphorism.
      expect(out, contains('Patch is in your care while their next '
          'chapter takes shape.'));
      expect(out, contains('progress toward release or placement'));
      expect(out, contains('the goal is the handoff'));
      // Pet welcome is gone.
      expect(out, isNot(contains('is a dog.')));
      expect(out, isNot(contains('The journal grows.')));
      // {name} substitution still happened.
      expect(out, isNot(contains('{name}')));
      // about_petpal_should_know placeholder still survives the swap
      // and gets emptied because no value was supplied.
      expect(out, isNot(contains('{about_petpal_should_know}')));
    });

    test('permanentWildlife swaps to the long-term-care welcome '
        '(dignified-of-purpose register)', () {
      final out = renderTemplate(
        tpl(),
        name: 'Hawk',
        relationship: Relationship.permanentWildlife,
      );
      expect(out, contains('Hawk is a permanent resident — '
          'non-releasable, in your long-term care.'));
      expect(out, contains('slow patterns that come with years '
          'rather than weeks'));
      expect(out, contains('a record worthy of the responsibility'));
      expect(out, isNot(contains('next chapter takes shape')));
      expect(out, isNot(contains('on your radar')));
    });

    test('wildlifeObservation swaps to the observer-naturalist welcome '
        '(documentary register)', () {
      final out = renderTemplate(
        tpl(),
        name: 'Vixen',
        relationship: Relationship.wildlifeObservation,
      );
      expect(out, contains('Vixen is on your radar — an animal you '
          'watch, not one you keep.'));
      expect(out, contains("through Vixen's presence"));
      expect(out, contains('The record is the relationship.'));
      expect(out, isNot(contains('a permanent resident')));
      expect(out, isNot(contains('next chapter takes shape')));
    });

    test('aboutPetPalShouldKnow still substitutes after a body fork', () {
      final out = renderTemplate(
        tpl(),
        name: 'Patch',
        relationship: Relationship.rescueRehab,
        aboutPetPalShouldKnow: 'Came in dehydrated; on fluids.',
      );
      expect(out, contains('the goal is the handoff'));
      expect(out, contains('Came in dehydrated; on fluids.'));
    });

    test('voice differentiation: each non-pet body opens with its own '
        'locked anchor phrase (regression guard against the bodies '
        'drifting toward each other on future edits)', () {
      String body(Relationship r) => renderTemplate(
            tpl(),
            name: 'Subject',
            relationship: r,
          );
      final rehab = body(Relationship.rescueRehab);
      final permWild = body(Relationship.permanentWildlife);
      final obs = body(Relationship.wildlifeObservation);

      // Each anchor appears exactly in one of the three bodies.
      const anchors = {
        'next chapter takes shape': 'rehab',
        'permanent resident': 'permanent wildlife',
        'on your radar': 'observation',
      };
      for (final entry in anchors.entries) {
        final hits = [rehab, permWild, obs]
            .where((b) => b.contains(entry.key))
            .length;
        expect(hits, 1,
            reason: '${entry.key} (${entry.value}) should appear in '
                'exactly one body — got $hits hits.');
      }
    });
  });

  group('5.5.5 SOUL keyOrder canonical shape (DECISIONS row 45)', () {
    test('serializeSoul emits the new identity / classification / '
        'lifecycle blocks in the canonical order', () {
      // Helper: index of `<key>:` (start-of-line). Returns -1 if absent.
      int idx(String emitted, String key) {
        final m = RegExp('^$key:', multiLine: true).firstMatch(emitted);
        return m?.start ?? -1;
      }

      final out = serializeSoul(
        frontmatter: {
          // Deliberately scrambled insertion order; serializeSoul must
          // re-emit per the canonical key order regardless.
          'temperament': const ['anxious'],
          'expected_release_date': '2026-06-01',
          'rehab_context': 'medical',
          'sex': 'female',
          'relationship': 'rescue-rehab',
          'breed': 'mixed',
          'category': 'dog',
          'species': 'Domestic Dog',
          'variety': 'mutt',
          'neutered': 'yes',
          'working_role': '',
          'care_context': '',
          'dob': '2022-06-12',
          'dob_approx': '',
          'adoption_date': '',
          'intake_date': '2026-04-01',
          'weight_kg': 14.2,
          'allergies': const ['chicken'],
          'meds': const [],
          'vet_contact': 'Dr. Patel',
          'extension_key': 'still trails',
        },
        body: '\n# Loki\n',
      );

      // Identity block: category < species < variety < breed.
      expect(idx(out, 'category'), greaterThanOrEqualTo(0));
      expect(idx(out, 'category'), lessThan(idx(out, 'species')));
      expect(idx(out, 'species'), lessThan(idx(out, 'variety')));
      expect(idx(out, 'variety'), lessThan(idx(out, 'breed')));

      // Classification: sex < neutered < relationship < working_role <
      // rehab_context < care_context.
      expect(idx(out, 'breed'), lessThan(idx(out, 'sex')));
      expect(idx(out, 'sex'), lessThan(idx(out, 'neutered')));
      expect(idx(out, 'neutered'), lessThan(idx(out, 'relationship')));
      expect(idx(out, 'relationship'), lessThan(idx(out, 'working_role')));
      expect(idx(out, 'working_role'), lessThan(idx(out, 'rehab_context')));
      expect(idx(out, 'rehab_context'), lessThan(idx(out, 'care_context')));

      // Lifecycle dates: dob < dob_approx < adoption_date <
      // intake_date < expected_release_date < weight_kg.
      expect(idx(out, 'care_context'), lessThan(idx(out, 'dob')));
      expect(idx(out, 'dob'), lessThan(idx(out, 'dob_approx')));
      expect(idx(out, 'dob_approx'), lessThan(idx(out, 'adoption_date')));
      expect(idx(out, 'adoption_date'), lessThan(idx(out, 'intake_date')));
      expect(
        idx(out, 'intake_date'),
        lessThan(idx(out, 'expected_release_date')),
      );
      expect(
        idx(out, 'expected_release_date'),
        lessThan(idx(out, 'weight_kg')),
      );

      // Trailing block survives in canonical position; extension keys
      // trail by virtue of falling outside keyOrder.
      expect(idx(out, 'weight_kg'), lessThan(idx(out, 'allergies')));
      expect(idx(out, 'temperament'), lessThan(idx(out, 'extension_key')));
    });
  });
}

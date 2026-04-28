import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/onboarding_templates.dart';
import 'package:petpal/harness/scheduling/reminder_kinds.dart';

void main() {
  group('ReminderKind', () {
    test('id round-trips through fromId for every value', () {
      for (final k in ReminderKind.values) {
        expect(ReminderKind.fromId(k.id), k);
      }
    });

    test('fromId returns null for unknown', () {
      expect(ReminderKind.fromId('something_else'), isNull);
    });

    test('every kind has a non-empty label', () {
      for (final k in ReminderKind.values) {
        expect(k.label, isNotEmpty);
      }
    });
  });

  group('defaultCadenceFor — locked dog/cat assumptions', () {
    test('flea, heartworm, vaccine, weight cadences for dog match the lock', () {
      expect(
        defaultCadenceFor(
            kind: ReminderKind.fleaTreatment, category: Category.dog),
        const Duration(days: 30),
      );
      expect(
        defaultCadenceFor(
            kind: ReminderKind.heartwormDose, category: Category.dog),
        const Duration(days: 30),
      );
      expect(
        defaultCadenceFor(
            kind: ReminderKind.vaccineDue, category: Category.dog),
        const Duration(days: 365),
      );
      expect(
        defaultCadenceFor(
            kind: ReminderKind.weightCheck, category: Category.dog),
        const Duration(days: 14),
      );
    });

    test('cat uses the same defaults as dog', () {
      for (final k in ReminderKind.values) {
        expect(
          defaultCadenceFor(kind: k, category: Category.cat),
          defaultCadenceFor(kind: k, category: Category.dog),
          reason: k.id,
        );
      }
    });

    test('rabbit and small-mammal use the canonical defaults', () {
      expect(
        defaultCadenceFor(
            kind: ReminderKind.fleaTreatment, category: Category.rabbit),
        const Duration(days: 30),
      );
      expect(
        defaultCadenceFor(
            kind: ReminderKind.weightCheck, category: Category.smallMammal),
        const Duration(days: 14),
      );
    });
  });

  group('defaultCadenceFor — locked no-default species', () {
    test('bird/reptile/fish/exotic return null for every kind', () {
      const noDefault = [
        Category.bird,
        Category.reptile,
        Category.fish,
        Category.exotic,
      ];
      for (final s in noDefault) {
        for (final k in ReminderKind.values) {
          expect(
            defaultCadenceFor(kind: k, category: s),
            isNull,
            reason: 'kind=${k.id} species=${s.id}',
          );
        }
      }
    });
  });

  test('vaccineUiNote is non-empty and direct, not alarmist', () {
    // VOICE.md tone — do not assert exact string, but enforce shape:
    // present-tense, factual, non-imperative scare wording.
    expect(vaccineUiNote, isNotEmpty);
    expect(vaccineUiNote.toLowerCase(), contains('vet'));
    expect(vaccineUiNote.toLowerCase(), isNot(contains('warning')));
    expect(vaccineUiNote.toLowerCase(), isNot(contains('danger')));
  });
}

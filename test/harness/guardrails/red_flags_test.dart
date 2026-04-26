import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/guardrails/red_flags.dart';

/// Smoke coverage for the red-flag pattern table — one canonical
/// positive per category to confirm regex compilation and basic match.
/// The full ≥30 positive + ≥20 negative fixture (CLAUDE.md §10
/// coverage rule) lives in `red_flags_fixture_test.dart`, written in
/// task 4.11.
void main() {
  group('redFlagPatterns', () {
    test('contains all 11 canonical categories from CLAUDE.md §10', () {
      final ids = redFlagPatterns.map((p) => p.id).toList();
      expect(ids, containsAll(const [
        'blood_in_stool',
        'blood_in_vomit',
        'repeat_vomit',
        'seizure',
        'bloat',
        'pale_gums',
        'toxin_ingestion',
        'dyspnea',
        'collapse',
        'trauma_fracture',
        'lethargy_anorexia',
      ]));
      expect(ids.toSet().length, ids.length, reason: 'ids must be unique');
    });

    test('every pattern is severity=urgent for Phase 4', () {
      for (final p in redFlagPatterns) {
        expect(p.severity, RedFlagSeverity.urgent, reason: p.id);
      }
    });

    test('every pattern has either triggers or all (never both empty)', () {
      for (final p in redFlagPatterns) {
        final hasTriggers = p.triggers.isNotEmpty;
        final hasAll = p.all != null && p.all!.isNotEmpty;
        expect(hasTriggers || hasAll, isTrue, reason: p.id);
      }
    });

    test('every pattern carries a non-empty aiSummary', () {
      for (final p in redFlagPatterns) {
        expect(p.aiSummary, isNotEmpty, reason: p.id);
      }
    });
  });

  // Canonical positive case per category. These are the seed fixtures
  // that must match across the lifetime of the table — task 4.11
  // expands coverage to ≥30 positives per category.
  group('canonical positives match', () {
    final canonicals = <String, List<String>>{
      'blood_in_stool': [
        'I noticed blood in his stool this morning',
        'bloody diarrhea twice today',
        'his stool is black',
      ],
      'blood_in_vomit': [
        'there was blood in his vomit',
        'she vomited blood last night',
        'threw up blood',
      ],
      'repeat_vomit': [
        'vomited 5 times today',
        'throwing up several times',
        "he can't stop vomiting",
        'keeps throwing up all morning',
      ],
      'seizure': [
        'Loki had a seizure',
        'she was seizing for about a minute',
        'a convulsion just now',
      ],
      'bloat': [
        'his belly looks distended',
        'her abdomen is bloated and hard',
        'possible GDV',
      ],
      'pale_gums': [
        'his gums are pale',
        'her gums look white',
        'blue gums',
      ],
      'toxin_ingestion': [
        'he ate chocolate',
        'she got into the trash',
        'swallowed a battery',
        'drank antifreeze',
      ],
      'dyspnea': [
        'laboured breathing',
        "she can't breathe",
        'open-mouth breathing',
        'gasping for air',
      ],
      'collapse': [
        'he collapsed in the yard',
        'passed out for a few seconds',
        'unresponsive',
      ],
      'trauma_fracture': [
        "he won't put weight on his back leg",
        'hit by a car',
        'broken paw',
        'fell from the balcony',
      ],
    };

    canonicals.forEach((id, phrases) {
      test('$id matches canonical phrasings', () {
        final pattern = redFlagPatterns.firstWhere((p) => p.id == id);
        for (final phrase in phrases) {
          expect(pattern.matches(phrase), isTrue, reason: '"$phrase"');
        }
      });
    });

    test('lethargy_anorexia (multi-symptom AND) needs both signals', () {
      final pattern =
          redFlagPatterns.firstWhere((p) => p.id == 'lethargy_anorexia');
      // Both present → match.
      expect(
        pattern.matches("Loki seems lethargic and won't eat anything"),
        isTrue,
      );
      expect(
        pattern.matches('she is listless and refusing food'),
        isTrue,
      );
      // Only lethargy → no match.
      expect(pattern.matches('Loki is a bit lethargic today'), isFalse);
      // Only anorexia → no match.
      expect(pattern.matches("she won't eat her dinner"), isFalse);
    });
  });

  // Spot-checks for the false-positive-tolerant principle — these are
  // textually similar phrasings that must NOT match. Full negative
  // fixture lives in task 4.11.
  group('canonical negatives do not match', () {
    test('"chocolate-coloured fur trim" is not toxin_ingestion', () {
      final pattern =
          redFlagPatterns.firstWhere((p) => p.id == 'toxin_ingestion');
      expect(
        pattern.matches('Loki had a great chocolate-coloured fur trim today'),
        isFalse,
      );
    });

    test('"vomited once after eating grass" is not repeat_vomit', () {
      final pattern =
          redFlagPatterns.firstWhere((p) => p.id == 'repeat_vomit');
      expect(
        pattern.matches('vomited once after eating grass'),
        isFalse,
      );
    });

    test('"pink gums" is not pale_gums', () {
      final pattern = redFlagPatterns.firstWhere((p) => p.id == 'pale_gums');
      expect(pattern.matches('her gums look pink and healthy'), isFalse);
    });

    test('"broke into the treat jar" is not trauma_fracture', () {
      final pattern =
          redFlagPatterns.firstWhere((p) => p.id == 'trauma_fracture');
      expect(pattern.matches('he broke into the treat jar again'), isFalse);
    });
  });
}

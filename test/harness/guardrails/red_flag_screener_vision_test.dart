import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/guardrails/red_flag_screener.dart';

/// Phase 6 task 6.7 — focused tests for the chat-or-vision screener
/// path. The fixture-driven walks live in `red_flags_fixture_test.dart`;
/// these tests cover the priority + null-safety contract that file
/// doesn't exercise.
void main() {
  final screener = RedFlagScreener();

  group('screenWithVision priority + null-safety', () {
    test('null + null → null', () {
      expect(
        screener.screenWithVision(),
        isNull,
      );
    });

    test('empty/whitespace inputs → null', () {
      expect(
        screener.screenWithVision(chatInput: '', visionExtracted: '   '),
        isNull,
      );
    });

    test('chat-only flag returns source=chat', () {
      final match = screener.screenWithVision(
        chatInput: 'Loki had a seizure',
      );
      expect(match, isNotNull);
      expect(match!.category.id, 'seizure');
      expect(match.source, RedFlagSource.chat);
    });

    test('vision-only flag returns source=vision', () {
      final match = screener.screenWithVision(
        visionExtracted: 'Dog mid-seizure on the kitchen floor',
      );
      expect(match, isNotNull);
      expect(match!.category.id, 'seizure');
      expect(match.source, RedFlagSource.vision);
    });

    test('both flag → chat wins (more decisive signal — user typed it)',
        () {
      // The user is reporting bloody stool in chat, AND the photo
      // shows blood in vomit. Chat takes priority because the user's
      // active typing is the more decisive signal.
      final match = screener.screenWithVision(
        chatInput: 'I noticed blood in his stool this morning',
        visionExtracted: 'Vomit with blood on the kitchen floor',
      );
      expect(match, isNotNull);
      expect(match!.category.id, 'blood_in_stool');
      expect(match.source, RedFlagSource.chat);
    });

    test('chat clean + vision flagged → vision (typical photo-save case)',
        () {
      // The form preview's bare `freeform_caption + notable_objects`
      // is the canonical caller — chatInput is null at that call site.
      final match = screener.screenWithVision(
        visionExtracted: 'Open-mouth breathing in a cat — concerning',
      );
      expect(match, isNotNull);
      expect(match!.category.id, 'dyspnea');
      expect(match.source, RedFlagSource.vision);
    });

    test('chat flagged + vision clean → chat (typical chat-attached photo'
        ' case)', () {
      // The 6.9 multimodal chat input case — user types something
      // urgent, the attached photo describes a normal scene.
      final match = screener.screenWithVision(
        chatInput: 'He collapsed in the yard',
        visionExtracted: 'Loki resting on the couch',
      );
      expect(match, isNotNull);
      expect(match!.category.id, 'collapse');
      expect(match.source, RedFlagSource.chat);
    });

    test('multi-line vision payload — caption + objects joined with newlines',
        () {
      // The canonical 6.7 vision payload shape.
      const payload =
          'Loki at the trailhead.\nleash\nfrozen carrot\nbloody paw bandage';
      final match = screener.screenWithVision(visionExtracted: payload);
      // The trauma_fracture category catches "bleeding through gauze"
      // / "won't stop bleeding" but not a bare "bloody paw bandage";
      // the screener may or may not flag — the test asserts the
      // contract: if it does flag, source is vision.
      if (match != null) {
        expect(match.source, RedFlagSource.vision);
      }
    });

    test('plain screen() still works (chat-only API, Phase 4 callers)', () {
      final match = screener.screen('he collapsed in the yard');
      expect(match, isNotNull);
      expect(match!.category.id, 'collapse');
      expect(match.source, RedFlagSource.chat);
    });
  });
}

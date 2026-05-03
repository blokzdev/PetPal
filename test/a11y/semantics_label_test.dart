import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 7 task H.2.b — every interactive control must announce a
/// label to TalkBack. The Play Console pre-launch scanner asserts the
/// same invariant; landing this in unit tests catches regressions
/// before they reach the AAB-build moment.
///
/// **Source-presence assertions** for label edits where pumping the
/// live widget would require heavyweight setup (private-class
/// composers, full Drift + scripted-LLM scaffolding). These read the
/// source file and assert the expected token is still at the call
/// site. Brittle to refactors that rename the file or move the call
/// site, but precisely the right shape for catching "someone removed
/// the tooltip during a routine edit." A future edit that strips the
/// label turns the test red on the next `flutter test` run, not at
/// the AAB-build moment.
///
/// Live `Semantics` tree assertions are deferred to the TalkBack
/// manual verification gate (CLAUDE.md §14) — `tester.getSemantics`
/// + flag introspection has Flutter-version churn that would make
/// these tests fragile.
void main() {
  group('Pass A — Semantics labels at call sites', () {
    test('chat composer send button declares a tooltip', () {
      final src = File('lib/app/screens/chat_screen.dart').readAsStringSync();
      // The send `IconButton.filled` lives at one site; the tooltip
      // string is 'Send' at rest, 'Sending…' while a turn is in flight.
      expect(
        src.contains("tooltip: sending ? 'Sending…' : 'Send'"),
        isTrue,
        reason: 'chat send button missing tooltip — Phase 7 H.2.b regression',
      );
    });

    test('onboarding brand image declares a semantic label', () {
      final src =
          File('lib/app/screens/onboarding_screen.dart').readAsStringSync();
      expect(
        src.contains("semanticLabel: 'PetPal'"),
        isTrue,
        reason:
            'onboarding hero Image.asset missing semanticLabel — '
            'Phase 7 H.2.b regression',
      );
    });

    test('pet switcher InkWell wraps Semantics(button: true, hint: …)', () {
      final src = File('lib/app/widgets/pet_switcher.dart').readAsStringSync();
      // The multi-pet title path wraps the InkWell in a
      // `Semantics(button: true, label: title, hint: 'Switch pet',
      // excludeSemantics: true)` so TalkBack reads "Loki, button,
      // Switch pet" instead of bare "Loki" with no hint that the
      // tap surfaces a sheet.
      expect(
        src.contains('button: true'),
        isTrue,
        reason: 'pet_switcher InkWell missing Semantics(button: true) wrap',
      );
      expect(
        src.contains("hint: 'Switch pet'"),
        isTrue,
        reason: 'pet_switcher InkWell missing the "Switch pet" hint',
      );
      expect(
        src.contains('excludeSemantics: true'),
        isTrue,
        reason:
            'pet_switcher Semantics wrap should excludeSemantics so the '
            'inner Text + chevron Icon collapse to a single TalkBack node',
      );
    });
  });
}

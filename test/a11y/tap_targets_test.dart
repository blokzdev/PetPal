import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 7 task H.2.b — every interactive control must meet the
/// 48×48 dp Android tap-target floor (Material guideline + Play
/// Console pre-launch scanner check).
///
/// The audit found one confirmed regression — the "Compare plans"
/// inline link inside the pet-quota error block on `add_pet_screen`
/// stripped its tap padding via `minimumSize: Size.zero +
/// MaterialTapTargetSize.shrinkWrap`. The fix restores the default
/// (`MaterialTapTargetSize.padded`) which guarantees a 48dp hit
/// rect regardless of label width.
///
/// This test is a source-presence regression lock: the offending
/// pattern must not reappear at the call site. A future "while I'm
/// here" cleanup that re-adds `Size.zero` to tighten the layout will
/// turn the test red on the next `flutter test` run.
///
/// **What this test does NOT cover** (intentional):
///
/// - Decorative `Chip`s with `VisualDensity.compact` like the chat
///   tool-pill at `chat_screen.dart:431`. These have no `onPressed`
///   and so are not interactive controls; the 48dp floor only applies
///   to tap targets.
/// - Per-screen `meetsGuideline(androidTapTargetGuideline)` sweeps —
///   live integration_test/ harness would catch sub-48dp targets
///   programmatically. Out of unit-test scope; lives in TalkBack
///   manual verification (CLAUDE.md §14).
void main() {
  group('Pass D — touch-target regressions', () {
    test('add_pet_screen Compare-plans link no longer strips tap padding',
        () {
      final src =
          File('lib/app/screens/add_pet_screen.dart').readAsStringSync();
      // The original regression — three-line pattern that drops the
      // button below 48dp. Each line independently signals the issue;
      // any one reappearing means the link is sub-48dp again.
      expect(
        src.contains('minimumSize: Size.zero'),
        isFalse,
        reason:
            'add_pet_screen reintroduced `Size.zero` minimumSize — '
            'sub-48dp tap target, Phase 7 H.2.b regression',
      );
      expect(
        src.contains('MaterialTapTargetSize.shrinkWrap'),
        isFalse,
        reason:
            'add_pet_screen reintroduced `tapTargetSize.shrinkWrap` — '
            'sub-48dp tap target, Phase 7 H.2.b regression',
      );
    });
  });
}

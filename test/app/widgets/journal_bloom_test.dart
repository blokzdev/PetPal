import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/app/widgets/journal_bloom.dart';

/// Task 5.9 — JournalBloom invariants. The bloom is a single-shot
/// rise + fade that fires `onComplete` when its AnimationController
/// hits AnimationStatus.completed. The chat surface relies on
/// onComplete to clear its `_activeBloomId` slot so a subsequent
/// save can mount a fresh bloom.
Widget _wrap(Widget child) => MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('renders a journal-book icon while animating',
      (tester) async {
    await tester.pumpWidget(_wrap(JournalBloom(onComplete: () {})));
    // First frame — opacity is at the start of the tween (0). The
    // icon is nonetheless mounted; it just isn't yet visible.
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    // Tear down the animation so the test exits cleanly.
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
  });

  testWidgets('fires onComplete exactly once when the controller settles',
      (tester) async {
    var completedCount = 0;
    await tester.pumpWidget(_wrap(
      JournalBloom(onComplete: () => completedCount++),
    ));
    expect(completedCount, 0,
        reason: 'onComplete must not fire on mount');
    // Run the full Motion.long (500ms) animation.
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(completedCount, 1,
        reason: 'onComplete fires once when AnimationStatus.completed');
  });

  testWidgets('two successive blooms each fire onComplete '
      '(parent re-mounts via key)', (tester) async {
    var completedCount = 0;

    await tester.pumpWidget(_wrap(
      JournalBloom(
        key: const ValueKey('bloom-1'),
        onComplete: () => completedCount++,
      ),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(completedCount, 1);

    await tester.pumpWidget(_wrap(
      JournalBloom(
        key: const ValueKey('bloom-2'),
        onComplete: () => completedCount++,
      ),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(completedCount, 2,
        reason: 'a second mount must run its own animation cycle');
  });

  testWidgets('is non-interactive so it never absorbs taps on whatever '
      'it overlays', (tester) async {
    await tester.pumpWidget(_wrap(JournalBloom(onComplete: () {})));
    // The bloom's own IgnorePointer must wrap the icon. Other
    // IgnorePointers exist further up Material's tree (Scaffold +
    // AppBar machinery); restrict the search to descendants of the
    // JournalBloom subtree.
    final ignorePointers = find.descendant(
      of: find.byType(JournalBloom),
      matching: find.byType(IgnorePointer),
    );
    expect(ignorePointers, findsOneWidget);
    expect(
      tester.widget<IgnorePointer>(ignorePointers).ignoring,
      isTrue,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
  });
}

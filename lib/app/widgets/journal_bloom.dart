import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design.dart';

/// Bubble→journal bloom (task 5.9, user-locked design pick). When
/// `write_wiki_entry` succeeds in the chat surface, a single instance
/// of this widget overlays the chat thread's bottom edge — visually
/// the spot where the most-recent assistant bubble lives — and runs
/// a one-shot rise + fade animation. The icon is
/// `PhosphorIconsRegular.bookOpen`, which echoes the journal-empty
/// state and the home greeting's journal motif so the bloom reads as
/// "the agent just placed something into the book."
///
/// Phase 5.6 Commit C — rewritten to use `flutter_animate`'s
/// declarative chain instead of a manual `AnimationController` +
/// `TweenSequence`. Same choreography (Motion.long = 500 ms total),
/// less ceremony. The chain:
///
/// - fadeIn over 30%   (0–150 ms): opacity 0 → 1.
/// - then 30%          (150–300 ms): hold at full opacity while
///                                  slideY drives dy 0 → -24.
/// - fadeOut over 40%  (300–500 ms): opacity 1 → 0; slideY continues.
///
/// `flutter_animate` calls `onComplete` when the chain finishes, so
/// the chat surface can null out its bloom slot. Spring curve from
/// `Motion.springCurve` drives the slide for the soft "settles in"
/// quality the user-locked design called for. Pairs with the
/// lightImpact haptic from 5.8 — by the time the icon is visible,
/// the user has already felt the buzz, so the visual lands as
/// confirmation, not anticipation.
class JournalBloom extends StatelessWidget {
  const JournalBloom({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Icon(
        PhosphorIconsRegular.bookOpen,
        size: 28,
        color: scheme.primary,
      )
          .animate(
            onComplete: (_) => onComplete(),
          )
          .fadeIn(duration: 150.ms, curve: Motion.standardCurve)
          .then(delay: 150.ms)
          .moveY(
            begin: 0,
            end: -24,
            duration: 350.ms,
            curve: Motion.springCurve,
          )
          .fadeOut(
            duration: 200.ms,
            delay: 150.ms,
            curve: Motion.standardCurve,
          ),
    );
  }
}

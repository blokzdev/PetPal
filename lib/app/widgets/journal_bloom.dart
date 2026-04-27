import 'package:flutter/material.dart';

import '../design/design.dart';

/// Bubble→journal bloom (task 5.9, user-locked design pick). When
/// `write_wiki_entry` succeeds in the chat surface, a single instance
/// of this widget overlays the chat thread's bottom edge — visually
/// the spot where the most-recent assistant bubble lives — and runs
/// a one-shot rise + fade animation. The icon is
/// `Icons.menu_book_outlined`, which echoes the 5.7 journal-empty
/// icon and the 5.10 (planned) home greeting's journal motif so the
/// bloom reads as "the agent just placed something into the book."
///
/// Choreography (Motion.long = 500 ms):
///
/// - 0–30%   icon fades 0 → 1, position dy 0
/// - 30–60%  icon holds at full opacity, dy easing 0 → -24
/// - 60–100% icon fades 1 → 0, dy continues to -24
///
/// The single AnimationController drives all three phases via
/// staggered intervals; on dismiss, [onComplete] fires so the parent
/// can null out its bloom slot. The widget self-disposes its
/// controller. Pairs with the lightImpact haptic from 5.8 — by the
/// time the icon is visible, the user has already felt the buzz, so
/// the visual lands as confirmation, not anticipation.
class JournalBloom extends StatefulWidget {
  const JournalBloom({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<JournalBloom> createState() => _JournalBloomState();
}

class _JournalBloomState extends State<JournalBloom>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _dy;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.long);
    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(
          CurveTween(curve: Motion.standardCurve),
        ),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(
          CurveTween(curve: Motion.standardCurve),
        ),
        weight: 40,
      ),
    ]).animate(_controller);
    _dy = Tween<double>(begin: 0.0, end: -24.0).animate(
      CurvedAnimation(parent: _controller, curve: Motion.heroCurve),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onComplete();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return IgnorePointer(
          child: Transform.translate(
            offset: Offset(0, _dy.value),
            child: Opacity(
              opacity: _opacity.value,
              child: Icon(
                Icons.menu_book_outlined,
                size: 28,
                color: scheme.primary,
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../design/design.dart';

/// Loading skeleton primitive — subtle pulse animation (DECISIONS row 38
/// follow-up). Skeleton bars pulse opacity smoothly between ~80% and
/// ~100% over ~1.5 s, no horizontal motion. Reads as "calmly waiting"
/// rather than the more visually-active sliding-shimmer alternative,
/// pairing better with the soft-modern palette and companion-app voice.
///
/// Three primitive shapes, all sharing the same pulse:
///
/// - [PetSkeleton.line]      — single text-line placeholder (height 14)
/// - [PetSkeleton.rectangle] — arbitrary rect (cards, images)
/// - [PetSkeleton.circle]    — avatars and icon-shaped placeholders
class PetSkeleton extends StatefulWidget {
  const PetSkeleton.line({
    super.key,
    this.width,
    this.height = 14,
  })  : _shape = _SkeletonShape.line,
        _diameter = null;

  const PetSkeleton.rectangle({
    super.key,
    required this.width,
    required this.height,
  })  : _shape = _SkeletonShape.rectangle,
        _diameter = null;

  const PetSkeleton.circle({
    super.key,
    required double diameter,
  })  : _shape = _SkeletonShape.circle,
        width = diameter,
        height = diameter,
        _diameter = diameter;

  final double? width;
  final double height;
  final double? _diameter;
  final _SkeletonShape _shape;

  @override
  State<PetSkeleton> createState() => _PetSkeletonState();
}

enum _SkeletonShape { line, rectangle, circle }

class _PetSkeletonState extends State<PetSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.55, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
      animation: _opacity,
      builder: (context, _) {
        final base = scheme.surfaceContainerHigh;
        final color = Color.lerp(
          scheme.surfaceContainer,
          base,
          _opacity.value,
        )!;
        switch (widget._shape) {
          case _SkeletonShape.circle:
            return Container(
              width: widget._diameter,
              height: widget._diameter,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            );
          case _SkeletonShape.line:
          case _SkeletonShape.rectangle:
            return Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: Corners.xs,
              ),
            );
        }
      },
    );
  }
}

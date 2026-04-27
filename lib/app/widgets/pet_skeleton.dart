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
///
/// One composite, layered on the primitives:
///
/// - [PetSkeletonListRow]    — ListTile-shaped row (optional leading
///   circle, 1–2 stacked lines, optional trailing chip-shape).
///   Used by [AppScaffold.async]'s default loading and by any list
///   surface that wants an authentic preview of its row geometry —
///   journal entries, care guides, reminders all share it.
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

/// ListTile-shaped row skeleton — composes the primitives. Honors the
/// same pulse animation by virtue of building from `PetSkeleton.line`
/// + `PetSkeleton.circle` + `PetSkeleton.rectangle` children, each of
/// which runs its own controller. Authoring rather than wrapping
/// keeps a single shared duration/curve from the primitive class.
///
/// Default geometry approximates Material's ListTile (56dp min height,
/// 16dp horizontal padding) so a `listRow` skeleton drops into a
/// `ListView.builder` without further wrapping.
class PetSkeletonListRow extends StatelessWidget {
  const PetSkeletonListRow({
    super.key,
    this.hasLeading = true,
    this.lines = 2,
    this.hasTrailing = false,
    this.titleWidth = 200,
    this.subtitleWidth = 140,
  }) : assert(lines == 1 || lines == 2, 'lines must be 1 or 2');

  /// Whether to render a 40dp leading circle (avatar / icon slot).
  final bool hasLeading;

  /// 1 (title only) or 2 (title + subtitle).
  final int lines;

  /// Whether to render a 56×28dp trailing chip-shaped rectangle.
  final bool hasTrailing;

  final double titleWidth;
  final double subtitleWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.m,
        vertical: Spacing.s,
      ),
      child: Row(
        children: [
          if (hasLeading) ...[
            const PetSkeleton.circle(diameter: 40),
            const SizedBox(width: Spacing.m),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                PetSkeleton.line(width: titleWidth, height: 16),
                if (lines == 2) ...[
                  const SizedBox(height: Spacing.xs),
                  PetSkeleton.line(width: subtitleWidth, height: 12),
                ],
              ],
            ),
          ),
          if (hasTrailing) ...[
            const SizedBox(width: Spacing.m),
            const PetSkeleton.rectangle(width: 56, height: 28),
          ],
        ],
      ),
    );
  }
}

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

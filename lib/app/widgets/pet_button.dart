import 'package:flutter/material.dart';

import '../design/design.dart';

/// Button variants matching Material 3's emphasis levels.
enum PetButtonVariant { filled, outlined, text }

/// Primary button primitive. Pill shape (DECISIONS row 38), three
/// emphasis variants, and a loading state that swaps the label for a
/// spinner without changing the button's width — so a tap never causes a
/// layout shift on the surrounding row.
///
/// VOICE.md §1: button labels stay static (no pet-name interpolation
/// per VOICE.md §5). The label parameter is therefore a plain `String`,
/// not a builder.
class PetButton extends StatelessWidget {
  const PetButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = PetButtonVariant.filled,
    this.icon,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final PetButtonVariant variant;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveOnPressed = isLoading ? null : onPressed;
    // Phase 5.6 Commit C — press physics. The press-scale gesture
    // wraps the inner content (NOT the entire FilledButton/etc.) so
    // the Material splash + ripple keeps its full hit-rect; the
    // visual scale-down lives on the label/icon area and reads as
    // "the button squeezed under the tap" without breaking the
    // ink-well boundary. All three variants inherit because they
    // all share `_PetButtonContent`.
    final child = _PressScale(
      enabled: effectiveOnPressed != null,
      child: _PetButtonContent(
        label: label,
        icon: icon,
        isLoading: isLoading,
        spinnerColor: _spinnerColor(scheme),
      ),
    );
    switch (variant) {
      case PetButtonVariant.filled:
        return FilledButton(onPressed: effectiveOnPressed, child: child);
      case PetButtonVariant.outlined:
        return OutlinedButton(onPressed: effectiveOnPressed, child: child);
      case PetButtonVariant.text:
        return TextButton(onPressed: effectiveOnPressed, child: child);
    }
  }

  Color _spinnerColor(ColorScheme scheme) {
    switch (variant) {
      case PetButtonVariant.filled:
        return scheme.onPrimary;
      case PetButtonVariant.outlined:
      case PetButtonVariant.text:
        return scheme.primary;
    }
  }
}

/// Press-down scale gesture detector. Drives an `AnimatedScale`
/// between 1.0 (rest) and 0.98 (pressed) with `Motion.springCurve`
/// for the spring-back on release. Phase 5.6 Commit C — DECISIONS
/// row 50 lock. Routes through `Listener` rather than
/// `GestureDetector` so it doesn't compete with the Material
/// InkWell's own gesture pipeline; pointer events are observed
/// translucently and the FilledButton/OutlinedButton/TextButton's
/// onPressed still fires normally.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, required this.enabled});

  final Widget child;
  final bool enabled;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: Motion.short,
        curve: Motion.springCurve,
        child: widget.child,
      ),
    );
  }
}

class _PetButtonContent extends StatelessWidget {
  const _PetButtonContent({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.spinnerColor,
  });

  final String label;
  final IconData? icon;
  final bool isLoading;
  final Color spinnerColor;

  @override
  Widget build(BuildContext context) {
    // Stack so the label always lays out (controls width) regardless of
    // loading state. The label fades to opacity 0 while loading; the
    // spinner mounts only when loading. Width never changes (label
    // always occupies its full width via opacity-only fade) — no
    // layout shift on tap, no neighbouring widgets jumping.
    //
    // The spinner is conditionally mounted rather than always-rendered-
    // -with-opacity-0 because CircularProgressIndicator has a
    // continuously-running animation that blocks `pumpAndSettle` in
    // widget tests even when invisible. Conditionally mounting kills
    // the animation when not in use; the small cross-fade-in for the
    // spinner is sacrificed in exchange for testable surfaces.
    final labelWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: Spacing.s),
        ],
        // Flexible so a long label wraps within the button's width
        // rather than overflowing at large accessibility text scales.
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          duration: Motion.short,
          curve: Motion.standardCurve,
          opacity: isLoading ? 0 : 1,
          child: IgnorePointer(ignoring: isLoading, child: labelWidget),
        ),
        if (isLoading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: spinnerColor,
            ),
          ),
      ],
    );
  }
}

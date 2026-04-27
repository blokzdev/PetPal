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
    final child = _PetButtonContent(
      label: label,
      icon: icon,
      isLoading: isLoading,
      spinnerColor: _spinnerColor(scheme),
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
    // spinner fades in on top. Width never changes — no layout shift on
    // tap, no neighbouring widgets jumping. The label is wrapped in
    // IgnorePointer when invisible so its no-longer-visible text can't
    // accidentally absorb hit-testing on the button surface.
    final labelWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: Spacing.s),
        ],
        Text(label),
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
        AnimatedOpacity(
          duration: Motion.short,
          curve: Motion.standardCurve,
          opacity: isLoading ? 1 : 0,
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: spinnerColor,
            ),
          ),
        ),
      ],
    );
  }
}

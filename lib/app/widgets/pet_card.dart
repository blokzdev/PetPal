import 'package:flutter/material.dart';

import '../design/design.dart';

/// Default card primitive — surfaceContainer fill, 16dp radius (Radii.m),
/// low elevation. Matches the `cardTheme` set by `lib/app/design/`,
/// re-stated here so app code can use a single import.
///
/// For tappable cards, use [PetCardButton] — it preserves the same
/// visual treatment and adds an `InkWell` ripple inside the rounded
/// corner, which a vanilla `Card` doesn't clip cleanly.
class PetCard extends StatelessWidget {
  const PetCard({
    super.key,
    required this.child,
    this.padding = Insets.m,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Tappable variant. Adds a ripple inside the card's rounded corners.
class PetCardButton extends StatelessWidget {
  const PetCardButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.padding = Insets.m,
    this.margin,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

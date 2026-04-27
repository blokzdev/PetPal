import 'package:flutter/material.dart';

/// Theme-aware wrapper around [Icon]. Today this just delegates; the
/// dispatcher between Material Icons and custom-asset glyphs (per Phase 5
/// task 5.2's ROADMAP description) lands once the journal-+-paw glyph
/// asset arrives in task 5.3 — at which point [PetIcon] grows a second
/// constructor for asset-glyph rendering. Until then, callsites use the
/// Material constructor and benefit from the default `onSurface`-derived
/// color so icons read correctly in both light and dark modes without
/// explicit color parameters at every callsite.
class PetIcon extends StatelessWidget {
  const PetIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final IconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Icon(
      icon,
      size: size,
      color: color ?? scheme.onSurface.withValues(alpha: 0.85),
      semanticLabel: semanticLabel,
    );
  }
}

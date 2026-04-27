import 'package:flutter/material.dart';

/// Soft modern palette — locked in DECISIONS row 35.
abstract final class PetPalColors {
  /// Muted sage. Primary brand color, used as the seed for `ColorScheme`.
  static const Color sage = Color(0xFF5C8A7A);

  /// Soft coral. Secondary accent — sparing use, draws attention.
  static const Color coral = Color(0xFFE89B7A);

  /// Warm off-white. Light-mode background. Distinct from `#FFFFFF` —
  /// the slight warmth carries through every surface.
  static const Color warmOffWhite = Color(0xFFF7F5F2);

  /// Graphite ink. Primary text on warm light surfaces; also the
  /// foreground tone of the journal-+-paw adaptive icon (task 5.3).
  static const Color graphite = Color(0xFF2D3436);

  /// Warm light surface scale (light mode). Hand-tuned to step up from
  /// [warmOffWhite] without the M3-default lavender drift that
  /// `ColorScheme.fromSeed` produces on a sage seed. Lower index = closer
  /// to the background; higher index = more raised.
  static const Color lightSurfaceLowest = Color(0xFFFFFFFF);
  static const Color lightSurfaceLow = Color(0xFFFBFAF7);
  static const Color lightSurface = warmOffWhite;
  static const Color lightSurfaceContainer = Color(0xFFF2EFE9);
  static const Color lightSurfaceContainerHigh = Color(0xFFEDE9E1);
  static const Color lightSurfaceContainerHighest = Color(0xFFE7E2D7);

  /// Honest warm graphite dark scale (DECISIONS row 38). Pure warm
  /// graphite base — no brand-color pull-through in the surface bands.
  /// Sage and coral remain accent colors; surfaces stay neutral so
  /// journal/chat content reads cleanly.
  static const Color darkSurfaceLowest = Color(0xFF161512);
  static const Color darkSurfaceLow = Color(0xFF1F1E1C);
  static const Color darkSurface = Color(0xFF23211E);
  static const Color darkSurfaceContainer = Color(0xFF28261F);
  static const Color darkSurfaceContainerHigh = Color(0xFF2D2B22);
  static const Color darkSurfaceContainerHighest = Color(0xFF33302C);

  /// On-surface ink for dark mode — warm off-white, mirrors the warmth
  /// of the light theme's text-on-surface relationship.
  static const Color darkOnSurface = Color(0xFFEEE9E0);
}

/// Builds the light `ColorScheme`. Seeded from sage, then overrides every
/// surface band with the warm scale to neutralise the M3-default drift
/// toward lavender on sage primaries. Sage stays primary; coral lands as
/// `tertiary` (M3 reserves `secondary` for a derivative of the seed —
/// putting coral on `tertiary` keeps it semantically "the accent").
ColorScheme buildLightColorScheme() {
  final base = ColorScheme.fromSeed(
    seedColor: PetPalColors.sage,
    brightness: Brightness.light,
  );
  return base.copyWith(
    primary: PetPalColors.sage,
    onPrimary: PetPalColors.warmOffWhite,
    tertiary: PetPalColors.coral,
    onTertiary: PetPalColors.graphite,
    surface: PetPalColors.lightSurface,
    surfaceContainerLowest: PetPalColors.lightSurfaceLowest,
    surfaceContainerLow: PetPalColors.lightSurfaceLow,
    surfaceContainer: PetPalColors.lightSurfaceContainer,
    surfaceContainerHigh: PetPalColors.lightSurfaceContainerHigh,
    surfaceContainerHighest: PetPalColors.lightSurfaceContainerHighest,
    onSurface: PetPalColors.graphite,
    surfaceTint: PetPalColors.sage,
  );
}

/// Builds the dark `ColorScheme` — honest warm graphite (DECISIONS row 38).
ColorScheme buildDarkColorScheme() {
  final base = ColorScheme.fromSeed(
    seedColor: PetPalColors.sage,
    brightness: Brightness.dark,
  );
  return base.copyWith(
    primary: PetPalColors.sage,
    onPrimary: PetPalColors.graphite,
    tertiary: PetPalColors.coral,
    onTertiary: PetPalColors.graphite,
    surface: PetPalColors.darkSurface,
    surfaceContainerLowest: PetPalColors.darkSurfaceLowest,
    surfaceContainerLow: PetPalColors.darkSurfaceLow,
    surfaceContainer: PetPalColors.darkSurfaceContainer,
    surfaceContainerHigh: PetPalColors.darkSurfaceContainerHigh,
    surfaceContainerHighest: PetPalColors.darkSurfaceContainerHighest,
    onSurface: PetPalColors.darkOnSurface,
    surfaceTint: PetPalColors.sage,
  );
}

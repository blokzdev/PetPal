import 'package:flex_color_scheme/flex_color_scheme.dart';
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

/// Builds the light `ColorScheme`. Phase 5.6 (DECISIONS row 50)
/// upgraded the resolution: FlexColorScheme generates the tonal
/// derivatives (containers, on-tones, fixed pairs) from the sage
/// primary + coral tertiary anchors with proper M3 tonal harmony,
/// then the manual surface overrides land last to neutralise the
/// M3-default drift toward lavender on sage primaries (DECISIONS
/// row 35 hex values stay pinned). Sage stays primary; coral lands
/// as `tertiary` — M3 reserves `secondary` for a derivative of the
/// seed, so putting coral on `tertiary` keeps it semantically "the
/// accent."
ColorScheme buildLightColorScheme() {
  final base = FlexColorScheme.light(
    colors: const FlexSchemeColor(
      primary: PetPalColors.sage,
      primaryContainer: PetPalColors.lightSurfaceContainerHigh,
      secondary: PetPalColors.sage,
      secondaryContainer: PetPalColors.lightSurfaceContainer,
      tertiary: PetPalColors.coral,
      tertiaryContainer: PetPalColors.lightSurfaceContainerHigh,
    ),
    surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
    blendLevel: 8,
  ).toScheme;
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

/// Builds the dark `ColorScheme` — honest warm graphite (DECISIONS
/// row 38). Same tonal-harmony upgrade as light via FlexColorScheme
/// (DECISIONS row 50); manual warm-graphite surface overrides land
/// last so brand-color pull-through stays out of the surface bands
/// and journal/chat content reads cleanly.
ColorScheme buildDarkColorScheme() {
  final base = FlexColorScheme.dark(
    colors: const FlexSchemeColor(
      primary: PetPalColors.sage,
      primaryContainer: PetPalColors.darkSurfaceContainerHigh,
      secondary: PetPalColors.sage,
      secondaryContainer: PetPalColors.darkSurfaceContainer,
      tertiary: PetPalColors.coral,
      tertiaryContainer: PetPalColors.darkSurfaceContainerHigh,
    ),
    surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
    blendLevel: 6,
  ).toScheme;
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

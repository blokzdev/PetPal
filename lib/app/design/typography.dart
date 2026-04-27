import 'dart:ui';

import 'package:flutter/material.dart';

/// Typography — Inter (UI body) + Source Serif 4 (journal accent on entry
/// titles + weekly-summary titles). Both ship as bundled variable fonts
/// (DECISIONS row 35 + row 38) so first-launch typography is correct
/// offline and consistent with PetPal's offline-first positioning.
///
/// Variable-font weight selection uses [FontVariation] (`wght` axis) rather
/// than relying on Flutter's static weight-to-asset slot mapping —
/// the variable file carries every weight from 100 to 900, and the
/// `wght` axis renders the requested weight on the fly.
abstract final class PetPalTypography {
  static const String inter = 'Inter';
  static const String sourceSerif4 = 'SourceSerif4';

  /// Material 3 reference text-theme weights. Centralised so a future
  /// taste shift (heavier titles, lighter bodies) edits one place.
  static const double weightRegular = 400;
  static const double weightMedium = 500;
  static const double weightSemiBold = 600;
  static const double weightBold = 700;
}

/// Returns a `wght`-axis variation for the variable font.
List<FontVariation> _wght(double weight) =>
    <FontVariation>[FontVariation('wght', weight)];

TextStyle _inter({
  required double size,
  required double weight,
  double letterSpacing = 0,
  double? height,
}) =>
    TextStyle(
      fontFamily: PetPalTypography.inter,
      fontSize: size,
      fontVariations: _wght(weight),
      // Best-effort static fallback. Modern Flutter renders the variable
      // axis from `fontVariations`; older renderers fall back to the
      // declared weight slot.
      fontWeight: _staticWeightFor(weight),
      letterSpacing: letterSpacing,
      height: height,
    );

TextStyle _serif({
  required double size,
  required double weight,
  double letterSpacing = 0,
  double? height,
}) =>
    TextStyle(
      fontFamily: PetPalTypography.sourceSerif4,
      fontSize: size,
      fontVariations: _wght(weight),
      fontWeight: _staticWeightFor(weight),
      letterSpacing: letterSpacing,
      height: height,
    );

FontWeight _staticWeightFor(double w) {
  if (w >= 700) return FontWeight.w700;
  if (w >= 600) return FontWeight.w600;
  if (w >= 500) return FontWeight.w500;
  return FontWeight.w400;
}

/// Builds the Material 3 `TextTheme` using Inter for every slot. Sizes,
/// weights, and letter-spacing values follow the M3 reference defaults so
/// platform components (AppBar, ListTile, dialogs, snackbars) read
/// correctly when they reach into the theme for type.
TextTheme buildTextTheme() {
  return TextTheme(
    displayLarge: _inter(size: 57, weight: 400, letterSpacing: -0.25),
    displayMedium: _inter(size: 45, weight: 400),
    displaySmall: _inter(size: 36, weight: 400),
    headlineLarge: _inter(size: 32, weight: 400),
    headlineMedium: _inter(size: 28, weight: 400),
    headlineSmall: _inter(size: 24, weight: 400),
    titleLarge: _inter(size: 22, weight: 400),
    titleMedium: _inter(size: 16, weight: 500, letterSpacing: 0.15),
    titleSmall: _inter(size: 14, weight: 500, letterSpacing: 0.1),
    bodyLarge: _inter(size: 16, weight: 400, letterSpacing: 0.5, height: 1.5),
    bodyMedium: _inter(size: 14, weight: 400, letterSpacing: 0.25, height: 1.45),
    bodySmall: _inter(size: 12, weight: 400, letterSpacing: 0.4, height: 1.4),
    labelLarge: _inter(size: 14, weight: 500, letterSpacing: 0.1),
    labelMedium: _inter(size: 12, weight: 500, letterSpacing: 0.5),
    labelSmall: _inter(size: 11, weight: 500, letterSpacing: 0.5),
  );
}

/// Journal accent — Source Serif 4. Used by journal entry titles and
/// weekly-summary entry titles to visually mark "this is the moat" copy.
/// Components that want a journal-flavoured title call this directly
/// rather than reading from the global TextTheme so the accent stays
/// scoped to the surfaces that earn it.
abstract final class JournalText {
  /// Title for an individual journal entry. Reads with weight, looks
  /// like a notebook heading rather than a UI label.
  static TextStyle entryTitle({Color? color}) {
    final base = _serif(size: 24, weight: 600, height: 1.25);
    return color == null ? base : base.copyWith(color: color);
  }

  /// Title for a weekly-summary digest entry. Slightly larger than a
  /// regular entry title — the weekly summary is a cumulative artifact.
  static TextStyle weeklySummaryTitle({Color? color}) {
    final base = _serif(size: 28, weight: 600, height: 1.2);
    return color == null ? base : base.copyWith(color: color);
  }
}

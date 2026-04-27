import 'package:flutter/material.dart';

import 'colors.dart';
import 'elevation.dart';
import 'motion.dart';
import 'radii.dart';
import 'spacing.dart';
import 'typography.dart';

/// Composes the design tokens into a `ThemeData`. Both light and dark
/// share the same surface shapes, motion, typography, and component
/// micro-styling — only the [ColorScheme] differs.
ThemeData _build(ColorScheme scheme) {
  final textTheme = buildTextTheme().apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    textTheme: textTheme,
    fontFamily: PetPalTypography.inter,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
    cardTheme: CardThemeData(
      elevation: Elevation.low,
      shape: const RoundedRectangleBorder(borderRadius: Corners.m),
      color: scheme.surfaceContainer,
      surfaceTintColor: scheme.surfaceTint,
      margin: const EdgeInsets.all(Spacing.s),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: scheme.surfaceTint,
      elevation: Elevation.flat,
      scrolledUnderElevation: Elevation.low,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.l,
          vertical: Spacing.s + Spacing.xs,
        ),
        textStyle: textTheme.labelLarge,
        animationDuration: Motion.short,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.l,
          vertical: Spacing.s + Spacing.xs,
        ),
        textStyle: textTheme.labelLarge,
        animationDuration: Motion.short,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.m,
          vertical: Spacing.s,
        ),
        textStyle: textTheme.labelLarge,
        animationDuration: Motion.short,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      labelStyle: textTheme.labelMedium,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s + Spacing.xs,
        vertical: Spacing.xs,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.m,
        vertical: Spacing.s + Spacing.xs,
      ),
      border: const OutlineInputBorder(
        borderRadius: Corners.s,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: Corners.s,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: Corners.s,
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      labelStyle: textTheme.bodyMedium,
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurface.withValues(alpha: 0.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      elevation: Elevation.medium,
      shape: const RoundedRectangleBorder(borderRadius: Corners.l),
      surfaceTintColor: scheme.surfaceTint,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle:
          textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      shape: const RoundedRectangleBorder(borderRadius: Corners.s),
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.all(Spacing.m),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.m,
        vertical: Spacing.xs,
      ),
      titleTextStyle: textTheme.titleMedium,
      subtitleTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurface.withValues(alpha: 0.7),
      ),
      iconColor: scheme.onSurface.withValues(alpha: 0.8),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: Spacing.l,
    ),
  );
}

ThemeData buildPetPalLightTheme() => _build(buildLightColorScheme());

ThemeData buildPetPalDarkTheme() => _build(buildDarkColorScheme());

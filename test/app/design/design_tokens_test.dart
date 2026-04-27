import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/design/design.dart';

void main() {
  group('palette (DECISIONS row 35)', () {
    test('locked hex values', () {
      expect(PetPalColors.sage, const Color(0xFF5C8A7A));
      expect(PetPalColors.coral, const Color(0xFFE89B7A));
      expect(PetPalColors.warmOffWhite, const Color(0xFFF7F5F2));
      expect(PetPalColors.graphite, const Color(0xFF2D3436));
    });

    test('light surface scale steps from white toward warm off-white', () {
      // Lowest is pure white; highest is the most-saturated warm tone —
      // monotonic warmth as you climb the elevation pyramid.
      expect(PetPalColors.lightSurfaceLowest, const Color(0xFFFFFFFF));
      expect(PetPalColors.lightSurface, PetPalColors.warmOffWhite);
      expect(PetPalColors.lightSurfaceContainerHighest,
          const Color(0xFFE7E2D7));
    });

    test('dark surface scale stays warm graphite (no cool grey, row 35)', () {
      // Each band should have R >= G in 8-bit — a warm bias, not the
      // M3-default cool grey where B >= R.
      for (final c in <Color>[
        PetPalColors.darkSurfaceLowest,
        PetPalColors.darkSurfaceLow,
        PetPalColors.darkSurface,
        PetPalColors.darkSurfaceContainer,
        PetPalColors.darkSurfaceContainerHigh,
        PetPalColors.darkSurfaceContainerHighest,
      ]) {
        final r = (c.r * 255).round();
        final g = (c.g * 255).round();
        final b = (c.b * 255).round();
        expect(r >= b, isTrue,
            reason: 'expected warm bias (R >= B) on $c, got R=$r G=$g B=$b');
      }
    });
  });

  group('color schemes', () {
    test('light scheme primary is sage; tertiary is coral', () {
      final s = buildLightColorScheme();
      expect(s.brightness, Brightness.light);
      expect(s.primary, PetPalColors.sage);
      expect(s.tertiary, PetPalColors.coral);
      expect(s.surface, PetPalColors.warmOffWhite);
    });

    test('dark scheme keeps sage as primary and warm graphite as surface', () {
      final s = buildDarkColorScheme();
      expect(s.brightness, Brightness.dark);
      expect(s.primary, PetPalColors.sage);
      expect(s.tertiary, PetPalColors.coral);
      expect(s.surface, PetPalColors.darkSurface);
      expect(s.onSurface, PetPalColors.darkOnSurface);
    });

    test('surface tint anchored to primary (suppresses M3 lavender drift)',
        () {
      expect(buildLightColorScheme().surfaceTint, PetPalColors.sage);
      expect(buildDarkColorScheme().surfaceTint, PetPalColors.sage);
    });
  });

  group('spacing scale (Spacing.xs/s/m/l/xl)', () {
    test('strictly monotonic on the 4-pt grid', () {
      expect(Spacing.xs, 4);
      expect(Spacing.s, 8);
      expect(Spacing.m, 16);
      expect(Spacing.l, 24);
      expect(Spacing.xl, 32);
    });

    test('Insets/Gaps mirror the scale', () {
      expect(Insets.m.left, Spacing.m);
      expect(Insets.m.top, Spacing.m);
      expect(Gaps.l.height, Spacing.l);
      expect(Gaps.l.width, Spacing.l);
    });
  });

  group('radii (PetPal-warmer rounded, DECISIONS row 38)', () {
    test('softer than Material 3 defaults', () {
      // M3 defaults are 4/8/12/16/28. PetPal scale is 8/12/16/24 + pill.
      expect(Radii.xs, 8);
      expect(Radii.s, 12);
      expect(Radii.m, 16);
      expect(Radii.l, 24);
    });

    test('pill is a sentinel signalling StadiumBorder', () {
      expect(Radii.pill, lessThan(0));
    });
  });

  group('motion (Material 3 standard, DECISIONS row 38)', () {
    test('200/300/500ms scale', () {
      expect(Motion.short, const Duration(milliseconds: 200));
      expect(Motion.medium, const Duration(milliseconds: 300));
      expect(Motion.long, const Duration(milliseconds: 500));
    });

    test('curves are non-default (intentional choice, not implicit)', () {
      expect(Motion.standardCurve, isNot(Curves.linear));
      expect(Motion.heroCurve, isNot(Curves.linear));
    });
  });

  group('elevation', () {
    test('strictly monotonic flat → high', () {
      expect(Elevation.flat, lessThan(Elevation.low));
      expect(Elevation.low, lessThan(Elevation.medium));
      expect(Elevation.medium, lessThan(Elevation.high));
    });
  });

  group('typography', () {
    test('Inter and SourceSerif4 family names are stable', () {
      // The family names here must match `pubspec.yaml`'s `fonts:`
      // entries exactly — a typo here ships system-default fonts at
      // runtime with no error.
      expect(PetPalTypography.inter, 'Inter');
      expect(PetPalTypography.sourceSerif4, 'SourceSerif4');
    });

    test('Material 3 TextTheme is fully populated and uses Inter', () {
      final t = buildTextTheme();
      for (final s in <TextStyle?>[
        t.displayLarge,
        t.displayMedium,
        t.displaySmall,
        t.headlineLarge,
        t.headlineMedium,
        t.headlineSmall,
        t.titleLarge,
        t.titleMedium,
        t.titleSmall,
        t.bodyLarge,
        t.bodyMedium,
        t.bodySmall,
        t.labelLarge,
        t.labelMedium,
        t.labelSmall,
      ]) {
        expect(s, isNotNull);
        expect(s!.fontFamily, PetPalTypography.inter);
        expect(s.fontVariations, isNotNull);
        expect(s.fontVariations!.first.axis, 'wght');
      }
    });

    test('JournalText uses Source Serif 4 with semibold wght axis', () {
      final entry = JournalText.entryTitle();
      expect(entry.fontFamily, PetPalTypography.sourceSerif4);
      expect(entry.fontVariations,
          contains(const FontVariation('wght', 600)));
      final weekly = JournalText.weeklySummaryTitle();
      expect(weekly.fontFamily, PetPalTypography.sourceSerif4);
      expect(weekly.fontSize! > entry.fontSize!, isTrue,
          reason: 'weekly summary title should outrank a regular entry title');
    });

    test('JournalText.copyWith honours color override', () {
      const c = Color(0xFF123456);
      expect(JournalText.entryTitle(color: c).color, c);
      expect(JournalText.weeklySummaryTitle(color: c).color, c);
    });
  });

  group('ThemeData composition', () {
    test('light theme builds with all expected anchors', () {
      final t = buildPetPalLightTheme();
      expect(t.useMaterial3, isTrue);
      expect(t.colorScheme.primary, PetPalColors.sage);
      expect(t.scaffoldBackgroundColor, PetPalColors.warmOffWhite);
      expect(t.textTheme.bodyMedium?.fontFamily, PetPalTypography.inter);
    });

    test('dark theme builds with warm graphite surface', () {
      final t = buildPetPalDarkTheme();
      expect(t.useMaterial3, isTrue);
      expect(t.colorScheme.brightness, Brightness.dark);
      expect(t.scaffoldBackgroundColor, PetPalColors.darkSurface);
    });

    test('button shape is StadiumBorder (pill) for the warmer character',
        () {
      final t = buildPetPalLightTheme();
      final filledShape =
          t.filledButtonTheme.style?.shape?.resolve(<WidgetState>{});
      expect(filledShape, isA<StadiumBorder>());
      final outlinedShape =
          t.outlinedButtonTheme.style?.shape?.resolve(<WidgetState>{});
      expect(outlinedShape, isA<StadiumBorder>());
    });

    test('AppBar elevation is flat at rest', () {
      final t = buildPetPalLightTheme();
      expect(t.appBarTheme.elevation, Elevation.flat);
      expect(t.appBarTheme.scrolledUnderElevation, Elevation.low);
    });
  });
}

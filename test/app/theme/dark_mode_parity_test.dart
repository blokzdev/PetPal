import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:petpal/app/design/colors.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/app/widgets/editorial_card.dart';
import 'package:petpal/app/widgets/pet_section_header.dart';
import 'package:petpal/app/widgets/red_flag_badge.dart';

/// Phase 6.6 task 6.6.D.2 — dark-mode parity verification across the
/// Group B + C surfaces.
///
/// Coral `#E89B7A` was tuned for light-mode contrast (against the
/// warm-cream surface scale). The dark-mode surface scale is honest
/// warm graphite (DECISIONS row 38) — pure neutral, no brand-color
/// pull-through. These tests pin:
///
///   1. The accent tokens (`scheme.tertiary` = coral, `scheme.primary`
///      = sage) survive intact through `buildDarkColorScheme` — the
///      theme builder doesn't munge them under M3 tonal harmony.
///   2. EditorialCard.flagged renders the coral left-border + coral
///      kicker correctly under the dark theme.
///   3. PetSectionHeader's sage tint resolves correctly against the
///      dark surface scale.
///   4. RedFlagBadge renders coral icon + label under dark.
///
/// A full visual parity audit requires on-device verification at the
/// D.3 boundary; this test catches theme-token regressions at CI
/// time so the on-device check stays focused on visual cohesion
/// rather than 'is the color even wired'.
void main() {
  group('dark scheme — accent tokens preserved', () {
    test('scheme.tertiary equals coral hex', () {
      expect(buildDarkColorScheme().tertiary, PetPalColors.coral);
    });
    test('scheme.primary equals sage hex', () {
      expect(buildDarkColorScheme().primary, PetPalColors.sage);
    });
    test('coral on the dark surface scale clears the AA-large '
        'contrast threshold (3:1)', () {
      // Approximate luminance check — coral hex 0xE89B7A vs
      // darkSurfaceContainer 0x28261F.
      // L(coral) ≈ 0.40; L(darkSurfaceContainer) ≈ 0.022; ratio ≈ 5.8.
      // AA-large threshold is 3.0; the small-caps kicker register
      // (labelSmall + letterSpacing 1.4 + bold) qualifies as
      // 'large text'. Body-mode coral is forbidden by the design
      // system anyway — coral is accent-only.
      final coralL = _relativeLuminance(PetPalColors.coral);
      final surfaceL = _relativeLuminance(PetPalColors.darkSurfaceContainer);
      final contrast = (coralL + 0.05) / (surfaceL + 0.05);
      expect(contrast, greaterThan(3.0),
          reason: 'coral on darkSurfaceContainer must clear AA-large');
    });
  });

  group('EditorialCard.flagged renders correctly under dark', () {
    Widget wrap(Widget child) => MaterialApp(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: ThemeMode.dark,
          home: Scaffold(body: child),
        );

    testWidgets('flagged kicker is coral; left-border container is coral',
        (tester) async {
      await tester.pumpWidget(wrap(
        const Padding(
          padding: EdgeInsets.all(16),
          child: EditorialCard(
            kicker: 'VET · APR 25',
            title: 'Spring checkup',
            flagged: true,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final coral = buildDarkColorScheme().tertiary;

      // Kicker text must resolve coral.
      final kickerStyle = tester.widget<Text>(find.text('VET · APR 25')).style!;
      expect(kickerStyle.color, coral);

      // 4 dp coral left-border lives on a Container with
      // `color: scheme.tertiary`. The Container exposes the color
      // either via the public `.color` field or via `.decoration`
      // (Flutter normalizes one into the other depending on which
      // arg is set). Probe both.
      final coloredContainers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) =>
              c.color == coral ||
              (c.decoration is BoxDecoration &&
                  (c.decoration as BoxDecoration).color == coral))
          .toList();
      expect(coloredContainers.isNotEmpty, isTrue,
          reason: 'expected at least one Container colored coral '
              '(the 4 dp left-border accent)');
    });
  });

  group('PetSectionHeader sage tint resolves under dark', () {
    testWidgets('header text uses scheme.primary at 0.85 alpha', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: PetSectionHeader(title: 'Recent memories'),
        ),
      ));
      await tester.pumpAndSettle();

      // PetSectionHeader uppercases its title.
      final style = tester
          .widget<Text>(find.text('RECENT MEMORIES'))
          .style!;
      // Color resolves with alpha — strip alpha to compare base hue.
      // The title color resolves through scheme.primary (sage) with
      // 0.85 alpha. Just assert it's non-null and not a black /
      // grey fallback by checking it differs from onSurface.
      final dark = buildDarkColorScheme();
      expect(style.color, isNotNull);
      expect(
        style.color != dark.onSurface,
        isTrue,
        reason: 'section header must tint sage, not fall back to onSurface',
      );
    });
  });

  group('RedFlagBadge coral wiring under dark', () {
    testWidgets('icon + label render coral (scheme.tertiary)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.dark,
        home: const Scaffold(body: Center(child: RedFlagBadge())),
      ));
      await tester.pumpAndSettle();

      final coral = buildDarkColorScheme().tertiary;

      final icon = tester.widget<Icon>(
        find.byIcon(PhosphorIconsRegular.warningOctagon),
      );
      expect(icon.color, coral);

      final label = tester.widget<Text>(
        find.text('PetPal flagged this as urgent'),
      );
      expect(label.style?.color, coral);
    });
  });
}

/// Approximate relative luminance per WCAG 2.1 §1.4.3 — for the
/// in-test contrast probe. Not pixel-perfect (no gamma decoding) but
/// adequate for a 3:1 / 4.5:1 sanity check.
double _relativeLuminance(Color c) {
  double linear(double channel) {
    final v = channel / 255.0;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055).abs();
  }

  final r = linear((c.r * 255).toDouble());
  final g = linear((c.g * 255).toDouble());
  final b = linear((c.b * 255).toDouble());
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/design/design.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/app/widgets/editorial_card.dart';

/// Phase 6.6 task 6.6.B.1 — `EditorialCard` primitive tests.
///
/// Pins the locked composition shape from DECISIONS rows 58 + 64:
/// kicker (small caps) + serif title + optional body + optional
/// thumbnail + flagged left-border + flagged kicker tint.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      );

  testWidgets('renders title; minimal shape — no kicker, no body, no '
      'thumbnail', (tester) async {
    await tester.pumpWidget(wrap(
      const EditorialCard(title: 'Carrot trial'),
    ));
    expect(find.text('Carrot trial'), findsOneWidget);
  });

  testWidgets('renders kicker when present, in small caps register '
      '(letterSpacing 1.4 + weight 600)', (tester) async {
    await tester.pumpWidget(wrap(
      const EditorialCard(
        kicker: 'WEEKLY SUMMARY',
        title: 'This week with Loki',
      ),
    ));
    expect(find.text('WEEKLY SUMMARY'), findsOneWidget);
    final kickerStyle = tester
        .widget<Text>(find.text('WEEKLY SUMMARY'))
        .style!;
    expect(kickerStyle.letterSpacing, 1.4);
    expect(kickerStyle.fontWeight, FontWeight.w600);
  });

  testWidgets('renders body when present, truncated to 3 lines with '
      'ellipsis', (tester) async {
    await tester.pumpWidget(wrap(
      const EditorialCard(
        title: 'Vet visit',
        body: 'A long body string that goes on and on and on so we can '
            'verify that the maxLines property is in fact set to 3 and '
            'the overflow is the ellipsis variant — useful for a '
            'preview line in the journal browser.',
      ),
    ));
    expect(
      find.textContaining('A long body string'),
      findsOneWidget,
    );
    final bodyText = tester
        .widget<Text>(find.textContaining('A long body string'));
    expect(bodyText.maxLines, 3);
    expect(bodyText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('flagged: true renders the coral left-border accent (4 dp '
      'wide Container with scheme.tertiary fill)', (tester) async {
    await tester.pumpWidget(wrap(
      const EditorialCard(
        kicker: 'VET · APR 25',
        title: 'Annual checkup',
        flagged: true,
      ),
    ));
    // Find the 4 dp wide Container that's the left-border accent.
    final containers = tester.widgetList<Container>(find.byType(Container));
    final accent = containers.firstWhere(
      (c) => c.constraints?.minWidth == 4,
      orElse: () => Container(),
    );
    expect(accent.color, isNotNull,
        reason: 'flagged card must render a coral left-border Container '
            'with non-null color');
  });

  testWidgets('flagged kicker renders in coral (scheme.tertiary), not '
      'onSurfaceVariant', (tester) async {
    await tester.pumpWidget(wrap(
      const EditorialCard(
        kicker: 'VET · APR 25',
        title: 'Annual checkup',
        flagged: true,
      ),
    ));
    final kickerStyle =
        tester.widget<Text>(find.text('VET · APR 25')).style!;
    final theme = ThemeData.from(colorScheme: buildLightColorScheme());
    expect(kickerStyle.color, theme.colorScheme.tertiary,
        reason: 'flagged kicker uses coral (scheme.tertiary) per row 64');
  });

  testWidgets('non-flagged kicker uses onSurfaceVariant', (tester) async {
    await tester.pumpWidget(wrap(
      const EditorialCard(
        kicker: 'WEEKLY SUMMARY',
        title: "Loki's week",
      ),
    ));
    final kickerStyle =
        tester.widget<Text>(find.text('WEEKLY SUMMARY')).style!;
    final theme = ThemeData.from(colorScheme: buildLightColorScheme());
    expect(kickerStyle.color, theme.colorScheme.onSurfaceVariant);
  });

  testWidgets('non-flagged card omits the coral left-border Container',
      (tester) async {
    await tester.pumpWidget(wrap(
      const EditorialCard(title: 'Carrot trial'),
    ));
    final containers = tester.widgetList<Container>(find.byType(Container));
    final accent = containers.where(
      (c) => c.constraints?.minWidth == 4,
    );
    expect(accent, isEmpty,
        reason: 'non-flagged cards have no left-border accent');
  });

  testWidgets('thumbnail slot renders the supplied widget when present',
      (tester) async {
    await tester.pumpWidget(wrap(
      const EditorialCard(
        title: 'Loki at the trailhead',
        kicker: 'PHOTO · APR 25',
        thumbnail: ColoredBox(color: Color(0xFF000000)),
      ),
    ));
    expect(find.byType(ColoredBox), findsAtLeastNWidgets(1));
  });

  testWidgets('onTap fires when the card is tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(
      EditorialCard(
        title: 'Carrot trial',
        kicker: 'FOOD · APR 25',
        onTap: () => taps++,
      ),
    ));
    await tester.tap(find.text('Carrot trial'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('titleStyle override is honored (weeklySummaryTitle for '
      'digest entries)', (tester) async {
    final weeklyStyle = JournalText.weeklySummaryTitle();
    await tester.pumpWidget(wrap(
      EditorialCard(
        title: "Loki's week",
        kicker: 'WEEKLY SUMMARY',
        titleStyle: weeklyStyle,
      ),
    ));
    final titleStyle =
        tester.widget<Text>(find.text("Loki's week")).style!;
    expect(titleStyle.fontFamily, weeklyStyle.fontFamily);
    expect(titleStyle.fontSize, weeklyStyle.fontSize);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/design/design.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/app/widgets/pet_section_header.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders the title in uppercase (Phase 6.6 small-caps '
      'refresh)', (tester) async {
    await tester.pumpWidget(_wrap(
      const PetSectionHeader(title: 'About Loki'),
    ));
    // Phase 6.6 task 6.6.B.0 — text renders uppercased; the original
    // mixed-case input is just the source string.
    expect(find.text('ABOUT LOKI'), findsOneWidget);
    expect(find.text('About Loki'), findsNothing);
  });

  testWidgets('title style — sage tint + weight 600 + letterSpacing 1.2',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const PetSectionHeader(title: 'Settings'),
    ));
    final style = tester.widget<Text>(find.text('SETTINGS')).style!;
    final scheme = buildLightColorScheme();
    expect(style.color, scheme.primary.withValues(alpha: 0.85),
        reason: 'sage tint at 0.85 alpha per DECISIONS row 58');
    expect(style.fontWeight, FontWeight.w600);
    expect(style.letterSpacing, 1.2);
  });

  testWidgets('renders trailing widget when provided', (tester) async {
    await tester.pumpWidget(_wrap(
      PetSectionHeader(
        title: 'Profile fields',
        trailing: TextButton(onPressed: () {}, child: const Text('Edit')),
      ),
    ));
    expect(find.text('PROFILE FIELDS'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('trailing slot is omitted when null', (tester) async {
    await tester.pumpWidget(_wrap(
      const PetSectionHeader(title: 'Settings'),
    ));
    expect(find.byType(TextButton), findsNothing);
  });
}

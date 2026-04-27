import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/app/widgets/pet_section_header.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders the title', (tester) async {
    await tester.pumpWidget(_wrap(
      const PetSectionHeader(title: 'About Loki'),
    ));
    expect(find.text('About Loki'), findsOneWidget);
  });

  testWidgets('renders trailing widget when provided', (tester) async {
    await tester.pumpWidget(_wrap(
      PetSectionHeader(
        title: 'Profile fields',
        trailing: TextButton(onPressed: () {}, child: const Text('Edit')),
      ),
    ));
    expect(find.text('Profile fields'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('trailing slot is omitted when null', (tester) async {
    await tester.pumpWidget(_wrap(
      const PetSectionHeader(title: 'Settings'),
    ));
    expect(find.byType(TextButton), findsNothing);
  });
}

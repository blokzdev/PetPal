import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/app/widgets/pet_button.dart';
import 'package:petpal/app/widgets/pet_empty_state.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders icon + heading + body', (tester) async {
    await tester.pumpWidget(_wrap(
      const PetEmptyState(
        icon: PhosphorIconsRegular.bookOpen,
        heading: 'No memories yet',
        body: "Tell PetPal what's been happening and they'll show up here.",
      ),
    ));
    expect(find.byIcon(PhosphorIconsRegular.bookOpen), findsOneWidget);
    expect(find.text('No memories yet'), findsOneWidget);
    expect(find.textContaining('PetPal'), findsOneWidget);
  });

  testWidgets('action slot is rendered when supplied', (tester) async {
    await tester.pumpWidget(_wrap(
      PetEmptyState(
        icon: PhosphorIconsRegular.bell,
        heading: 'No reminders',
        body: 'Reminders for vaccines, flea, weight checks live here.',
        action: PetButton(label: 'Add reminder', onPressed: () {}),
      ),
    ));
    expect(find.text('Add reminder'), findsOneWidget);
    expect(find.byType(PetButton), findsOneWidget);
  });

  testWidgets('action slot is omitted when null', (tester) async {
    await tester.pumpWidget(_wrap(
      const PetEmptyState(
        icon: PhosphorIconsRegular.chatCircle,
        heading: 'Start the conversation',
        body: 'Say hi to PetPal — anything you say gets remembered.',
      ),
    ));
    expect(find.byType(PetButton), findsNothing);
  });
}

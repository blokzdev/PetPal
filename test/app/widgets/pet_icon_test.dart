import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/app/widgets/pet_icon.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('renders the supplied IconData', (tester) async {
    await tester.pumpWidget(_wrap(const PetIcon(Icons.pets)));
    expect(find.byIcon(Icons.pets), findsOneWidget);
  });

  testWidgets('explicit color override wins over theme default',
      (tester) async {
    const c = Color(0xFFFF0000);
    await tester.pumpWidget(_wrap(const PetIcon(Icons.pets, color: c)));
    final icon = tester.widget<Icon>(find.byIcon(Icons.pets));
    expect(icon.color, c);
  });

  testWidgets('size override is honoured', (tester) async {
    await tester.pumpWidget(_wrap(const PetIcon(Icons.pets, size: 32)));
    final icon = tester.widget<Icon>(find.byIcon(Icons.pets));
    expect(icon.size, 32);
  });

  testWidgets('semantic label propagates', (tester) async {
    await tester.pumpWidget(_wrap(
      const PetIcon(Icons.pets, semanticLabel: 'pets'),
    ));
    final icon = tester.widget<Icon>(find.byIcon(Icons.pets));
    expect(icon.semanticLabel, 'pets');
  });
}

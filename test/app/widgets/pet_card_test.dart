import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/app/widgets/pet_card.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('PetCard renders its child inside a Card', (tester) async {
    await tester.pumpWidget(_wrap(
      const PetCard(child: Text('hello')),
    ));
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('PetCardButton wires onPressed via InkWell', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(
      PetCardButton(
        onPressed: () => taps++,
        child: const SizedBox(width: 200, height: 80, child: Text('tap')),
      ),
    ));
    await tester.tap(find.byType(PetCardButton));
    expect(taps, 1);
    expect(find.byType(InkWell), findsOneWidget);
  });

  testWidgets('PetCardButton with null onPressed is a no-op', (tester) async {
    await tester.pumpWidget(_wrap(
      const PetCardButton(
        onPressed: null,
        child: SizedBox(width: 200, height: 80, child: Text('tap')),
      ),
    ));
    // Tapping a disabled InkWell should not throw.
    await tester.tap(find.byType(PetCardButton));
    expect(find.byType(InkWell), findsOneWidget);
  });
}

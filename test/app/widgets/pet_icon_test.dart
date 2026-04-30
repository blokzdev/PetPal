import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/app/widgets/pet_icon.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('renders the supplied IconData', (tester) async {
    await tester.pumpWidget(_wrap(const PetIcon(PhosphorIconsRegular.pawPrint)));
    expect(find.byIcon(PhosphorIconsRegular.pawPrint), findsOneWidget);
  });

  testWidgets('explicit color override wins over theme default',
      (tester) async {
    const c = Color(0xFFFF0000);
    await tester.pumpWidget(
        _wrap(const PetIcon(PhosphorIconsRegular.pawPrint, color: c)));
    final icon = tester.widget<Icon>(find.byIcon(PhosphorIconsRegular.pawPrint));
    expect(icon.color, c);
  });

  testWidgets('size override is honoured', (tester) async {
    await tester.pumpWidget(
        _wrap(const PetIcon(PhosphorIconsRegular.pawPrint, size: 32)));
    final icon = tester.widget<Icon>(find.byIcon(PhosphorIconsRegular.pawPrint));
    expect(icon.size, 32);
  });

  testWidgets('semantic label propagates', (tester) async {
    await tester.pumpWidget(_wrap(
      const PetIcon(PhosphorIconsRegular.pawPrint, semanticLabel: 'pets'),
    ));
    final icon = tester.widget<Icon>(find.byIcon(PhosphorIconsRegular.pawPrint));
    expect(icon.semanticLabel, 'pets');
  });
}

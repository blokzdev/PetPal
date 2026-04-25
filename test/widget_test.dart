import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/main.dart';

void main() {
  testWidgets('Home screen renders PetPal title and tagline', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PetPalApp()));
    await tester.pumpAndSettle();

    expect(find.text('PetPal'), findsNWidgets(2));
    expect(find.text('A memory agent for your pet.'), findsOneWidget);
  });
}

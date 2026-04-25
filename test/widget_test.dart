import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/main.dart';

import '_helpers/fake_api_key_storage.dart';

void main() {
  testWidgets('Onboarded user lands on Home', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PetPal'), findsNWidgets(2));
    expect(find.text('A memory agent for your pet.'), findsOneWidget);
  });

  testWidgets('Unonboarded user lands on the welcome page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(FakeApiKeyStorage()),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome to PetPal'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });
}

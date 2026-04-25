import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/main.dart';

import '../../_helpers/fake_api_key_storage.dart';

void main() {
  testWidgets('walking forward through onboarding lands on Home with the '
      'key persisted', (tester) async {
    final storage = FakeApiKeyStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(storage),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Page 1: welcome
    expect(find.text('Welcome to PetPal'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // Page 2: privacy disclosure
    expect(find.text('Your data, your device.'), findsOneWidget);
    expect(find.textContaining('leaves the device'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Page 3: API key entry
    expect(find.text('Connect to Anthropic'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'sk-ant-mock-key');
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    // Should now be on Home
    expect(find.text('A memory agent for your pet.'), findsOneWidget);
    // Key persisted to storage
    expect(await storage.read(), 'sk-ant-mock-key');
  });

  testWidgets('empty API key is rejected with an error message',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(FakeApiKeyStorage()),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Skip past welcome + privacy
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Submit an empty key
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a non-empty API key.'), findsOneWidget);
    // Still on the API key page, not Home
    expect(find.text('Connect to Anthropic'), findsOneWidget);
  });
}

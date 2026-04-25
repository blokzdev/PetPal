import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/wiki_io.dart';
import 'package:petpal/main.dart';

import '../../_helpers/fake_api_key_storage.dart';

class _NoopWiki implements WikiIo {
  @override
  Future<void> writeAtomic(String relPath, String body) async {}
  @override
  Future<String> read(String relPath) async => '';
  @override
  Future<List<String>> listForPet(int petId) async => const [];
  @override
  String petDir(int petId) => 'wiki/$petId';
  @override
  String soulPath(int petId) => 'wiki/$petId/SOUL.md';
}

List<Override> _dataOverrides() => [
      appDatabaseProvider.overrideWith((ref) async {
        final db = AppDatabase(NativeDatabase.memory());
        ref.onDispose(() async => db.close());
        return db;
      }),
      wikiIoProvider.overrideWith((ref) async => _NoopWiki()),
    ];

void main() {
  testWidgets('walking forward through onboarding leaves the welcome screen '
      'and persists the key', (tester) async {
    final storage = FakeApiKeyStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(storage),
          ..._dataOverrides(),
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

    // Onboarding must be gone — assert via the welcome string, not via
    // Home internals (Home depends on the data layer this test doesn't
    // care about).
    expect(find.text('Welcome to PetPal'), findsNothing);
    expect(find.text('Connect to Anthropic'), findsNothing);
    // Key persisted to storage.
    expect(await storage.read(), 'sk-ant-mock-key');
  });

  testWidgets('empty API key is rejected with an error message',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(FakeApiKeyStorage()),
          ..._dataOverrides(),
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

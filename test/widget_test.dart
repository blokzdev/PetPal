import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/wiki_io.dart';
import 'package:petpal/main.dart';

import '_helpers/fake_api_key_storage.dart';

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
  testWidgets('Onboarded user with no pet sees the empty-state Home',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          ..._dataOverrides(),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PetPal'), findsNWidgets(2));
    expect(
      find.text("PetPal remembers your pet's life so you don't have to."),
      findsOneWidget,
    );
    expect(find.text('Add your pet'), findsOneWidget);
  });

  testWidgets('Unonboarded user lands on the welcome page', (tester) async {
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

    expect(find.text('Welcome to PetPal'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });
}

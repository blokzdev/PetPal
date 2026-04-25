import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/wiki_io.dart';
import 'package:petpal/main.dart';

import '../../_helpers/fake_api_key_storage.dart';

class _CapturingWiki implements WikiIo {
  final Map<String, String> writes = {};

  @override
  Future<void> writeAtomic(String relPath, String body) async {
    writes[relPath] = body;
  }

  @override
  Future<String> read(String relPath) async => writes[relPath] ?? '';

  @override
  Future<List<String>> listForPet(int petId) async => [];

  @override
  String petDir(int petId) => 'wiki/$petId';

  @override
  String soulPath(int petId) => 'wiki/$petId/SOUL.md';
}

ProviderContainer _setupOverrides({
  required AppDatabase db,
  required WikiIo wiki,
  required FakeApiKeyStorage storage,
}) {
  return ProviderContainer(
    overrides: [
      apiKeyStorageProvider.overrideWithValue(storage),
      appDatabaseProvider.overrideWith((ref) async {
        ref.onDispose(() async => db.close());
        return db;
      }),
      wikiIoProvider.overrideWith((ref) async => wiki),
    ],
  );
}

void main() {
  late AppDatabase db;
  late _CapturingWiki wiki;
  late FakeApiKeyStorage storage;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    wiki = _CapturingWiki();
    storage = FakeApiKeyStorage(initial: 'sk-ant-test');
    container = _setupOverrides(db: db, wiki: wiki, storage: storage);
  });

  tearDown(() => container.dispose());

  testWidgets('empty Home shows "Add your pet" CTA', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add your pet'), findsOneWidget);
  });

  testWidgets('add-pet form requires a name', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add your pet'));
    await tester.pumpAndSettle();

    // Submit with empty name
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsOneWidget);
    // Still on the add-pet screen (no pet was created)
    expect(find.text('Add a pet'), findsOneWidget);
  });

  testWidgets('saving a pet creates the row, seeds SOUL.md, and routes Home '
      'with the pet greeted', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add your pet'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Milo',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Species'),
      'dog',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Breed (optional)'),
      'mixed',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Pet row exists
    final pets = await db.select(db.pets).get();
    expect(pets, hasLength(1));
    expect(pets.first.name, 'Milo');

    // SOUL.md was seeded
    final soul = wiki.writes['wiki/${pets.first.id}/SOUL.md'];
    expect(soul, isNotNull);
    expect(soul!, contains('# Milo'));
    expect(soul, contains('species: dog'));
    expect(soul, contains('breed: mixed'));

    // Home reflects the new pet
    expect(find.text('Milo'), findsOneWidget);
  });

  testWidgets('free-tier gate: AddPetScreen blocks a second pet '
      '(DECISIONS row 8)', (tester) async {
    // Pre-seed a pet so the free-tier limit is hit.
    await db.into(db.pets).insert(
          PetsCompanion.insert(
            name: 'Milo',
            createdAt: DateTime(2026, 4, 25),
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Force-navigate to /pets/add (the empty-state CTA is hidden when a
    // pet exists, but a deep-link or future pet switcher could land
    // here).
    BuildContext deeplinkCtx = tester.element(find.text('Milo'));
    GoRouter.of(deeplinkCtx).push('/pets/add');
    await tester.pumpAndSettle();

    expect(find.textContaining('You already have a pet'), findsOneWidget);
    // No form fields rendered.
    expect(find.widgetWithText(TextFormField, 'Name'), findsNothing);
  });
}

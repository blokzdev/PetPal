import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/active_pet/active_pet_notifier.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/platform/settings_storage.dart';

/// Phase 7 task E.2 — active-pet notifier + the resolved
/// `activePetIdProvider` / `activePetProvider` fallback semantics.
void main() {
  late AppDatabase db;
  late InMemorySettingsStorage settings;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = InMemorySettingsStorage();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async {
          ref.onDispose(() async => db.close());
          return db;
        }),
        settingsStorageProvider.overrideWithValue(settings),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<int> seedPet({required String name, DateTime? createdAt}) async {
    return db.into(db.pets).insert(
          PetsCompanion.insert(
            name: name,
            createdAt: createdAt ?? DateTime(2026, 4, 25),
          ),
        );
  }

  test('notifier defaults to null when SharedPreferences key is unset',
      () async {
    final id = await container.read(activePetSelectionProvider.future);
    expect(id, isNull);
  });

  test('notifier loads the persisted ID on build', () async {
    await settings.setInt('active_pet_id', 42);
    final id = await container.read(activePetSelectionProvider.future);
    expect(id, 42);
  });

  test('select() persists + emits the new ID', () async {
    await container.read(activePetSelectionProvider.future);
    await container
        .read(activePetSelectionProvider.notifier)
        .select(7);
    expect(container.read(activePetSelectionProvider).valueOrNull, 7);
    expect(await settings.getInt('active_pet_id'), 7);
  });

  test('activePetIdProvider falls back to pets.last.id when no '
      'selection persisted', () async {
    await seedPet(name: 'Milo', createdAt: DateTime(2026, 4, 10));
    final lastId =
        await seedPet(name: 'Loki', createdAt: DateTime(2026, 4, 20));
    await container.read(petsProvider.future);
    await container.read(activePetSelectionProvider.future);
    expect(container.read(activePetIdProvider)(), lastId);
  });

  test('activePetIdProvider honours persisted selection when the pet '
      'still exists', () async {
    final firstId =
        await seedPet(name: 'Milo', createdAt: DateTime(2026, 4, 10));
    await seedPet(name: 'Loki', createdAt: DateTime(2026, 4, 20));
    await settings.setInt('active_pet_id', firstId);
    await container.read(petsProvider.future);
    await container.read(activePetSelectionProvider.future);
    expect(container.read(activePetIdProvider)(), firstId);
  });

  test('activePetIdProvider falls back when the persisted ID no longer '
      'matches an existing pet (pet was deleted)', () async {
    final loki =
        await seedPet(name: 'Loki', createdAt: DateTime(2026, 4, 20));
    // Persisted ID points at a pet that never existed (or was deleted).
    await settings.setInt('active_pet_id', 9999);
    await container.read(petsProvider.future);
    await container.read(activePetSelectionProvider.future);
    expect(container.read(activePetIdProvider)(), loki);
  });

  test('activePetIdProvider throws StateError when no pets exist',
      () async {
    await container.read(petsProvider.future);
    expect(
      () => container.read(activePetIdProvider)(),
      throwsA(isA<StateError>()),
    );
  });

  test('activePetProvider returns the resolved Pet, falls back to '
      'pets.last when no selection persisted', () async {
    await seedPet(name: 'Milo', createdAt: DateTime(2026, 4, 10));
    final lokiId =
        await seedPet(name: 'Loki', createdAt: DateTime(2026, 4, 20));
    await container.read(petsProvider.future);
    await container.read(activePetSelectionProvider.future);
    final pet = container.read(activePetProvider);
    expect(pet, isNotNull);
    expect(pet!.id, lokiId);
  });

  test('activePetProvider returns null when no pets exist', () async {
    await container.read(petsProvider.future);
    expect(container.read(activePetProvider), isNull);
  });

  test('activePetProvider follows the persisted selection', () async {
    final miloId =
        await seedPet(name: 'Milo', createdAt: DateTime(2026, 4, 10));
    await seedPet(name: 'Loki', createdAt: DateTime(2026, 4, 20));
    await settings.setInt('active_pet_id', miloId);
    await container.read(petsProvider.future);
    await container.read(activePetSelectionProvider.future);
    expect(container.read(activePetProvider)?.id, miloId);
  });
}

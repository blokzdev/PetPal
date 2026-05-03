import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:petpal/app/active_pet/active_pet_notifier.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/app/widgets/pet_switcher.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/platform/settings_storage.dart';

/// Phase 7 task E.2 — pet switcher widget tests. Covers the
/// bottom-sheet renderer, the title chevron visibility rule, and
/// the side-effect of selecting a pet (writes through to
/// `activePetSelectionProvider`).
void main() {
  late AppDatabase db;
  late InMemorySettingsStorage settings;

  Future<int> seedPet({required String name}) {
    return db.into(db.pets).insert(
          PetsCompanion.insert(name: name, createdAt: DateTime(2026, 4, 25)),
        );
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = InMemorySettingsStorage();
  });

  tearDown(() async => db.close());

  Widget testApp({required Widget home}) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => home),
        GoRoute(
          path: '/pets/add',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('add-pet-route'))),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async {
          ref.onDispose(() async {});
          return db;
        }),
        settingsStorageProvider.overrideWithValue(settings),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('PetSwitcherTitle hides the chevron when only one pet exists',
      (tester) async {
    await seedPet(name: 'Milo');
    await tester.pumpWidget(
      testApp(
        home: Scaffold(
          appBar: AppBar(
            title: PetSwitcherTitle(
              titleBuilder: (p) => "${p.name}'s profile",
              fallbackTitle: 'Profile',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Milo's profile"), findsOneWidget);
    // No chevron icon when there's nowhere to switch to. The switcher
    // sheet is a bottom-sheet that doesn't pre-render, so absence is
    // verified by tapping the title and finding nothing.
    await tester.tap(find.text("Milo's profile"));
    await tester.pumpAndSettle();
    expect(find.text('Switch pet'), findsNothing);
  });

  testWidgets('PetSwitcherTitle opens the sheet on tap when multiple pets '
      'exist, and selecting a pet writes through to '
      'activePetSelectionProvider', (tester) async {
    final miloId = await seedPet(name: 'Milo');
    final lokiId = await seedPet(name: 'Loki');
    await settings.setInt('active_pet_id', miloId);

    await tester.pumpWidget(
      testApp(
        home: Scaffold(
          appBar: AppBar(
            title: PetSwitcherTitle(
              titleBuilder: (p) => "${p.name}'s profile",
              fallbackTitle: 'Profile',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Milo's profile"), findsOneWidget);

    await tester.tap(find.text("Milo's profile"));
    await tester.pumpAndSettle();
    expect(find.text('Switch pet'), findsOneWidget);
    expect(find.text('Milo'), findsOneWidget);
    expect(find.text('Loki'), findsOneWidget);
    // "All pets" is journal-only — title switcher should NOT include it.
    expect(find.text('All pets'), findsNothing);

    await tester.tap(find.text('Loki'));
    await tester.pumpAndSettle();
    expect(await settings.getInt('active_pet_id'), lokiId);
    // Title rebuilds against the new active pet.
    expect(find.text("Loki's profile"), findsOneWidget);
  });

  testWidgets('showPetSwitcherSheet returns PickedAllPets when "All pets" '
      'tapped (includeAllPets: true)', (tester) async {
    await seedPet(name: 'Milo');
    await seedPet(name: 'Loki');

    PetSwitcherChoice? captured;
    await tester.pumpWidget(
      testApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showPetSwitcherSheet(
                    ctx,
                    currentSelection: const PickedAllPets(),
                    includeAllPets: true,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('All pets'), findsOneWidget);
    await tester.tap(find.text('All pets'));
    await tester.pumpAndSettle();
    expect(captured, isA<PickedAllPets>());
  });

  testWidgets('"Add pet" tile in the sheet pops + routes to /pets/add',
      (tester) async {
    await seedPet(name: 'Milo');
    await tester.pumpWidget(
      testApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showPetSwitcherSheet(
                  ctx,
                  currentSelection: const PickedPet(1),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Add pet'), findsOneWidget);
    await tester.tap(find.text('Add pet'));
    await tester.pumpAndSettle();
    expect(find.text('add-pet-route'), findsOneWidget);
  });
}

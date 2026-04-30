import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/onboarding_templates.dart';
import 'package:petpal/data/species_catalog.dart';
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

  @override
  Future<void> writeBytesAtomic(String relPath, Uint8List bytes) =>
      throw UnimplementedError('photo write not used in this test');
  @override
  Future<Uint8List> readBytes(String relPath) =>
      throw UnimplementedError('photo read not used in this test');
  @override
  Future<void> deleteIfExists(String relPath) async {}
  @override
  Future<int> bytesForPet(int petId) async => 0;
}

/// Rich in-memory template that mirrors the placeholder set the real
/// `assets/onboarding/dog.md` ships with after 5.5.4 schema prep. Used
/// by the end-to-end widget tests that thread sex / neutered /
/// relationship / weight / about-petpal-should-know all the way to a
/// captured SOUL.md.
const _richDogTemplate =
    '---\n'
    'category: dog\n'
    'breed: {breed}\n'
    'sex: {sex}\n'
    'neutered: {neutered}\n'
    'relationship: {relationship}\n'
    'working_role: {working_role}\n'
    'rehab_context: {rehab_context}\n'
    'dob: {dob}\n'
    'dob_approx: {dob_approx}\n'
    'adoption_date: {adoption_date}\n'
    'intake_date: {intake_date}\n'
    'expected_release_date: {expected_release_date}\n'
    'weight_kg: {weight_kg}\n'
    '---\n'
    '# {name}\n'
    'A line of canned welcome prose.\n'
    '\n'
    '{about_petpal_should_know}\n';

/// Rich exotic template — used by the 5.5.6 freeform-species test that
/// expects `category: exotic` + `species: <freeform-text>` in the
/// captured SOUL.
const _richExoticTemplate =
    '---\n'
    'category: exotic\n'
    'species: {species}\n'
    'breed: {breed}\n'
    '---\n'
    '# {name}\n'
    "{name} doesn't fit one of PetPal's standard species.\n";

ProviderContainer _setupOverrides({
  required AppDatabase db,
  required WikiIo wiki,
  required FakeApiKeyStorage storage,
  bool richTemplates = false,
  SpeciesCatalog? catalog,
}) {
  return ProviderContainer(
    overrides: [
      apiKeyStorageProvider.overrideWithValue(storage),
      appDatabaseProvider.overrideWith((ref) async {
        ref.onDispose(() async => db.close());
        return db;
      }),
      wikiIoProvider.overrideWith((ref) async => wiki),
      // Inject an in-memory onboarding-template source covering every
      // species, so the AddPetScreen save path doesn't try to hit
      // rootBundle (no asset bundle in widget tests).
      onboardingTemplatesProvider.overrideWithValue(
        InMemoryOnboardingTemplates({
          for (final s in Category.values)
            s: richTemplates && s == Category.dog
                ? _richDogTemplate
                : richTemplates && s == Category.exotic
                    ? _richExoticTemplate
                    : '---\ncategory: ${s.id}\nbreed: {breed}\n---\n# {name}\n',
        }),
      ),
      if (catalog != null) speciesCatalogProvider.overrideWithValue(catalog),
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
    // 5.5.4 expanded the form (relationship + sub-classification) past
    // the default 800x600 surface, pushing Save off-viewport. Resize so
    // the whole form fits without needing scroll plumbing in the test.
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
    // Category dropdown defaults to "Dog" (Phase 3.4); no need to tap.
    // Without a species pick, the form falls through to the universal
    // "Variety (optional)" freeform text field (DECISIONS row 47 lock).
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Variety (optional)'),
      'mixed',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Pet row exists
    final pets = await db.select(db.pets).get();
    expect(pets, hasLength(1));
    expect(pets.first.name, 'Milo');

    // SOUL.md was seeded from the dog template
    final soul = wiki.writes['wiki/${pets.first.id}/SOUL.md'];
    expect(soul, isNotNull);
    expect(soul!, contains('# Milo'));
    expect(soul, contains('category: dog'));
    expect(soul, contains('breed: mixed'));

    // Home reflects the new pet
    expect(find.text('Milo'), findsOneWidget);
  });

  testWidgets('Bug 1 regression: a phone-shaped scroll viewport that '
      'unmounts the Name field still rejects empty-name save (no '
      'pet row, no SOUL.md write). Reproduces the on-device bug '
      'where ListView lazy-mounting let the Name validator skip '
      'and produced SOUL files with an empty `# {name}` header.',
      (tester) async {
    // Default phone-ish surface — small enough that the Name field
    // scrolls out of viewport when Save comes into view. (The other
    // 5.5.4+ tests deliberately oversize to 900x1600 so the whole
    // form fits without scrolling — keeping THIS test on a
    // realistic surface is the whole point.)
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add your pet'));
    await tester.pumpAndSettle();

    // Scroll the form's scrollable until Save is visible. We
    // explicitly scope to the Form's descendant Scrollable — there
    // are multiple Scrollables in PetPalApp's widget tree — and on
    // a 400x700 surface Save sits well below the viewport. The
    // defense-in-depth name guard in `_save()` is what makes this
    // test pass: even if a future refactor reintroduces the
    // lazy-mount bug, the guard catches the empty-name case before
    // any SOUL.md write.
    // Several descendants of `Form` are themselves `Scrollable`
    // (each TextFormField owns one for caret overflow, etc.); the
    // form's own SingleChildScrollView is the FIRST in widget-tree
    // order. Take `.first` and pass that as the scroll source.
    final formScrollable = find
        .descendant(
          of: find.byType(Form),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Save'),
      200,
      scrollable: formScrollable,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // No pet row, no SOUL.md write — the defense-in-depth guard
    // catches the empty name even if the Form's validate() pass
    // missed it.
    final pets = await db.select(db.pets).get();
    expect(pets, isEmpty,
        reason: 'Empty-name save must not reach the database.');
    expect(wiki.writes, isEmpty,
        reason: 'Empty-name save must not write a SOUL.md file.');

    // Inline error surface — `_saveError` renders.
    expect(find.text('Name is required.'), findsOneWidget);
  });

  testWidgets('5.5.4: relationship=rescue-rehab reveals intake + '
      'expected-release date pickers; switching back hides them',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add your pet'));
    await tester.pumpAndSettle();

    // Default relationship = pet → no intake / release pickers.
    expect(find.text('Pick intake date'), findsNothing);
    expect(find.text('Pick expected release date'), findsNothing);

    // Pick "Rescue / rehab" — AnimatedSwitcher reveals the conditional
    // date pickers within the About card.
    await tester.tap(find.text('Rescue / rehab'));
    await tester.pumpAndSettle();
    expect(find.text('Pick intake date'), findsOneWidget);
    expect(find.text('Pick expected release date'), findsOneWidget);

    // Back to "Pet" → pickers hide again.
    await tester.tap(find.text('Pet'));
    await tester.pumpAndSettle();
    expect(find.text('Pick intake date'), findsNothing);
    expect(find.text('Pick expected release date'), findsNothing);
  });

  testWidgets('5.5.4: a fully-filled form threads sex / neutered / '
      'weight / in-your-words into the rendered SOUL', (tester) async {
    // Swap in the rich template so the placeholders the new fields
    // target are present.
    container.dispose();
    container = _setupOverrides(
      db: db,
      wiki: wiki,
      storage: storage,
      richTemplates: true,
    );

    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
      find.widgetWithText(TextFormField, 'Variety (optional)'),
      'rescue mutt',
    );

    // Sex = Female; Neutered = Yes — both are the visible
    // SegmentedButton labels on those rows.
    await tester.tap(find.text('Female'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    // Weight in kg.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Weight (kg)'),
      '14.2',
    );

    // In your words.
    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'e.g. Loki is a rescue mutt who came home in October 2023. '
        'Afraid of skateboards, soft for frozen carrots.',
      ),
      'Soft for frozen carrots.',
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final pets = await db.select(db.pets).get();
    expect(pets, hasLength(1));
    final soul = wiki.writes['wiki/${pets.first.id}/SOUL.md'];
    expect(soul, isNotNull);
    expect(soul!, contains('# Milo'));
    expect(soul, contains('breed: rescue mutt'));
    expect(soul, contains('sex: female'));
    expect(soul, contains('neutered: yes'));
    expect(soul, contains('relationship: pet'));
    expect(soul, contains('weight_kg: 14.2'));
    expect(soul, contains('Soft for frozen carrots.'));
    // Defaults stripped on disk.
    expect(soul, isNot(contains('working_role:')));
    expect(soul, isNot(contains('rehab_context:')));
    expect(soul, isNot(contains('intake_date:')));
    expect(soul, isNot(contains('expected_release_date:')));
  });

  testWidgets('5.5.6: "Other (type your own)" routes a freeform species '
      'to category=exotic in the SOUL, regardless of the picked '
      'category', (tester) async {
    // Inject a minimal in-memory catalog so the picker sheet renders.
    container.dispose();
    container = _setupOverrides(
      db: db,
      wiki: wiki,
      storage: storage,
      richTemplates: true,
      catalog: InMemorySpeciesCatalog(const {
        // Empty entries means the picker just shows the "Other" tile —
        // exactly the tail-row path 5.5.6 wires through.
        'dog': [],
      }),
    );

    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
      'Specimen',
    );

    // Open the species picker. Category defaults to Dog; we'll deny
    // every entry the freeform path so the test passes through "Other".
    await tester.tap(find.text('Tap to pick a species'));
    await tester.pumpAndSettle();

    // Tap the freeform tail row. Exact-match `find.text` here, not
    // `textContaining` — the empty-results hint in the picker also
    // contains the substring 'Other (type your own)' (in quotes).
    await tester.tap(find.text('Other (type your own)'));
    await tester.pumpAndSettle();

    // The new prompt copy lands on the freeform input.
    expect(
      find.widgetWithText(
        TextFormField,
        'Type the species — common names work.',
      ),
      findsOneWidget,
    );

    // Type a freeform species and save.
    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'Type the species — common names work.',
      ),
      'tegu',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The captured SOUL.md routes through the exotic template even
    // though the user picked Dog at the category step. The freeform
    // species text flows through to `species:`. Per ROADMAP 5.5.6.
    // (Category lives in SOUL frontmatter, not the pets DB row — the
    // pets table only stores id / name / createdAt.)
    final pets = await db.select(db.pets).get();
    expect(pets, hasLength(1));
    final soul = wiki.writes['wiki/${pets.first.id}/SOUL.md'];
    expect(soul, isNotNull);
    expect(soul!, contains('category: exotic'));
    expect(soul, contains('species: tegu'));
    expect(soul, isNot(contains('category: dog')));
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
    final deeplinkCtx = tester.element(find.text('Milo'));
    unawaited(GoRouter.of(deeplinkCtx).push('/pets/add'));
    await tester.pumpAndSettle();

    expect(find.textContaining('You already have a pet'), findsOneWidget);
    // No form fields rendered.
    expect(find.widgetWithText(TextFormField, 'Name'), findsNothing);
  });
}

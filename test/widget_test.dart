import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
  // Phase 6 task 6.1 — photo storage surface. The widget tests don't
  // exercise photo paths; throw on call so an accidental traversal
  // surfaces in the test, rather than silently no-op'ing.
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

List<Override> _dataOverrides({String? withPetNamed}) => [
      appDatabaseProvider.overrideWith((ref) async {
        final db = AppDatabase(NativeDatabase.memory());
        if (withPetNamed != null) {
          await db.into(db.pets).insert(
                PetsCompanion.insert(
                  name: withPetNamed,
                  createdAt: DateTime(2026, 4, 27),
                ),
              );
        }
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
    // 5.8 — the greeting slot is wrapped in an AnimatedSwitcher so
    // the empty-state ↔ named-pet transition fades cleanly. The
    // child carries a stable ValueKey ('empty' here) so the switcher
    // sees an identity change when the user adds their first pet.
    // Phase 5.6 Commit C upgraded the duration to Motion.medium
    // (300 ms) and the in-curve to Motion.springCurve so the
    // identity change reads as a settled-in transition rather than
    // a flat fade.
    final switcher = tester.widget<AnimatedSwitcher>(
      find.ancestor(
        of: find.text('Add your pet'),
        matching: find.byType(AnimatedSwitcher),
      ).first,
    );
    expect(switcher.duration, const Duration(milliseconds: 300));
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

    // Task 5.6 redesign — narrative-led welcome. The tagline IS the
    // headline; "Welcome to PetPal" is gone.
    expect(
      find.text("PetPal remembers your pet's life so you don't have to."),
      findsOneWidget,
    );
    expect(find.text('Get started'), findsOneWidget);
  });

  // -------------------------------------------------------------------
  // Task 5.10 — per-pet home greeting hero. User-locked composition is
  // "centered name on gradient sweep"; user-locked copy is "Loki" —
  // the name itself, displayed in display-class type. The hero zone
  // sits above the body via AppScaffold.hero (5.5). Empty-state Home
  // (test above) collapses the hero so the existing tagline + Add CTA
  // continue to read full-bleed.
  // -------------------------------------------------------------------
  testWidgets('Onboarded user with a pet sees the hero greeting (name '
      'as the greeting; gradient backdrop)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          ..._dataOverrides(withPetNamed: 'Loki'),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The pet name appears prominently (the hero) AND inside the
    // body's button labels ("Chat with Loki"). Either way the name
    // is the greeting — matches the user-locked "Loki" copy pick.
    expect(find.text('Loki'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Chat with Loki'),
        findsOneWidget);

    // Hero composition: a DecoratedBox with a LinearGradient fills the
    // 120dp zone above the body. Find it via the gradient-bearing
    // decoration so the assertion is structural, not pixel-based.
    final heroBox = tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    ).firstWhere(
      (w) => w.decoration is BoxDecoration &&
             (w.decoration as BoxDecoration).gradient is LinearGradient,
      orElse: () => throw TestFailure(
        'expected a DecoratedBox with a LinearGradient (the hero) '
        'above the body when a pet is present',
      ),
    );
    final gradient = (heroBox.decoration as BoxDecoration).gradient
        as LinearGradient;
    expect(gradient.colors.length, 2,
        reason: 'gradient is a two-stop sweep, top → bottom');

    // Pre-Phase-6 placeholder — the old Icons.pets header is gone
    // from the body now that the hero owns "this is your pet".
    // Keep the assertion forward-compatible by counting: there
    // should be no Icons.pets directly on the home body. (The
    // empty-state still uses it; this test runs the named-pet path.)
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byIcon(PhosphorIconsRegular.pawPrint),
      ),
      findsNothing,
    );

    // Old "PetPal remembers Loki's life so you don't have to." line
    // stays in the body — the hero is name-only, the tagline is
    // body-only. Two separate registers.
    expect(
      find.text("PetPal remembers Loki's life so you don't have to."),
      findsOneWidget,
    );
  });

  // -----------------------------------------------------------------
  // Bug 2 regression — defensive empty-name handling on Home. With a
  // pet whose `name` is empty / whitespace, no surface should emit
  // orphan punctuation: the tagline "PetPal remembers 's life so..."
  // and the CTA "Chat with " (trailing space) were the user-reported
  // failure modes from on-device verification.
  // -----------------------------------------------------------------
  testWidgets('Bug 2 regression: empty-name pet renders Home with the '
      '"Your pet" fallback — no orphan apostrophe in tagline, no '
      'trailing space in chat CTA, hero shows the placeholder',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          // Empty name — the failure mode that surfaced on-device.
          ..._dataOverrides(withPetNamed: ''),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Tagline: "PetPal remembers Your pet's life..." — NOT
    // "PetPal remembers 's life..." with the orphan apostrophe.
    expect(
      find.text(
        "PetPal remembers Your pet's life so you don't have to.",
      ),
      findsOneWidget,
      reason: 'displayPetName must replace empty pet.name with the '
          '"Your pet" fallback in the home tagline.',
    );
    expect(
      find.text("PetPal remembers 's life so you don't have to."),
      findsNothing,
      reason: 'orphan apostrophe must never reach the tagline.',
    );

    // Chat CTA: "Chat with Your pet" — no trailing-space artefact.
    expect(
      find.widgetWithText(FilledButton, 'Chat with Your pet'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Chat with '),
      findsNothing,
    );

    // Hero greeting: shows the placeholder, not blank.
    expect(find.text('Your pet'), findsWidgets);
  });

  // -----------------------------------------------------------------
  // Task 5.12 — home destinations land as a 2-col PetCard grid below
  // the primary CTA (user-locked). The five tile labels (Journal,
  // Profile, Reminders, Care guides, Settings) replace the previous
  // OutlinedButton.icon stack; the chat CTA stays as a FilledButton
  // above the grid.
  // -----------------------------------------------------------------
  testWidgets('home destinations render as a 2-col PetCardButton grid '
      'below the chat CTA', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          ..._dataOverrides(withPetNamed: 'Loki'),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The chat CTA stays as a FilledButton above the grid.
    expect(find.widgetWithText(FilledButton, 'Chat with Loki'),
        findsOneWidget);

    // The five destinations all render as cards. Tap-handler comes
    // from PetCardButton, not OutlinedButton — assert by type +
    // label (the previous 'Open journal' / 'Edit profile' verbose
    // labels collapsed to 'Journal' / 'Profile' to fit the tile
    // grid).
    for (final label in const [
      'Journal',
      'Profile',
      'Reminders',
      'Care guides',
      'Settings',
    ]) {
      expect(find.text(label), findsOneWidget,
          reason: 'destination "$label" is missing');
    }

    // The OutlinedButton.icon stack is gone — no OutlinedButton
    // should be present on home in release-mode-equivalent state.
    // (Debug-only adds a Dev tile, also a PetCardButton, not an
    // OutlinedButton — so this assertion holds in test mode.)
    expect(find.byType(OutlinedButton), findsNothing,
        reason: 'home destinations should be cards, not outlined '
            'buttons (5.12)');

    // The grid uses GridView.count with crossAxisCount: 2.
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
  });
}

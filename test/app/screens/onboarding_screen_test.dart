import 'dart:typed_data';

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

List<Override> _dataOverrides() => [
      appDatabaseProvider.overrideWith((ref) async {
        final db = AppDatabase(NativeDatabase.memory());
        ref.onDispose(() async => db.close());
        return db;
      }),
      wikiIoProvider.overrideWith((ref) async => _NoopWiki()),
    ];

void main() {
  // Strings that the task 5.6 redesign locks in. If a future copy
  // refresh changes these, update both this fixture and the fixtures
  // under VOICE.md §6 (the canonical onboarding examples).
  const welcomeTagline =
      "PetPal remembers your pet's life so you don't have to.";
  const privacyHeadline = 'Your data, your device.';
  const privacyJournalSection = "Your pet's journal.";
  const privacyChatSection = 'When you chat.';
  const privacyFooterStart = 'PetPal is software, not a vet';
  const apiKeyHeadline = 'One last thing — your Anthropic key.';

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

    // Page 1: narrative-led welcome (tagline is the headline now).
    expect(find.text(welcomeTagline), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // Page 2: sectioned plain-English privacy disclosure.
    expect(find.text(privacyHeadline), findsOneWidget);
    expect(find.text(privacyJournalSection), findsOneWidget);
    expect(find.text(privacyChatSection), findsOneWidget);
    expect(find.textContaining('leaves the phone'), findsOneWidget);
    expect(find.textContaining(privacyFooterStart), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Page 3: "One last thing — your Anthropic key" utility framing.
    expect(find.text(apiKeyHeadline), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'sk-ant-mock-key');
    await tester.tap(find.text('Save and continue'));
    await tester.pumpAndSettle();

    // Onboarding must be gone — assert via onboarding-unique copy.
    // The welcome tagline ("PetPal remembers...") is intentionally
    // shared with the Home empty-state per VOICE.md §6 ex 6 (brand
    // consistency between cold-start surfaces), so it survives the
    // navigation. The API key headline + "Save and continue" CTA
    // are onboarding-only.
    expect(find.text(apiKeyHeadline), findsNothing);
    expect(find.text('Save and continue'), findsNothing);
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
    expect(find.text(apiKeyHeadline), findsOneWidget);
  });

  // ---------------------------------------------------------------
  // Task 5.6 invariants: the design choices the user locked in the
  // 5.6 design questions. If any of these change, the user picked
  // a different option and this fixture should be reviewed against
  // the new choice.
  // ---------------------------------------------------------------

  testWidgets('welcome page is narrative-led — the journal-+-paw mark '
      'sits above the tagline', (tester) async {
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

    // The narrative-led pick uses an Image.asset of the icon
    // foreground; assert the asset is referenced. Image asset
    // resolution itself is exercised by the rasterized widget tests
    // (the icon bytes ship under assets/branding/ and the pubspec
    // declares the directory).
    final image = find.byType(Image);
    expect(image, findsOneWidget);
    final widget = tester.widget<Image>(image);
    final provider = widget.image as AssetImage;
    expect(provider.assetName, 'assets/branding/icon-foreground.png');
  });

  testWidgets('privacy page uses sectioned plain-English '
      '(two sub-headers, not bullets)', (tester) async {
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
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // The sectioned layout shows BOTH sub-headers as standalone Text
    // widgets — a bullet-list pick wouldn't have these as separate
    // headings.
    expect(find.text(privacyJournalSection), findsOneWidget);
    expect(find.text(privacyChatSection), findsOneWidget);
    // Body sentences sit under each header.
    expect(find.textContaining("doesn't copy it to a server"),
        findsOneWidget);
    expect(find.textContaining("Anthropic's Claude using your API key"),
        findsOneWidget);
  });

  testWidgets('API key page is framed as utility, not welcome '
      '(headline starts with "One last thing")', (tester) async {
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
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text(apiKeyHeadline), findsOneWidget);
    // The CTA reads "Save and continue" — utility verb, not the
    // brand-name "Connect" or generic "Continue" alone.
    expect(find.text('Save and continue'), findsOneWidget);
    // The body explains Claude + Anthropic in plain language.
    expect(
      find.textContaining('PetPal runs on Claude, made by Anthropic'),
      findsOneWidget,
    );
  });

  testWidgets('Phase 5 honesty invariant — privacy copy describes the '
      'BYOK-only path, not the Phase 7 proxy default', (tester) async {
    // PetPal does NOT yet host an LLM proxy (Phase 7 work). Until
    // it does, the privacy disclosure must describe the today-
    // reality: chat goes direct to Anthropic via the user's key.
    // The Phase-7 framing ("PetPal routes through our servers") is
    // misleading to ship now. When the proxy lands, this test +
    // the corresponding copy update need to land in the same commit.
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
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // Must mention API key + direct routing.
    expect(
      find.textContaining("Anthropic's Claude using your API key"),
      findsOneWidget,
    );
    // Must NOT claim PetPal-server-mediated routing — that's Phase 7.
    expect(find.textContaining("PetPal's servers"), findsNothing);
    expect(find.textContaining('through our servers'), findsNothing);
    expect(find.textContaining('200-message'), findsNothing);
  });
}

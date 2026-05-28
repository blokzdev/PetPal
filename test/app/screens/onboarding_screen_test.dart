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
import 'package:petpal/platform/settings_storage.dart';

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
  @override
  Future<void> deleteAll() async {}
}

List<Override> _dataOverrides({
  required InMemorySettingsStorage settings,
}) =>
    [
      appDatabaseProvider.overrideWith((ref) async {
        final db = AppDatabase(NativeDatabase.memory());
        ref.onDispose(() async => db.close());
        return db;
      }),
      wikiIoProvider.overrideWith((ref) async => _NoopWiki()),
      settingsStorageProvider.overrideWithValue(settings),
    ];

void main() {
  // Phase 7 task F.1 redesign: API-key page is gone — the proxy-
  // default monetization model (DECISIONS row 36) means a fresh-
  // install user is past onboarding without ever entering a key.
  // VOICE.md §6 example 15 is the locked privacy-page copy.
  const welcomeTagline =
      "PetPal remembers your pet's life so you don't have to.";
  const privacyHeadline = 'Your data, your device.';
  const privacyJournalSection = "Your pet's journal.";
  const privacyChatSection = 'How chat works.';
  const privacyFooterStart = 'PetPal is software, not a vet';

  testWidgets('two-page onboarding: welcome → privacy → Home '
      '(no API-key page; welcome flag persisted)', (tester) async {
    final settings = InMemorySettingsStorage();
    final storage = FakeApiKeyStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(storage),
          ..._dataOverrides(settings: settings),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Page 1: narrative-led welcome.
    expect(find.text(welcomeTagline), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // Page 2: VOICE.md §6 example 15 proxy-default privacy.
    expect(find.text(privacyHeadline), findsOneWidget);
    expect(find.text(privacyJournalSection), findsOneWidget);
    expect(find.text(privacyChatSection), findsOneWidget);
    expect(
      find.textContaining('200-message-a-month allowance'),
      findsOneWidget,
    );
    expect(
      find.textContaining('switch to your own Anthropic API key any '
          'time in Settings'),
      findsOneWidget,
    );
    expect(find.textContaining(privacyFooterStart), findsOneWidget);
    // The privacy page scrolls; its CTA sits below the fold in the
    // test viewport, so bring it on-screen before tapping.
    await tester.ensureVisible(find.text('Get started').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started').last);
    await tester.pumpAndSettle();

    // Onboarding finished: privacy headline gone; no key was ever
    // requested.
    expect(find.text(privacyHeadline), findsNothing);
    expect(await storage.read(), isNull);
    // Welcome flag persisted so the next launch skips onboarding.
    expect(await settings.getBool('welcome_completed'), isTrue);
  });

  testWidgets('migration: existing user with stored key skips onboarding',
      (tester) async {
    // Pre-Phase-7 onboarding mandated a key. Those users land on
    // F.1 with a stored key but no welcome flag. The notifier
    // auto-promotes them so they never see the new onboarding.
    final settings = InMemorySettingsStorage();
    final storage =
        FakeApiKeyStorage(initial: 'sk-ant-existing-mock-key-1234567890');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(storage),
          ..._dataOverrides(settings: settings),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Privacy / welcome copy is gone — the user landed past
    // onboarding (Home empty state).
    expect(find.text(privacyHeadline), findsNothing);
    // Migration persisted the welcome flag.
    expect(await settings.getBool('welcome_completed'), isTrue);
    // Existing key is still there (DECISIONS row 74 — keys persist
    // on upgrade).
    expect(await storage.read(),
        'sk-ant-existing-mock-key-1234567890');
  });

  // ---------------------------------------------------------------
  // Phase 7 task F.1 invariants — locked design choices.
  // ---------------------------------------------------------------

  testWidgets('welcome page is narrative-led — the journal-+-paw mark '
      'sits above the tagline', (tester) async {
    final settings = InMemorySettingsStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(FakeApiKeyStorage()),
          ..._dataOverrides(settings: settings),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The narrative-led pick uses an Image.asset of the icon
    // foreground; assert the asset is referenced.
    final image = find.byType(Image);
    expect(image, findsOneWidget);
    final widget = tester.widget<Image>(image);
    final provider = widget.image as AssetImage;
    expect(provider.assetName, 'assets/branding/icon-foreground.png');
  });

  testWidgets('Phase 7 honesty invariant — privacy copy describes the '
      'proxy-default + BYOK escape valve (VOICE.md §6 ex. 15)',
      (tester) async {
    // Phase 5 had a "BYOK-only" privacy copy. Phase 7 inverts it:
    // proxy default, BYOK lives in Settings as an opt-in. This test
    // pins the new copy so a future careless edit doesn't regress.
    final settings = InMemorySettingsStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(FakeApiKeyStorage()),
          ..._dataOverrides(settings: settings),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // VOICE.md §6 ex 15 locked language.
    expect(
      find.textContaining('PetPal routes that through our servers'),
      findsOneWidget,
    );
    expect(
      find.textContaining('200-message-a-month allowance'),
      findsOneWidget,
    );
    expect(
      find.textContaining('switch to your own Anthropic API key any '
          'time in Settings'),
      findsOneWidget,
    );
  });
}

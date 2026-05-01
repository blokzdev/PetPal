import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/main.dart';
import 'package:petpal/platform/settings_storage.dart';

import '../../_helpers/fake_api_key_storage.dart';
import '../../_helpers/scripted_llm_client.dart';
import '../../_helpers/test_provider_scope.dart';

void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  testWidgets('weekly summary toggle starts off, persists when flipped on',
      (tester) async {
    final settings = InMemorySettingsStorage();
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          settingsStorageProvider.overrideWithValue(settings),
          ...stack.overrides,
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Phase 6.6 task 6.6.A.3 — bottom nav replaces the home grid.
    // Tap the Hub tab → tap the Settings ListTile inside Hub.
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Hub'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final firstSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Weekly summary'),
    );
    expect(firstSwitch.value, isFalse,
        reason: 'weekly summary should default to off (Pro-tier)');

    // Task 5.12 — section grouping migrated to PetSectionHeader +
    // PetCard. The header text appears once (above the card); the
    // SwitchListTile + the run-now ListTile both live inside a
    // single Card surface (no surfaceContainerHigh band header).
    expect(find.text('Weekly summary'), findsWidgets,
        reason: 'PetSectionHeader title still reads "Weekly summary"');
    expect(
      find.ancestor(
        of: find.widgetWithText(SwitchListTile, 'Weekly summary'),
        matching: find.byType(Card),
      ),
      findsOneWidget,
      reason: 'switch lives inside the section card (5.12)');
    expect(
      find.ancestor(
        of: find.widgetWithText(
            ListTile, "Generate this week's summary now"),
        matching: find.byType(Card),
      ),
      findsOneWidget,
      reason: 'run-now row shares the section card (5.12)');

    await tester.tap(find.widgetWithText(SwitchListTile, 'Weekly summary'));
    await tester.pumpAndSettle();

    final afterToggle = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Weekly summary'),
    );
    expect(afterToggle.value, isTrue);

    // Underlying storage was updated.
    expect(await settings.getBool('weekly_digest_enabled'), isTrue);
  });

  testWidgets('preloaded "on" state shows the toggle as on', (tester) async {
    final settings =
        InMemorySettingsStorage({'weekly_digest_enabled': true});
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          settingsStorageProvider.overrideWithValue(settings),
          ...stack.overrides,
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Phase 6.6 task 6.6.A.3 — Hub tab → Settings sub-page.
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Hub'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final s = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Weekly summary'),
    );
    expect(s.value, isTrue);
  });
}

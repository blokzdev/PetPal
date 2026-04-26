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

    // Home → Settings.
    // Adding the Reminders button (task 4.10) pushed Settings below the
    // viewport in the test harness — scroll it in before tapping.
    await tester.ensureVisible(find.text('Settings'));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final firstSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Weekly summary'),
    );
    expect(firstSwitch.value, isFalse,
        reason: 'weekly summary should default to off (Pro-tier)');

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

    // Adding the Reminders button (task 4.10) pushed Settings below the
    // viewport in the test harness — scroll it in before tapping.
    await tester.ensureVisible(find.text('Settings'));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final s = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Weekly summary'),
    );
    expect(s.value, isTrue);
  });
}

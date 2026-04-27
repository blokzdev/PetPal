import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/harness/skills/skill_manifest.dart';
import 'package:petpal/harness/skills/skill_source.dart';
import 'package:petpal/main.dart';

import '../../_helpers/fake_api_key_storage.dart';
import '../../_helpers/scripted_llm_client.dart';
import '../../_helpers/test_provider_scope.dart';

class _FakeSkillSource implements SkillSource {
  _FakeSkillSource(this.manifests);
  final List<SkillManifest> manifests;

  @override
  Future<List<SkillSourceEntry>> list() async => [
        for (final m in manifests)
          SkillSourceEntry(
            manifest: m,
            readFragment: (_) async => '',
          ),
      ];
}

SkillManifest _manifest({
  required String id,
  required String name,
  List<String> species = const [],
}) {
  return SkillManifest(
    id: id,
    name: name,
    version: 1,
    species: species,
    triggers: const ['x'],
    loads: const [],
    requiresPro: false,
  );
}

void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  testWidgets('skill browser shows only species-applicable skills + lets '
      'the user toggle each one off and back on', (tester) async {
    // Inject a fake source with one dog-only, one cat-only, and one
    // universal skill. The seeded pet in buildChatTestStack is a dog
    // (species: dog SOUL.md), so the browser should show
    // puppy + universal-tracking, hide new-cat.
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
      skillSource: _FakeSkillSource([
        _manifest(id: 'puppy', name: 'Puppy', species: ['dog']),
        _manifest(id: 'new-cat', name: 'New Cat', species: ['cat']),
        _manifest(id: 'tracking', name: 'Universal Tracking'),
      ]),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          ...stack.overrides,
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Home → Care guides.
    await tester.ensureVisible(find.text('Care guides'));
    await tester.tap(find.text('Care guides'));
    await tester.pumpAndSettle();

    expect(find.text('Puppy'), findsOneWidget);
    expect(find.text('Universal Tracking'), findsOneWidget);
    // Cat-only skill is filtered out for our dog pet.
    expect(find.text('New Cat'), findsNothing);

    // Both visible skills start enabled (default).
    final puppySwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Puppy'),
    );
    expect(puppySwitch.value, isTrue);

    // Toggle Puppy off.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Puppy'));
    await tester.pumpAndSettle();

    final puppyAfter = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Puppy'),
    );
    expect(puppyAfter.value, isFalse);

    // Toggle back on.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Puppy'));
    await tester.pumpAndSettle();

    final puppyRestored = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Puppy'),
    );
    expect(puppyRestored.value, isTrue);
  });
}

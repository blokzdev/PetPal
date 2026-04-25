import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/main.dart';

import '../../_helpers/fake_api_key_storage.dart';
import '../../_helpers/scripted_llm_client.dart';
import '../../_helpers/test_provider_scope.dart';

void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  testWidgets('SOUL editor opens with existing frontmatter populated into '
      'the form fields and the body text', (tester) async {
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );
    final soulPath = stack.wiki.soulPath(stack.petId);

    // Replace the seeded SOUL.md with a richer one.
    await stack.wiki.writeAtomic(
      soulPath,
      '---\n'
      'species: dog\n'
      'breed: mixed\n'
      'dob: 2022-06-12\n'
      'weight_kg: 14.2\n'
      'allergies: [chicken]\n'
      'meds: []\n'
      "vet_contact: 'Dr. Patel'\n"
      'temperament: [anxious, food-motivated]\n'
      '---\n'
      '\n'
      '# Milo\n'
      'A rescue mutt.\n',
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

    await tester.tap(find.text('Edit SOUL'));
    await tester.pumpAndSettle();

    // Form populates from the parsed frontmatter. Field order:
    // 0 species, 1 breed, 2 dob, 3 weight, 4 allergies, 5 meds,
    // 6 vet_contact, 7 temperament, 8 body.
    String fieldText(int i) =>
        tester.widget<TextField>(find.byType(TextField).at(i)).controller!.text;
    expect(fieldText(0), 'dog');
    expect(fieldText(1), 'mixed');
    expect(fieldText(2), '2022-06-12');
    expect(fieldText(3), '14.2');
    expect(fieldText(4), 'chicken');
    expect(fieldText(5), '');
    expect(fieldText(6), 'Dr. Patel');
    expect(fieldText(7), 'anxious, food-motivated');
    // Body field carries the prose after the closing ---.
    expect(fieldText(8), contains('# Milo'));
    expect(fieldText(8), contains('A rescue mutt.'));
  });
}

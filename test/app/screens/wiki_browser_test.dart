import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/database.dart';
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

  testWidgets('wiki browser shows entries grouped by type and opens an '
      'entry on tap', (tester) async {
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );

    // Seed three entries spanning two types so grouping is exercised.
    await stack.db.into(stack.db.entries).insert(
          EntriesCompanion.insert(
            petId: stack.petId,
            path: 'wiki/${stack.petId}/food/2026-04-25-carrot-trial.md',
            type: 'food',
            ts: DateTime(2026, 4, 25),
            title: 'Carrot trial',
            bodyHash: 'h1',
          ),
        );
    await stack.db.into(stack.db.entries).insert(
          EntriesCompanion.insert(
            petId: stack.petId,
            path: 'wiki/${stack.petId}/vet/2026-04-26-checkup.md',
            type: 'vet',
            ts: DateTime(2026, 4, 26),
            title: 'Annual checkup',
            bodyHash: 'h2',
          ),
        );
    await stack.wiki.writeAtomic(
      'wiki/${stack.petId}/food/2026-04-25-carrot-trial.md',
      'Milo loved the frozen carrots.',
    );
    await stack.wiki.writeAtomic(
      'wiki/${stack.petId}/vet/2026-04-26-checkup.md',
      'Vitals normal at the vet.',
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

    // Land on Home → Open journal.
    await tester.tap(find.text('Open journal'));
    await tester.pumpAndSettle();

    // Group headers + entry titles.
    expect(find.text('food · 1'), findsOneWidget);
    expect(find.text('vet · 1'), findsOneWidget);
    expect(find.text('Carrot trial'), findsOneWidget);
    expect(find.text('Annual checkup'), findsOneWidget);

    // Tap the food entry.
    await tester.tap(find.text('Carrot trial'));
    await tester.pumpAndSettle();

    // Entry screen renders the body.
    expect(find.text('Milo loved the frozen carrots.'), findsOneWidget);
  });

  testWidgets('wiki browser shows the empty state when no entries exist',
      (tester) async {
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
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

    await tester.tap(find.text('Open journal'));
    await tester.pumpAndSettle();

    // Empty state — task 5.7 redesign. Narrative invitation framing:
    // heading states the empty fact, body frames the journal as the
    // place where the pet's life accumulates, CTA opens chat.
    // VOICE.md §5: per-pet destination → name interpolation.
    expect(find.text('No memories about Milo yet.'), findsOneWidget);
    expect(
      find.textContaining("Milo's life will accumulate"),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Open chat'), findsOneWidget);
  });
}

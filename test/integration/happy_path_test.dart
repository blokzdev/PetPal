// Phase 2 happy-path integration test (host-runnable). Exercises the
// full UI flow with mocked LLM streaming: onboarded user adds a pet,
// chat triggers write_wiki_entry via a scripted tool call, the entry
// appears in the wiki browser, and tapping it shows the body.
//
// The on-device verification batch (DECISIONS row 21) re-exercises this
// flow with a real Anthropic key against a real device.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';
import 'package:petpal/main.dart';

import '../_helpers/fake_api_key_storage.dart';
import '../_helpers/scripted_llm_client.dart';
import '../_helpers/test_provider_scope.dart';

void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  testWidgets(
      'happy path: onboarded → add pet → chat writes entry → entry shows '
      'up in wiki browser', (tester) async {
    // Scripted LLM:
    //   Turn 1: assistant calls write_wiki_entry for "Carrot trial".
    //   Turn 2: assistant confirms in plain text.
    final llm = ScriptedLlmClient(
      scripts: [
        [
          const StreamMessageStart(),
          const StreamToolUseStart(
            index: 0,
            id: 'tu_w',
            name: 'write_wiki_entry',
          ),
          const StreamToolUseInputDelta(
            index: 0,
            partialJson:
                '{"type":"food","title":"Carrot trial",'
                '"body":"Milo loves frozen carrots — naps after.",'
                '"date":"2026-04-25"}',
          ),
          const StreamContentBlockStop(index: 0),
          const StreamMessageStop(stopReason: 'tool_use'),
        ],
        [
          const StreamMessageStart(),
          const StreamTextDelta('Logged Milo’s carrot trial.'),
          const StreamContentBlockStop(index: 0),
          const StreamMessageStop(stopReason: 'end_turn'),
        ],
      ],
    );

    // Fresh DB + capturing wiki + StubEmbeddingProvider via the helper.
    // We seed the pet in the DB ourselves below to skip the AddPet form
    // (already covered by add_pet_screen_test).
    final stack = await buildChatTestStack(llm: llm);

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

    // Home greets Milo.
    expect(find.text('Milo'), findsOneWidget);

    // 1. Open chat and send a message.
    await tester.tap(find.text('Chat with Milo'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Milo just ate frozen carrots and napped — please log it.',
    );
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    // The assistant's final text bubble shows up.
    expect(find.text('Logged Milo’s carrot trial.'), findsOneWidget);

    // 2. The tool call ran for real — entry exists in the DB and on
    //    disk.
    final entries = await stack.db.select(stack.db.entries).get();
    expect(entries, hasLength(1));
    expect(entries.first.title, 'Carrot trial');
    expect(entries.first.type, 'food');
    expect(
      stack.wiki.writes['wiki/${stack.petId}/food/2026-04-25-carrot-trial.md'],
      contains('frozen carrots'),
    );

    // 3. Navigate to wiki browser via Home.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open journal'), findsOneWidget);
    await tester.tap(find.text('Open journal'));
    await tester.pumpAndSettle();

    // Entry visible in the browser, grouped under `food`.
    expect(find.text('food · 1'), findsOneWidget);
    expect(find.text('Carrot trial'), findsOneWidget);

    // 4. Open the entry and read its body.
    await tester.tap(find.text('Carrot trial'));
    await tester.pumpAndSettle();
    expect(
      find.text('Milo loves frozen carrots — naps after.'),
      findsOneWidget,
    );
  });
}

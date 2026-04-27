import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/database.dart';
import 'dart:io';

import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/data/wiki_io.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';
import 'package:petpal/harness/agent/tool_dispatcher.dart';
import 'package:petpal/harness/retrieval/stub_embedding_provider.dart';
import 'package:petpal/harness/skills/empty_skill_source.dart';
import 'package:petpal/main.dart';

import '../../_helpers/fake_api_key_storage.dart';
import '../../_helpers/scripted_llm_client.dart';

class _NoopWiki implements WikiIo {
  // Returns a minimal SOUL.md for any read so SessionBuilder can compose
  // a turn without throwing.
  @override
  Future<void> writeAtomic(String relPath, String body) async {}
  @override
  Future<String> read(String relPath) async =>
      '---\nspecies: dog\n---\n\n# Milo\n';
  @override
  Future<List<String>> listForPet(int petId) async => const [];
  @override
  String petDir(int petId) => 'wiki/$petId';
  @override
  String soulPath(int petId) => 'wiki/$petId/SOUL.md';
}

List<Override> _commonOverrides({required ScriptedLlmClient llm}) => [
      apiKeyStorageProvider.overrideWithValue(
        FakeApiKeyStorage(initial: 'sk-ant-test'),
      ),
      appDatabaseProvider.overrideWith((ref) async {
        final db = AppDatabase(NativeDatabase.memory());
        // Pre-populate with a pet so /chat can show "Milo" in the AppBar.
        await db.into(db.pets).insert(
              PetsCompanion.insert(
                name: 'Milo',
                createdAt: DateTime(2026, 4, 25),
              ),
            );
        ref.onDispose(() async => db.close());
        return db;
      }),
      wikiIoProvider.overrideWith((ref) async => _NoopWiki()),
      embeddingProviderProvider.overrideWith(
        (ref) async => const StubEmbeddingProvider(dim: 16),
      ),
      // No asset bundle in `flutter test` — fall back to an empty
      // skill source so SessionBuilder doesn't try AssetSkillSource.
      skillSourceProvider.overrideWithValue(const EmptySkillSource()),
      llmClientProvider.overrideWithValue(llm),
      // Empty tool dispatcher — text-only streaming, no tool calls.
      toolDispatcherProvider.overrideWith(
        (ref) async => ToolDispatcher(),
      ),
    ];

void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  testWidgets(
      'tapping send shows the user bubble and the streaming assistant '
      'text, then finalises', (tester) async {
    final llm = ScriptedLlmClient(
      scripts: [
        [
          const StreamMessageStart(),
          const StreamTextDelta('Got it. '),
          const StreamTextDelta('Logging Milo’s carrot trial.'),
          const StreamContentBlockStop(index: 0),
          const StreamMessageStop(),
        ],
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(llm: llm),
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Home greets Milo and shows the chat CTA.
    expect(find.text('Milo'), findsOneWidget);
    await tester.tap(find.text('Chat with Milo'));
    await tester.pumpAndSettle();

    // Empty-state heading (task 5.7 redesign). Per VOICE.md §5 the
    // heading interpolates the pet name. Three suggestion chips lower
    // activation energy on first use.
    expect(find.text('Chat with PetPal about Milo.'), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(3));

    // Type and send.
    await tester.enterText(
      find.byType(TextField),
      'Milo loves frozen carrots',
    );
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    // User bubble + finalised assistant text.
    expect(find.text('Milo loves frozen carrots'), findsOneWidget);
    expect(find.text('Got it. Logging Milo’s carrot trial.'), findsOneWidget);

    // Non-flagged turn → no escalation badge.
    expect(find.text('PetPal flagged this as urgent'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets(
      'flagged user turn renders the vet-escalation badge on the assistant '
      'bubble and persists in scrollback (VOICE.md §6, DECISIONS row 29)',
      (tester) async {
    final llm = ScriptedLlmClient(
      scripts: [
        [
          const StreamMessageStart(),
          const StreamTextDelta(
              'This sounds urgent — please call your vet now.'),
          const StreamContentBlockStop(index: 0),
          const StreamMessageStop(),
        ],
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(llm: llm),
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chat with Milo'));
    await tester.pumpAndSettle();

    // Type a phrase that the screener flags as blood_in_stool.
    await tester.enterText(
      find.byType(TextField),
      'I noticed blood in his stool this morning',
    );
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    // Both the muted scrollback marker text and the warning icon must
    // attach to the assistant bubble.
    expect(find.text('PetPal flagged this as urgent'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/chat/chat_notifier.dart';
import 'package:petpal/app/chat/chat_state.dart';
import 'package:petpal/app/platform/haptics.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/data/repos/wiki_repo.dart' show parseEntryPath;
import 'package:petpal/data/wiki_io_fs.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';
import 'package:petpal/harness/agent/messages.dart' as llm;
import 'package:petpal/harness/retrieval/stub_embedding_provider.dart';
import 'package:petpal/harness/skills/empty_skill_source.dart';

import '../../_helpers/scripted_llm_client.dart';

void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  test(
      'chat → write_wiki_entry tool call → entry lands in DB and is '
      'retrievable on next turn', () async {
    final tempRoot = Directory.systemTemp.createTempSync('petpal_chat_tools_');
    addTearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Seed a pet so activePetIdProvider has something to return.
    final petId = await db.into(db.pets).insert(
          PetsCompanion.insert(
            name: 'Milo',
            createdAt: DateTime(2026, 4, 25),
          ),
        );
    expect(petId, 1);

    // Scripted LLM: turn 1 calls write_wiki_entry; turn 2 confirms
    // (text-only) after seeing the tool result.
    final llmClient = ScriptedLlmClient(scripts: [
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
              '"body":"Milo loves frozen carrots.","date":"2026-04-25"}',
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
    ]);

    final haptics = FakeHaptics();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async {
          ref.onDispose(() async {});
          return db;
        }),
        wikiIoProvider.overrideWith((ref) async => WikiIoFs(tempRoot)),
        embeddingProviderProvider.overrideWith(
          (ref) async => const StubEmbeddingProvider(dim: 16),
        ),
        // No asset bundle in `flutter test` — fall back to an empty
        // skill source so SessionBuilder doesn't try AssetSkillSource
        // and crash. This test doesn't exercise skills.
        skillSourceProvider.overrideWithValue(const EmptySkillSource()),
        llmClientProvider.overrideWithValue(llmClient),
        // 5.8 — chat layer fires HapticFeedback on a successful
        // write_wiki_entry. The services binding isn't initialized
        // in non-widget tests, so swap to a counting fake; we also
        // assert the haptic actually fired (one light pulse per
        // successful write).
        hapticsProvider.overrideWithValue(haptics),
      ],
    );
    addTearDown(container.dispose);

    // Make sure the Pet row is visible to activePetIdProvider.
    await container.read(petsProvider.future);

    await container.read(chatProvider.notifier).send(
          'Milo loves frozen carrots — please log it.',
        );

    final state = container.read(chatProvider);
    expect(state.error, isNull, reason: 'no error should surface');
    expect(state.streamingAssistant, isNull);
    expect(state.activeTools, isEmpty);

    // 5.8 — exactly one light haptic for the single successful
    // write_wiki_entry tool result. Subsequent text-only turns must
    // not fire additional haptics.
    expect(haptics.lightCount, 1,
        reason: 'one light haptic per successful write_wiki_entry commit');

    // The entry actually lives in the DB now.
    final entries = await db.select(db.entries).get();
    expect(entries, hasLength(1));
    expect(entries.first.type, 'food');
    expect(entries.first.title, 'Carrot trial');
    final parsed = parseEntryPath(entries.first.path);
    expect(parsed?.ts, DateTime(2026, 4, 25));

    // The file exists on disk too.
    final body = await WikiIoFs(tempRoot).read(entries.first.path);
    expect(body, contains('frozen carrots'));

    // 5.9 — recentMemorySave signal carries the entry path so the
    // chat surface's snackbar can deep-link to /wiki/entry. The id
    // monotonically increments per save (1 here for the single
    // save). The path matches what the tool actually wrote to disk.
    expect(state.recentMemorySave, isNotNull,
        reason: 'memory-saved signal must emit on a successful write');
    expect(state.recentMemorySave!.id, 1);
    expect(state.recentMemorySave!.path, entries.first.path);
    expect(state.recentMemorySave!.title, 'Carrot trial');

    // History has user + assistant(tool_use) + user(tool_result) +
    // assistant(text). UI projection drops the tool-only turns.
    expect(state.history.length, 4);
    final ui = state.uiMessages.toList();
    expect(ui, hasLength(2));
    expect(ui[0].role, ChatRole.user);
    expect(ui[1].role, ChatRole.assistant);
    expect(ui[1].text, contains('Logged'));

    // Cross-check: the assistant's tool_use input was parsed correctly.
    final assistantToolUse = state.history[1];
    expect(assistantToolUse.role, llm.Message.assistantRole);
    final tu = assistantToolUse.content
        .whereType<llm.ToolUseBlock>()
        .single;
    expect(tu.name, 'write_wiki_entry');
    expect(tu.input['title'], 'Carrot trial');
  });
}

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart' hide Message;
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/data/repos/wiki_repo.dart';
import 'package:petpal/data/wiki_io_fs.dart';
import 'package:petpal/harness/agent/llm_client.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';
import 'package:petpal/harness/agent/messages.dart';
import 'package:petpal/harness/retrieval/embedding_worker.dart';
import 'package:petpal/harness/retrieval/stub_embedding_provider.dart';
import 'package:petpal/harness/synthesis/weekly_digest.dart';

class _ScriptedLlm implements LlmClient {
  _ScriptedLlm(this.next);
  Message next;
  final List<String> systemPromptsSeen = [];
  final List<List<Message>> historiesSeen = [];

  @override
  Future<Message> turn({
    required String systemPrompt,
    required List<Message> history,
    List<ToolDefinition> tools = const [],
  }) async {
    systemPromptsSeen.add(systemPrompt);
    historiesSeen.add(List.of(history));
    return next;
  }

  @override
  Stream<LlmStreamEvent> streamTurn({
    required String systemPrompt,
    required List<Message> history,
    List<ToolDefinition> tools = const [],
  }) =>
      throw UnimplementedError();
}

void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late WikiIoFs wiki;
  late WikiRepo wikiRepo;
  late int petId;

  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('petpal_digest_');
    db = AppDatabase(NativeDatabase.memory());
    wiki = WikiIoFs(tempRoot);
    final worker = EmbeddingWorker(
      db: db,
      provider: const StubEmbeddingProvider(dim: 16),
    );
    wikiRepo = WikiRepo(db: db, wiki: wiki, embeddings: worker);
    petId = await db.into(db.pets).insert(
          PetsCompanion.insert(
            name: 'Milo',
            createdAt: DateTime(2026, 4, 25),
          ),
        );
    await wiki.writeAtomic(
      wiki.soulPath(petId),
      '---\ncategory: dog\n---\n\n# Milo\n',
    );
  });

  tearDown(() async {
    await db.close();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('skips with reason when the pet has no entries in the window',
      () async {
    final llm = _ScriptedLlm(
      const Message(role: 'assistant', content: [TextBlock('unused')]),
    );
    final runner = WeeklyDigestRunner(
      db: db,
      wiki: wiki,
      wikiRepo: wikiRepo,
      llm: llm,
    );
    final result = await runner.run(petId: petId, now: DateTime(2026, 4, 25));
    expect(result.skipped, isTrue);
    expect(result.reason, contains('no entries'));
    expect(llm.historiesSeen, isEmpty,
        reason: 'no entries should mean no LLM call');
  });

  test('writes a digest entry with synthesised body when entries exist',
      () async {
    // Two entries inside the 7-day window.
    await wikiRepo.writeEntry(
      petId: petId,
      type: 'food',
      title: 'Carrot trial',
      body: 'Milo loved frozen carrots.',
      ts: DateTime(2026, 4, 22),
    );
    await wikiRepo.writeEntry(
      petId: petId,
      type: 'behavior',
      title: 'Skateboard fear',
      body: 'Milo bolted from a skateboard yesterday.',
      ts: DateTime(2026, 4, 23),
    );
    // One entry OUTSIDE the window (must not be in the prompt).
    await wikiRepo.writeEntry(
      petId: petId,
      type: 'vet',
      title: 'Old checkup',
      body: 'From two months ago.',
      ts: DateTime(2026, 2, 15),
    );

    final llm = _ScriptedLlm(
      const Message(
        role: 'assistant',
        content: [
          TextBlock(
            '## Trends\n- Two food/behaviour entries this week.\n\n'
            '## Watch list\n- Skateboard reactivity.\n',
          ),
        ],
      ),
    );

    final runner = WeeklyDigestRunner(
      db: db,
      wiki: wiki,
      wikiRepo: wikiRepo,
      llm: llm,
    );

    final asOf = DateTime(2026, 4, 25);
    final result = await runner.run(petId: petId, now: asOf);

    expect(result.skipped, isFalse);
    expect(result.entryId, isNotNull);
    expect(result.entryPath, contains('digest/2026-04-25'));

    // The system prompt mentions the species + name.
    expect(llm.systemPromptsSeen.single, contains('Milo'));
    expect(llm.systemPromptsSeen.single, contains('dog'));
    // Only the two in-window entries appear in the user message.
    final history = llm.historiesSeen.single;
    final userText =
        history.single.content.whereType<TextBlock>().single.text;
    expect(userText, contains('Carrot trial'));
    expect(userText, contains('Skateboard fear'));
    expect(userText, isNot(contains('Old checkup')),
        reason: 'entry outside the 7-day window must be excluded');

    // The digest entry actually persisted.
    final entryRow = await (db.select(db.entries)
          ..where((e) => e.id.equals(result.entryId!)))
        .getSingle();
    expect(entryRow.type, 'digest');
    expect(entryRow.title, 'Weekly digest 2026-04-25');

    // The body is the synthesised text.
    final body = await wiki.read(entryRow.path);
    expect(body, contains('Trends'));
    expect(body, contains('Watch list'));
  });

  test('skips when the LLM returns an empty response', () async {
    await wikiRepo.writeEntry(
      petId: petId,
      type: 'food',
      title: 'A note',
      body: 'Some content.',
      ts: DateTime(2026, 4, 22),
    );

    final llm = _ScriptedLlm(
      const Message(role: 'assistant', content: [TextBlock('   ')]),
    );

    final runner = WeeklyDigestRunner(
      db: db,
      wiki: wiki,
      wikiRepo: wikiRepo,
      llm: llm,
    );

    final result = await runner.run(
      petId: petId,
      now: DateTime(2026, 4, 25),
    );
    expect(result.skipped, isTrue);
    expect(result.reason, contains('no usable text'));
  });
}

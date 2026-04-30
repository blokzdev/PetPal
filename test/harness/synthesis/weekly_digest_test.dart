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

  group('Phase 6 task 6.13 — smarter digest enrichment', () {
    test('the system prompt instructs on trends, anomalies, photo '
        'memories, and gentle observations', () async {
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'food',
        title: 'A note',
        body: 'Some content.',
        ts: DateTime(2026, 4, 22),
      );
      final llm = _ScriptedLlm(
        const Message(
          role: 'assistant',
          content: [TextBlock('## Summary\n- ok')],
        ),
      );
      final runner = WeeklyDigestRunner(
        db: db,
        wiki: wiki,
        wikiRepo: wikiRepo,
        llm: llm,
      );
      await runner.run(petId: petId, now: DateTime(2026, 4, 25));
      final sys = llm.systemPromptsSeen.single;
      expect(sys, contains('Trends'));
      expect(sys, contains('Anomalies'));
      expect(sys, contains('Photo memories'));
      expect(sys, contains('Gentle observations'));
      expect(sys, contains('not a vet'));
    });

    test('weight observations + delta block are included in the user '
        'turn when the pet has weight history', () async {
      // Six weight entries over six weeks — three this week, three
      // prior — so the delta path triggers. (The runner queries
      // ALL weight history and computes the delta over the digest
      // window vs the prior window; entries outside both windows
      // still show up in the all-time list but don't drive the
      // delta.)
      final asOf = DateTime(2026, 4, 25);
      final entries = [
        (asOf.subtract(const Duration(days: 13)), 14.0),
        (asOf.subtract(const Duration(days: 11)), 14.1),
        (asOf.subtract(const Duration(days: 9)), 14.2),
        (asOf.subtract(const Duration(days: 5)), 13.8),
        (asOf.subtract(const Duration(days: 3)), 13.7),
        (asOf.subtract(const Duration(days: 1)), 13.6),
      ];
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        await wikiRepo.writeEntry(
          petId: petId,
          type: 'weight',
          title: 'Weigh-in $i',
          body: '---\ntype: weight\nweight_kg: ${e.$2}\n---\n\nNote.\n',
          ts: e.$1,
        );
      }
      final llm = _ScriptedLlm(
        const Message(
          role: 'assistant',
          content: [TextBlock('## Summary\n- ok')],
        ),
      );
      final runner = WeeklyDigestRunner(
        db: db,
        wiki: wiki,
        wikiRepo: wikiRepo,
        llm: llm,
      );
      await runner.run(petId: petId, now: asOf);
      final userText = llm.historiesSeen.single.single.content
          .whereType<TextBlock>()
          .single
          .text;
      expect(userText, contains('Structured signal block'));
      expect(userText, contains('Weight observations'));
      expect(userText, contains('14.00 kg'));
      expect(userText, contains('Weight delta'));
      expect(userText, contains('Direction: down'));
    });

    test('photo entries this week appear in the user-turn payload as '
        'anchor moments', () async {
      // The runner type-classifies entries by their `type` column,
      // not by parsing frontmatter from disk. We seed a photo-typed
      // entry directly via WikiRepo.writeEntry.
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'photos',
        title: 'Loki at the trailhead',
        body: '---\ntype: photos\nimage: abc-123.jpg\n---\n\n'
            'Loki at the trailhead.\n',
        ts: DateTime(2026, 4, 23),
      );
      final llm = _ScriptedLlm(
        const Message(
          role: 'assistant',
          content: [TextBlock('## Summary\n- ok')],
        ),
      );
      final runner = WeeklyDigestRunner(
        db: db,
        wiki: wiki,
        wikiRepo: wikiRepo,
        llm: llm,
      );
      await runner.run(petId: petId, now: DateTime(2026, 4, 25));
      final userText = llm.historiesSeen.single.single.content
          .whereType<TextBlock>()
          .single
          .text;
      expect(userText, contains('Photo memories this week'));
      expect(userText, contains('Loki at the trailhead'));
    });

    test('symptom keyword hits surface in the trend block', () async {
      // Two entries that mention scratching keyword — FTS5 indexes
      // the body so the trend block picks it up.
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'behavior',
        title: 'Itchy day',
        body: 'Loki was scratching all morning.',
        ts: DateTime(2026, 4, 22),
      );
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'behavior',
        title: 'Itchy again',
        body: 'More scratching this evening.',
        ts: DateTime(2026, 4, 23),
      );
      final llm = _ScriptedLlm(
        const Message(
          role: 'assistant',
          content: [TextBlock('## Summary\n- ok')],
        ),
      );
      final runner = WeeklyDigestRunner(
        db: db,
        wiki: wiki,
        wikiRepo: wikiRepo,
        llm: llm,
      );
      await runner.run(petId: petId, now: DateTime(2026, 4, 25));
      final userText = llm.historiesSeen.single.single.content
          .whereType<TextBlock>()
          .single
          .text;
      expect(userText, contains('Symptom keyword counts'));
      expect(userText, contains('Scratching: 2'));
    });
  });
}

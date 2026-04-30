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
import 'package:petpal/harness/synthesis/monthly_report.dart';

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

/// Phase 6 task 6.14 — monthly report runner unit tests. Cover:
///   - skip-when-empty, write-when-entries-exist (parity with weekly).
///   - the system prompt is monthly-flavoured (multi-week
///     trajectory, vet follow-up status, recurring patterns).
///   - vet-follow-up status block reflects past-due vs pending.
///   - the title is calendar-month-stamped: "Monthly report YYYY-MM".
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
    tempRoot = Directory.systemTemp.createTempSync('petpal_monthly_');
    db = AppDatabase(NativeDatabase.memory());
    wiki = WikiIoFs(tempRoot);
    final worker = EmbeddingWorker(
      db: db,
      provider: const StubEmbeddingProvider(dim: 16),
    );
    wikiRepo = WikiRepo(db: db, wiki: wiki, embeddings: worker);
    petId = await db.into(db.pets).insert(
          PetsCompanion.insert(
            name: 'Loki',
            createdAt: DateTime(2026, 4, 25),
          ),
        );
    await wiki.writeAtomic(
      wiki.soulPath(petId),
      '---\ncategory: dog\n---\n\n# Loki\n',
    );
  });

  tearDown(() async {
    await db.close();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('skips with reason when the pet has no entries in the month',
      () async {
    final llm = _ScriptedLlm(
      const Message(role: 'assistant', content: [TextBlock('unused')]),
    );
    final runner = MonthlyReportRunner(
      db: db,
      wiki: wiki,
      wikiRepo: wikiRepo,
      llm: llm,
    );
    final result = await runner.run(petId: petId, now: DateTime(2026, 4, 25));
    expect(result.skipped, isTrue);
    expect(result.reason, contains('no entries'));
    expect(llm.historiesSeen, isEmpty);
  });

  test('writes a report whose title is calendar-month-stamped', () async {
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
        content: [TextBlock('## April\n- ok')],
      ),
    );
    final runner = MonthlyReportRunner(
      db: db,
      wiki: wiki,
      wikiRepo: wikiRepo,
      llm: llm,
    );
    final result =
        await runner.run(petId: petId, now: DateTime(2026, 4, 25));
    expect(result.skipped, isFalse);
    expect(result.entryPath, contains('digest/2026-04-25-monthly-report-2026-04.md'));
    final row = await (db.select(db.entries)
          ..where((e) => e.id.equals(result.entryId!)))
        .getSingle();
    expect(row.type, 'digest');
    expect(row.title, 'Monthly report 2026-04');
  });

  test('the system prompt is monthly-flavoured (multi-week, vet '
      'follow-up status, recurring patterns)', () async {
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
        content: [TextBlock('## ok')],
      ),
    );
    final runner = MonthlyReportRunner(
      db: db,
      wiki: wiki,
      wikiRepo: wikiRepo,
      llm: llm,
    );
    await runner.run(petId: petId, now: DateTime(2026, 4, 25));
    final sys = llm.systemPromptsSeen.single;
    expect(sys, contains('MONTHLY health report'));
    expect(sys, contains('Multi-week trajectory'));
    expect(sys, contains('Vet-visit follow-up status'));
    expect(sys, contains('Recurring patterns'));
    expect(sys, contains('Photo memory anchors'));
  });

  test('vet-visit follow-up status surfaces in the trend block, '
      'flagging past-due vs pending dates', () async {
    final asOf = DateTime(2026, 4, 25);

    // Vet entry with a follow-up that's already past-due relative
    // to asOf.
    await wikiRepo.writeEntry(
      petId: petId,
      type: 'vet',
      title: 'Booster',
      body: '---\ntype: vet\nreason: Booster\n'
          'follow_up_date: 2026-04-10\n---\n\nBooster shot.\n',
      ts: DateTime(2026, 4, 5),
    );
    // Vet entry with a follow-up still pending.
    await wikiRepo.writeEntry(
      petId: petId,
      type: 'vet',
      title: 'Annual checkup',
      body: '---\ntype: vet\nreason: Annual checkup\n'
          'follow_up_date: 2027-04-15\n---\n\nAnnual checkup.\n',
      ts: DateTime(2026, 4, 15),
    );

    final llm = _ScriptedLlm(
      const Message(
        role: 'assistant',
        content: [TextBlock('## ok')],
      ),
    );
    final runner = MonthlyReportRunner(
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
    expect(userText, contains('Vet visits this month'));
    expect(userText, contains('Booster'));
    expect(userText, contains('follow-up 2026-04-10 (past-due)'));
    expect(userText, contains('Annual checkup'));
    expect(userText, contains('follow-up 2027-04-15 (pending)'));
  });

  test('skips when the LLM returns empty text', () async {
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
    final runner = MonthlyReportRunner(
      db: db,
      wiki: wiki,
      wikiRepo: wikiRepo,
      llm: llm,
    );
    final result =
        await runner.run(petId: petId, now: DateTime(2026, 4, 25));
    expect(result.skipped, isTrue);
    expect(result.reason, contains('no usable text'));
  });
}

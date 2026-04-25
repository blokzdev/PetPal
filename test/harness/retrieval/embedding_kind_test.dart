// Verifies EmbeddingKind plumbing — that retrieval call sites
// (SessionBuilder, search_wiki tool) actually pass kind=query when
// embedding the user's question, while indexing call sites
// (EmbeddingWorker via WikiRepo) leave the default kind=document.
//
// The on-device OnnxEmbeddingProvider is asymmetric (queries get a
// prefix, documents don't); embedding both with the same kind degrades
// retrieval quality. This test guards the wiring without needing the
// real model.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/data/repos/pet_repo.dart';
import 'package:petpal/data/repos/wiki_repo.dart';
import 'package:petpal/data/wiki_io_fs.dart';
import 'package:petpal/harness/agent/messages.dart';
import 'package:petpal/harness/agent/tool_dispatcher.dart';
import 'package:petpal/harness/retrieval/embedding_provider.dart';
import 'package:petpal/harness/retrieval/embedding_worker.dart';
import 'package:petpal/harness/retrieval/hybrid_retriever.dart';
import 'package:petpal/harness/session_builder.dart';
import 'package:petpal/harness/skills/empty_skill_source.dart';
import 'package:petpal/harness/skills/skill_loader.dart';
import 'package:petpal/harness/tools/wiki_tools.dart';

/// Records every embed() call's text + kind so the test can assert on them.
class _RecordingProvider implements EmbeddingProvider {
  @override
  int get dim => 8;

  final List<({String text, EmbeddingKind kind})> calls = [];

  @override
  Future<List<double>> embed(
    String text, {
    EmbeddingKind kind = EmbeddingKind.document,
  }) async {
    calls.add((text: text, kind: kind));
    return List<double>.filled(dim, 0.5);
  }
}

void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late _RecordingProvider provider;

  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('petpal_embed_kind_');
    db = AppDatabase(NativeDatabase.memory());
    provider = _RecordingProvider();
  });

  tearDown(() async {
    await db.close();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('WikiRepo.writeEntry embeds the body with kind=document', () async {
    final wiki = WikiIoFs(tempRoot);
    final petRepo = PetRepo(db: db, wiki: wiki);
    final worker = EmbeddingWorker(db: db, provider: provider);
    final repo = WikiRepo(db: db, wiki: wiki, embeddings: worker);

    final id = await petRepo.createPet(name: 'Milo');
    await repo.writeEntry(
      petId: id,
      type: 'food',
      title: 'Carrot trial',
      body: 'Milo loves frozen carrots.',
      ts: DateTime(2026, 4, 25),
    );

    final embedCall =
        provider.calls.singleWhere((c) => c.text.contains('carrots'));
    expect(embedCall.kind, EmbeddingKind.document);
  });

  test('SessionBuilder embeds the user question with kind=query', () async {
    final wiki = WikiIoFs(tempRoot);
    final petRepo = PetRepo(db: db, wiki: wiki);
    final id = await petRepo.createPet(name: 'Milo');
    final pet = (await petRepo.getPet(id))!;

    final builder = SessionBuilder(
      wiki: wiki,
      retriever: HybridRetriever(db: db),
      embeddings: provider,
      skills: SkillLoader(source: const EmptySkillSource()),
    );

    await builder.compose(pet: pet, userInput: 'what treats does Milo like?');

    final queryCalls =
        provider.calls.where((c) => c.kind == EmbeddingKind.query).toList();
    expect(queryCalls, hasLength(1));
    expect(queryCalls.first.text, 'what treats does Milo like?');
  });

  test('search_wiki tool embeds the model-supplied query with kind=query',
      () async {
    final wiki = WikiIoFs(tempRoot);
    final petRepo = PetRepo(db: db, wiki: wiki);
    final id = await petRepo.createPet(name: 'Milo');
    final repo = WikiRepo(
      db: db,
      wiki: wiki,
      embeddings: EmbeddingWorker(db: db, provider: provider),
    );

    final dispatcher = ToolDispatcher();
    registerWikiTools(
      dispatcher,
      wiki: wiki,
      repo: repo,
      retriever: HybridRetriever(db: db),
      embeddings: provider,
      activePetId: () => id,
    );

    await dispatcher.handle(const ToolUseBlock(
      id: 'tu_s',
      name: 'search_wiki',
      input: {'query': 'frozen carrots'},
    ));

    final queryCall = provider.calls.singleWhere(
      (c) => c.text == 'frozen carrots',
    );
    expect(queryCall.kind, EmbeddingKind.query);
  });
}

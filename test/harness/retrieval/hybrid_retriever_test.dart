import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/data/repos/wiki_repo.dart';
import 'package:petpal/data/wiki_io_fs.dart';
import 'package:petpal/harness/retrieval/embedding_worker.dart';
import 'package:petpal/harness/retrieval/hybrid_retriever.dart';
import 'package:petpal/harness/retrieval/stub_embedding_provider.dart';

void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late WikiRepo repo;
  late HybridRetriever retriever;
  const provider = StubEmbeddingProvider(dim: 16);
  const petA = 1;
  const petB = 2;

  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('petpal_hybrid_');
    db = AppDatabase(NativeDatabase.memory());
    final wiki = WikiIoFs(tempRoot);
    final worker = EmbeddingWorker(db: db, provider: provider);
    repo = WikiRepo(db: db, wiki: wiki, embeddings: worker);
    retriever = HybridRetriever(db: db);

    await db.into(db.pets).insert(
          PetsCompanion.insert(
            name: 'Milo',
            createdAt: DateTime(2026, 4, 25),
          ),
        );
    await db.into(db.pets).insert(
          PetsCompanion.insert(
            name: 'Luna',
            createdAt: DateTime(2026, 4, 25),
          ),
        );

    await repo.writeEntry(
      petId: petA,
      type: 'food',
      title: 'Carrot trial',
      body: 'Milo loves frozen carrots and naps after.',
      ts: DateTime(2026, 4, 25),
    );
    await repo.writeEntry(
      petId: petA,
      type: 'behavior',
      title: 'Skateboard fear',
      body: 'Milo bolts whenever a skateboard rolls past.',
      ts: DateTime(2026, 4, 26),
    );
    await repo.writeEntry(
      petId: petA,
      type: 'vet',
      title: 'Annual checkup',
      body: 'Routine visit. Vitals normal.',
      ts: DateTime(2026, 4, 27),
    );
    // Belongs to a different pet — must be filtered out by petId.
    await repo.writeEntry(
      petId: petB,
      type: 'food',
      title: 'Carrot trial',
      body: 'Luna also loves carrots.',
      ts: DateTime(2026, 4, 25),
    );
  });

  tearDown(() async {
    await db.close();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('keyword-only search returns FTS5 matches with snippets', () async {
    final hits = await retriever.search(
      petId: petA,
      queryText: 'carrot*',
    );
    expect(hits, hasLength(1));
    expect(hits.first.title, 'Carrot trial');
    expect(hits.first.snippet, isNotNull);
    expect(hits.first.snippet, contains('carrots'));
  });

  test('keyword search filters out other pets', () async {
    final hitsA = await retriever.search(petId: petA, queryText: 'carrot*');
    final hitsB = await retriever.search(petId: petB, queryText: 'carrot*');
    expect(hitsA.map((h) => h.path), [
      contains('wiki/$petA/'),
    ]);
    expect(hitsB.map((h) => h.path), [
      contains('wiki/$petB/'),
    ]);
  });

  test('vector-only search returns kNN ordered by distance', () async {
    // Querying with the exact body of an entry yields a perfect-match (the
    // stub provider is deterministic on text), so that entry ranks first.
    final query = await provider.embed(
      'Milo bolts whenever a skateboard rolls past.',
    );
    final hits = await retriever.search(
      petId: petA,
      queryVector: query,
      k: 3,
    );
    expect(hits, hasLength(3));
    expect(hits.first.title, 'Skateboard fear');
  });

  test('hybrid search dedupes when the same entry is both an FTS5 and a '
      'vector hit', () async {
    final query = await provider.embed(
      'Milo loves frozen carrots and naps after.',
    );
    final hits = await retriever.search(
      petId: petA,
      queryText: 'carrot*',
      queryVector: query,
      k: 5,
    );
    final ids = hits.map((h) => h.entryId).toList();
    expect(ids.toSet().length, ids.length, reason: 'no duplicates');
    // Carrot entry hit by both signals should fuse to top rank.
    expect(hits.first.title, 'Carrot trial');
    // FTS5 snippet must survive dedup — a vector hit on the same entry
    // mustn't blank it out.
    expect(hits.first.snippet, isNotNull);
    expect(hits.first.snippet, contains('carrots'));
  });

  test('empty query and null vector return no hits', () async {
    final hits = await retriever.search(petId: petA);
    expect(hits, isEmpty);
  });
}

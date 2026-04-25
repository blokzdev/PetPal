import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/repos/wiki_repo.dart';
import 'package:petpal/data/wiki_io_fs.dart';
import 'package:petpal/harness/retrieval/embedding_provider.dart';
import 'package:petpal/harness/retrieval/embedding_worker.dart';
import 'package:petpal/harness/retrieval/stub_embedding_provider.dart';

class _RecordingProvider implements EmbeddingProvider {
  @override
  int get dim => 8;

  final List<String> calls = [];

  @override
  Future<List<double>> embed(String text) async {
    calls.add(text);
    return List<double>.filled(dim, 0.5);
  }
}

List<double> _bytesToFloats(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  return List<double>.generate(
    bytes.lengthInBytes ~/ 4,
    (i) => bd.getFloat32(i * 4, Endian.little),
  );
}

void main() {
  group('StubEmbeddingProvider', () {
    test('returns deterministic vectors of the configured dimension',
        () async {
      const provider = StubEmbeddingProvider(dim: 16);
      final a = await provider.embed('Milo loves frozen carrots');
      final b = await provider.embed('Milo loves frozen carrots');
      expect(a.length, 16);
      expect(a, b);
    });

    test('different inputs map to different vectors', () async {
      const provider = StubEmbeddingProvider();
      final a = await provider.embed('frozen carrots');
      final b = await provider.embed('frozen peas');
      expect(a, isNot(b));
    });

    test('vectors are unit-normalized (||v|| ≈ 1)', () async {
      const provider = StubEmbeddingProvider();
      final v = await provider.embed('hello');
      var norm = 0.0;
      for (final x in v) {
        norm += x * x;
      }
      expect(norm, closeTo(1.0, 1e-6));
    });
  });

  group('EmbeddingWorker', () {
    late AppDatabase db;
    late EmbeddingWorker worker;
    late _RecordingProvider provider;
    const petId = 1;
    late int entryId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      provider = _RecordingProvider();
      worker = EmbeddingWorker(db: db, provider: provider);
      await db.into(db.pets).insert(
            PetsCompanion.insert(
              name: 'Milo',
              createdAt: DateTime(2026, 4, 25),
            ),
          );
      entryId = await db.into(db.entries).insert(
            EntriesCompanion.insert(
              petId: petId,
              path: 'wiki/$petId/note/2026-04-25-x.md',
              type: 'note',
              ts: DateTime(2026, 4, 25),
              title: 'x',
              bodyHash: 'h',
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test('enqueue calls the provider and inserts an embeddings row',
        () async {
      await worker.enqueue(entryId: entryId, body: 'Milo loves carrots');

      expect(provider.calls, ['Milo loves carrots']);
      final rows = await db.select(db.embeddings).get();
      expect(rows, hasLength(1));
      expect(rows.first.entryId, entryId);
      expect(rows.first.chunkIdx, 0);

      final floats = _bytesToFloats(rows.first.vector);
      expect(floats, hasLength(provider.dim));
      expect(floats, everyElement(closeTo(0.5, 1e-6)));
    });

    test('enqueue is idempotent — running twice keeps a single row',
        () async {
      await worker.enqueue(entryId: entryId, body: 'first');
      await worker.enqueue(entryId: entryId, body: 'second');

      final rows = await db.select(db.embeddings).get();
      expect(rows, hasLength(1));
    });
  });

  group('WikiRepo + EmbeddingWorker', () {
    late Directory tempRoot;
    late AppDatabase db;
    late WikiIoFs wiki;
    late WikiRepo repo;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('petpal_repo_embed_');
      db = AppDatabase(NativeDatabase.memory());
      wiki = WikiIoFs(tempRoot);
      final worker = EmbeddingWorker(
        db: db,
        provider: const StubEmbeddingProvider(dim: 8),
      );
      repo = WikiRepo(db: db, wiki: wiki, embeddings: worker);
      await db.into(db.pets).insert(
            PetsCompanion.insert(
              name: 'Milo',
              createdAt: DateTime(2026, 4, 25),
            ),
          );
    });

    tearDown(() async {
      await db.close();
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('writeEntry produces an embeddings row alongside the entry',
        () async {
      final id = await repo.writeEntry(
        petId: 1,
        type: 'food',
        title: 'Carrot trial',
        body: 'Milo loves frozen carrots.',
        ts: DateTime(2026, 4, 25),
      );

      final rows = await (db.select(db.embeddings)
            ..where((e) => e.entryId.equals(id)))
          .get();
      expect(rows, hasLength(1));
    });
  });
}

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/data/repos/pet_repo.dart';
import 'package:petpal/data/repos/trends_repo.dart';
import 'package:petpal/data/repos/wiki_repo.dart';
import 'package:petpal/data/wiki_io_fs.dart';
import 'package:petpal/harness/retrieval/embedding_worker.dart';
import 'package:petpal/harness/retrieval/stub_embedding_provider.dart';

/// Phase 6 task 6.12 — trends repo unit tests. Cover both surfaces:
///   - weightHistory parses `weight_kg:` from type=weight entries,
///     skips entries without the field, returns ascending-by-ts.
///   - symptomFrequencies counts FTS5 hits per known keyword for the
///     active pet only, returns one row per keyword (including 0
///     counts), sorted descending.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late WikiIoFs wiki;
  late WikiRepo wikiRepo;
  late PetRepo petRepo;
  late TrendsRepo trends;
  late int petId;

  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('petpal_trends_');
    db = AppDatabase(NativeDatabase.memory());
    wiki = WikiIoFs(tempRoot);
    final stub = const StubEmbeddingProvider(dim: 16);
    final worker = EmbeddingWorker(db: db, provider: stub);
    wikiRepo = WikiRepo(db: db, wiki: wiki, embeddings: worker);
    petRepo = PetRepo(db: db, wiki: wiki);
    trends = TrendsRepo(db: db, wiki: wiki);
    petId = await petRepo.createPet(name: 'Loki', category: 'dog');
  });

  tearDown(() async {
    await db.close();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  group('weightHistory', () {
    test('returns parsed weight_kg observations in ascending ts order',
        () async {
      // Three weight entries, written out of order.
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'weight',
        title: 'Vet checkup',
        body:
            '---\ntype: weight\nweight_kg: 14.2\n---\n\nLoki at the vet.\n',
        ts: DateTime(2026, 3, 1),
      );
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'weight',
        title: 'Home weigh-in',
        body: '---\ntype: weight\nweight_kg: 14.5\n---\n\nKitchen scale.\n',
        ts: DateTime(2026, 4, 15),
      );
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'weight',
        title: 'Spring check',
        body: '---\ntype: weight\nweight_kg: 13.9\n---\n\nMud-season weigh.\n',
        ts: DateTime(2026, 4, 1),
      );

      final history = await trends.weightHistory(petId);
      expect(history, hasLength(3));
      expect(history.map((o) => o.kg).toList(), [14.2, 13.9, 14.5]);
      expect(history[0].ts.isBefore(history[1].ts), isTrue);
      expect(history[1].ts.isBefore(history[2].ts), isTrue);
    });

    test('silently skips weight entries that have no weight_kg field',
        () async {
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'weight',
        title: 'Vague note',
        body: '---\ntype: weight\n---\n\nForgot to write the number.\n',
        ts: DateTime(2026, 3, 1),
      );
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'weight',
        title: 'Real measurement',
        body: '---\ntype: weight\nweight_kg: 14.2\n---\n\nKitchen scale.\n',
        ts: DateTime(2026, 4, 1),
      );

      final history = await trends.weightHistory(petId);
      expect(history, hasLength(1));
      expect(history.single.kg, 14.2);
    });

    test('parses string-form weight_kg ("14.2") with optional units '
        'so partial-yaml entries still chart', () async {
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'weight',
        title: 'Pounds-style',
        body: '---\ntype: weight\nweight_kg: "14.2 kg"\n---\n\nLater note.\n',
        ts: DateTime(2026, 4, 1),
      );
      final history = await trends.weightHistory(petId);
      expect(history.single.kg, 14.2);
    });

    test('returns empty when no weight entries exist', () async {
      final history = await trends.weightHistory(petId);
      expect(history, isEmpty);
    });

    test('only returns observations for the requested pet', () async {
      final otherId = await petRepo.createPet(name: 'Mochi', category: 'cat');
      await wikiRepo.writeEntry(
        petId: otherId,
        type: 'weight',
        title: 'Cat weigh',
        body: '---\ntype: weight\nweight_kg: 4.5\n---\n\nCat scale.\n',
        ts: DateTime(2026, 4, 1),
      );
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'weight',
        title: 'Dog weigh',
        body: '---\ntype: weight\nweight_kg: 14.2\n---\n\nDog scale.\n',
        ts: DateTime(2026, 4, 1),
      );
      final dogHistory = await trends.weightHistory(petId);
      final catHistory = await trends.weightHistory(otherId);
      expect(dogHistory.single.kg, 14.2);
      expect(catHistory.single.kg, 4.5);
    });
  });

  group('symptomFrequencies', () {
    test('returns one row per known keyword; hit counts come from FTS5',
        () async {
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'behavior',
        title: 'Bath day',
        body: 'Loki was scratching all morning after the bath.',
        ts: DateTime(2026, 4, 1),
      );
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'behavior',
        title: 'After dinner',
        body: 'He vomited a little after dinner — chewed too fast.',
        ts: DateTime(2026, 4, 5),
      );
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'behavior',
        title: 'Walk',
        body: 'Loki seemed lethargic on the walk this evening.',
        ts: DateTime(2026, 4, 6),
      );

      final freq = await trends.symptomFrequencies(petId);
      expect(freq, hasLength(TrendsRepo.symptomKeywords.length));
      // Each named keyword must be present.
      final byLabel = {for (final f in freq) f.label: f.count};
      expect(byLabel['Vomiting'], 1);
      expect(byLabel['Scratching'], 1);
      expect(byLabel['Lethargy'], 1);
      // No mentions of limping or diarrhea.
      expect(byLabel['Limping'], 0);
      expect(byLabel['Diarrhea'], 0);
    });

    test('sorts descending by count so the chart shows the loudest '
        'concerns first', () async {
      // Three vomiting entries, one scratching entry.
      for (var i = 1; i <= 3; i++) {
        await wikiRepo.writeEntry(
          petId: petId,
          type: 'behavior',
          title: 'Episode $i',
          body: 'Loki vomited — episode $i.',
          ts: DateTime(2026, 4, i),
        );
      }
      await wikiRepo.writeEntry(
        petId: petId,
        type: 'behavior',
        title: 'Itchy',
        body: 'Lots of scratching today.',
        ts: DateTime(2026, 4, 10),
      );

      final freq = await trends.symptomFrequencies(petId);
      // Top entry should be Vomiting (count 3); next non-zero is
      // Scratching (count 1). The remaining keywords sit at 0.
      expect(freq.first.label, 'Vomiting');
      expect(freq.first.count, 3);
      final scratching = freq.firstWhere((f) => f.label == 'Scratching');
      expect(scratching.count, 1);
    });

    test('isolates pets — symptoms in one pet\'s journal don\'t bleed '
        'into another pet\'s frequencies', () async {
      final otherId = await petRepo.createPet(name: 'Mochi', category: 'cat');
      await wikiRepo.writeEntry(
        petId: otherId,
        type: 'behavior',
        title: 'Cat',
        body: 'Mochi vomited a hairball.',
        ts: DateTime(2026, 4, 1),
      );
      final dogFreq = await trends.symptomFrequencies(petId);
      final catFreq = await trends.symptomFrequencies(otherId);
      expect(
        dogFreq.firstWhere((f) => f.label == 'Vomiting').count,
        0,
        reason: "the cat's vomit doesn't show in the dog's chart",
      );
      expect(
        catFreq.firstWhere((f) => f.label == 'Vomiting').count,
        1,
      );
    });

    test('returns all-zero rows when the pet has no journal entries',
        () async {
      final freq = await trends.symptomFrequencies(petId);
      expect(freq, hasLength(TrendsRepo.symptomKeywords.length));
      expect(freq.every((f) => f.count == 0), isTrue);
    });
  });
}

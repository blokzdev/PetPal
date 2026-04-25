import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/repos/wiki_repo.dart';
import 'package:petpal/data/wiki_io_fs.dart';

void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late WikiIoFs wiki;
  late WikiRepo repo;
  const petId = 1;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('petpal_wiki_repo_');
    db = AppDatabase(NativeDatabase.memory());
    wiki = WikiIoFs(tempRoot);
    repo = WikiRepo(db: db, wiki: wiki);
    // The schema's pets FK forces a real pet row.
    await db.into(db.pets).insert(
          PetsCompanion.insert(name: 'Milo', createdAt: DateTime(2026, 4, 25)),
        );
  });

  tearDown(() async {
    await db.close();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  group('entryPath', () {
    test('builds wiki/<id>/<type>/<date>-<slug>.md', () {
      expect(
        entryPath(
          petId: 1,
          type: 'vet',
          title: 'Annual checkup',
          ts: DateTime(2026, 1, 12),
        ),
        'wiki/1/vet/2026-01-12-annual-checkup.md',
      );
    });
  });

  group('parseEntryPath', () {
    test('round-trips type, date, and slug-as-title', () {
      final p = parseEntryPath('wiki/1/vet/2026-01-12-annual-checkup.md');
      expect(p, isNotNull);
      expect(p!.petId, 1);
      expect(p.type, 'vet');
      expect(p.ts, DateTime(2026, 1, 12));
      expect(p.title, 'annual checkup');
    });

    test('returns null for SOUL.md', () {
      expect(parseEntryPath('wiki/1/SOUL.md'), isNull);
    });

    test('returns null for weight/log.md', () {
      expect(parseEntryPath('wiki/1/weight/log.md'), isNull);
    });
  });

  group('writeEntry', () {
    test('writes file, inserts entries row, populates FTS5', () async {
      final id = await repo.writeEntry(
        petId: petId,
        type: 'food',
        title: 'Frozen carrot trial',
        body: 'Milo loved the frozen carrots. Will repeat.',
        ts: DateTime(2026, 4, 25),
      );

      final fileBody = await wiki.read(
        'wiki/$petId/food/2026-04-25-frozen-carrot-trial.md',
      );
      expect(fileBody, contains('frozen carrots'));

      final row = await (db.select(db.entries)
            ..where((e) => e.id.equals(id)))
          .getSingle();
      expect(row.path, 'wiki/$petId/food/2026-04-25-frozen-carrot-trial.md');
      expect(row.type, 'food');
      expect(row.title, 'Frozen carrot trial');

      final hits = await db.customSelect(
        '''SELECT rowid FROM entries_fts5 WHERE entries_fts5 MATCH 'carrot*' ''',
      ).get();
      expect(hits.map((r) => r.read<int>('rowid')).toList(), [id]);
    });

    test('overwriting same path updates the row and FTS5 in place',
        () async {
      final ts = DateTime(2026, 4, 25);
      final firstId = await repo.writeEntry(
        petId: petId,
        type: 'behavior',
        title: 'Skateboard fear',
        body: 'Milo bolts from skateboards.',
        ts: ts,
      );
      final secondId = await repo.writeEntry(
        petId: petId,
        type: 'behavior',
        title: 'Skateboard fear',
        body: 'Update: Milo only flinches at skateboards now.',
        ts: ts,
      );

      expect(secondId, firstId);
      final row = await (db.select(db.entries)
            ..where((e) => e.id.equals(firstId)))
          .getSingle();
      expect(row.bodyHash, isNot('')); // body_hash got refreshed

      final flinchHits = await db.customSelect(
        '''SELECT rowid FROM entries_fts5 WHERE entries_fts5 MATCH 'flinch*' ''',
      ).get();
      expect(flinchHits, hasLength(1));

      final boltsHits = await db.customSelect(
        '''SELECT rowid FROM entries_fts5 WHERE entries_fts5 MATCH 'bolts' ''',
      ).get();
      expect(boltsHits, isEmpty);
    });
  });

  group('rebuildIndex', () {
    test('indexes a file that exists on disk but not in the DB', () async {
      // Drop a markdown file directly via the IO layer (bypassing repo).
      await wiki.writeAtomic(
        'wiki/$petId/vet/2026-01-12-annual-checkup.md',
        'Routine. All vitals normal.',
      );

      await repo.rebuildIndex(petId);

      final rows = await (db.select(db.entries)
            ..where((e) => e.petId.equals(petId)))
          .get();
      expect(rows, hasLength(1));
      expect(rows.first.type, 'vet');
      expect(rows.first.ts, DateTime(2026, 1, 12));

      final hits = await db.customSelect(
        '''SELECT rowid FROM entries_fts5 WHERE entries_fts5 MATCH 'vitals' ''',
      ).get();
      expect(hits, hasLength(1));
    });

    test('prunes a row whose file has been deleted from disk', () async {
      await repo.writeEntry(
        petId: petId,
        type: 'food',
        title: 'Treat trial',
        body: 'Liked them.',
        ts: DateTime(2026, 4, 25),
      );
      // Delete the file behind the repo's back.
      File('${tempRoot.path}/wiki/$petId/food/2026-04-25-treat-trial.md')
          .deleteSync();

      await repo.rebuildIndex(petId);

      expect(await db.select(db.entries).get(), isEmpty);
      final hits = await db.customSelect(
        '''SELECT rowid FROM entries_fts5 WHERE entries_fts5 MATCH 'liked' ''',
      ).get();
      expect(hits, isEmpty);
    });

    test('skips files whose body hash is unchanged (idempotent)', () async {
      final id = await repo.writeEntry(
        petId: petId,
        type: 'food',
        title: 'Treat trial',
        body: 'Liked them.',
        ts: DateTime(2026, 4, 25),
      );
      final before = await (db.select(db.entries)
            ..where((e) => e.id.equals(id)))
          .getSingle();

      await repo.rebuildIndex(petId);

      final after = await (db.select(db.entries)
            ..where((e) => e.id.equals(id)))
          .getSingle();
      expect(after.bodyHash, before.bodyHash);
      // Row count unchanged.
      expect(await db.select(db.entries).get(), hasLength(1));
    });

    test('skips paths that do not match the entry layout (e.g. SOUL.md)',
        () async {
      await wiki.writeAtomic('wiki/$petId/SOUL.md', '---\n---\n# Milo\n');
      await wiki.writeAtomic(
        'wiki/$petId/vet/2026-01-12-checkup.md',
        'Visit notes.',
      );

      await repo.rebuildIndex(petId);

      final rows = await db.select(db.entries).get();
      expect(rows, hasLength(1));
      expect(rows.first.path, 'wiki/$petId/vet/2026-01-12-checkup.md');
    });
  });
}

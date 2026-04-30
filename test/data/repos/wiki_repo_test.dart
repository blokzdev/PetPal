import 'dart:io';
import 'dart:typed_data';

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

    test('rebuilds the entire index from files alone — the rebuildable '
        'index invariant from DECISIONS row 1', () async {
      // Seed three entries through the repo (file + entries row + FTS5).
      await repo.writeEntry(
        petId: petId,
        type: 'food',
        title: 'Carrot trial',
        body: 'Milo loves frozen carrots.',
        ts: DateTime(2026, 4, 25),
      );
      await repo.writeEntry(
        petId: petId,
        type: 'behavior',
        title: 'Skateboard fear',
        body: 'Milo bolts when skateboards roll past.',
        ts: DateTime(2026, 4, 26),
      );
      await repo.writeEntry(
        petId: petId,
        type: 'vet',
        title: 'Annual checkup',
        body: 'Vitals normal.',
        ts: DateTime(2026, 4, 27),
      );

      // Wipe both the entries table AND the FTS5 mirror, simulating a
      // fresh-install rebuild with the markdown files still on disk.
      await db.delete(db.entries).go();
      await db.customStatement('DELETE FROM entries_fts5');
      expect(await db.select(db.entries).get(), isEmpty);

      await repo.rebuildIndex(petId);

      final rows = await db.select(db.entries).get();
      expect(rows, hasLength(3));
      expect(rows.map((r) => r.type).toSet(), {'food', 'behavior', 'vet'});

      final ftsHits = await db.customSelect(
        '''SELECT rowid FROM entries_fts5 WHERE entries_fts5 MATCH 'carrot* OR skateboard* OR vital*' ''',
      ).get();
      expect(ftsHits, hasLength(3));
    });
  });

  group('writePhoto (Phase 6 task 6.1)', () {
    Uint8List fakeJpegBytes([int n = 1024]) =>
        Uint8List.fromList(List<int>.filled(n, 0xff));

    test('writes the .jpg + .md sidecar pair on disk and indexes the '
        'sidecar with type=photos', () async {
      final result = await repo.writePhoto(
        petId: petId,
        imageBytes: fakeJpegBytes(2048),
        caption: 'Loki at the park',
        ts: DateTime(2026, 4, 25, 14, 30, 12),
        photoId: 'fixed-id',
      );

      expect(result.success, isTrue);
      expect(result.photoId, 'fixed-id');
      expect(result.binaryPath, 'wiki/$petId/photos/fixed-id.jpg');
      expect(result.sidecarPath, 'wiki/$petId/photos/fixed-id.md');
      expect(result.error, isNull);
      expect(result.warningBytes, isNull);

      // Both files landed on disk.
      expect(
        File('${tempRoot.path}/wiki/$petId/photos/fixed-id.jpg').existsSync(),
        isTrue,
      );
      expect(
        File('${tempRoot.path}/wiki/$petId/photos/fixed-id.md').existsSync(),
        isTrue,
      );

      // Sidecar contains the locked 6.1-minimum frontmatter + caption.
      final sidecar = File(
        '${tempRoot.path}/wiki/$petId/photos/fixed-id.md',
      ).readAsStringSync();
      expect(sidecar, contains('type: photos'));
      expect(sidecar, contains('image: fixed-id.jpg'));
      expect(sidecar, contains('ts: 2026-04-25T14:30:12'));
      expect(sidecar, contains('byte_size: 2048'));
      expect(sidecar, contains('Loki at the park'));

      // Sidecar is indexed as the entry; binary is NOT.
      final entries = await db.select(db.entries).get();
      expect(entries, hasLength(1));
      expect(entries.single.path, 'wiki/$petId/photos/fixed-id.md');
      expect(entries.single.type, 'photos');
      expect(entries.single.title, 'Loki at the park');
    });

    test('FTS5 indexes the caption — search finds the photo by caption '
        'text', () async {
      await repo.writePhoto(
        petId: petId,
        imageBytes: fakeJpegBytes(),
        caption: 'sunset at the trailhead',
      );

      final hits = await db.customSelect(
        "SELECT rowid FROM entries_fts5 WHERE entries_fts5 MATCH 'trailhead'",
      ).get();
      expect(hits, hasLength(1));
    });

    test('empty caption falls back to "Photo" as the indexed title — no '
        'UUID leak in the journal browser tile', () async {
      final result = await repo.writePhoto(
        petId: petId,
        imageBytes: fakeJpegBytes(),
        caption: '',
        photoId: 'no-caption-id',
      );

      expect(result.success, isTrue);
      final entries = await db.select(db.entries).get();
      expect(entries.single.title, 'Photo');
    });

    test('hard-limit reject: pre-write check refuses when the next '
        'write would exceed the budget; neither file lands on disk',
        () async {
      // Force a tight budget so the small fake bytes blow it.
      final result = await repo.writePhoto(
        petId: petId,
        imageBytes: fakeJpegBytes(2048),
        caption: 'will not save',
        photoId: 'rejected',
        hardLimitBytes: 1024,
      );

      expect(result.success, isFalse);
      expect(result.error, PhotoSaveError.storageFull);
      expect(result.sidecarPath, isNull);
      expect(result.binaryPath, isNull);

      // Neither file was written.
      expect(
        File('${tempRoot.path}/wiki/$petId/photos/rejected.jpg').existsSync(),
        isFalse,
      );
      expect(
        File('${tempRoot.path}/wiki/$petId/photos/rejected.md').existsSync(),
        isFalse,
      );
      // No entries row for the rejected photo.
      expect(await db.select(db.entries).get(), isEmpty);
    });

    test('warn threshold: post-write usage above warnBytes returns '
        'warningBytes (write still succeeds)', () async {
      final result = await repo.writePhoto(
        petId: petId,
        imageBytes: fakeJpegBytes(2048),
        caption: 'about to bump the warn line',
        photoId: 'warn-id',
        warnBytes: 1024,
      );

      expect(result.success, isTrue);
      expect(result.warningBytes, isNotNull);
      expect(result.warningBytes! >= 2048, isTrue);
    });

    test('photoBinaryPath / photoSidecarPath produce the canonical '
        'wiki/<petId>/photos/<id>.{jpg,md} layout', () {
      expect(
        photoBinaryPath(petId: 7, photoId: 'abc'),
        'wiki/7/photos/abc.jpg',
      );
      expect(
        photoBinaryPath(petId: 7, photoId: 'abc', ext: 'png'),
        'wiki/7/photos/abc.png',
      );
      expect(
        photoSidecarPath(petId: 7, photoId: 'abc'),
        'wiki/7/photos/abc.md',
      );
    });

    test('mime type → extension mapping covers the v1 set + falls back '
        'to .jpg for unknown types (consistent with the 6.6 resize '
        'normalising to JPEG)', () async {
      final png = await repo.writePhoto(
        petId: petId,
        imageBytes: fakeJpegBytes(),
        caption: 'png upload',
        mimeType: 'image/png',
        photoId: 'png-id',
      );
      expect(png.binaryPath, endsWith('png-id.png'));

      final unknown = await repo.writePhoto(
        petId: petId,
        imageBytes: fakeJpegBytes(),
        caption: 'unknown',
        mimeType: 'image/something-weird',
        photoId: 'fallback-id',
      );
      expect(unknown.binaryPath, endsWith('fallback-id.jpg'));
    });

    test('parseEntryPath does NOT match the photo sidecar shape — that '
        'is intentional: photo paths use UUIDs not <date>-<slug>, and '
        'rebuildIndex relies on writePhoto for indexing rather than '
        'path-only parsing', () {
      final p = parseEntryPath('wiki/1/photos/abc-123.md');
      expect(p, isNull);
    });
  });
}

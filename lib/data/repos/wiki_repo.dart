import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../harness/retrieval/embedding_worker.dart';
import '../db/database.dart';
import '../wiki_io.dart';
import '../wiki_slug.dart';

/// Write-through index for the per-pet wiki.
///
/// The on-disk markdown files are the source of truth. [writeEntry] writes the
/// file via [WikiIo], inserts/updates the matching `entries` row, and keeps
/// the `entries_fts5` virtual table in sync — all inside a single Drift
/// transaction so the index can never disagree with the file we just wrote.
///
/// [rebuildIndex] is the recovery path: walk a pet's files, upsert one row
/// per file, prune rows whose files no longer exist. Idempotent — files
/// whose body hash hasn't changed are skipped.
class WikiRepo {
  WikiRepo({
    required AppDatabase db,
    required WikiIo wiki,
    EmbeddingWorker? embeddings,
  })  : _db = db,
        _wiki = wiki,
        _embeddings = embeddings;

  final AppDatabase _db;
  final WikiIo _wiki;
  final EmbeddingWorker? _embeddings;

  /// Write or overwrite an entry. The path is computed as
  /// `wiki/<petId>/<type>/<YYYY-MM-DD>-<slug>.md`. Returns the entry's id.
  Future<int> writeEntry({
    required int petId,
    required String type,
    required String title,
    required String body,
    required DateTime ts,
  }) async {
    final path = entryPath(petId: petId, type: type, title: title, ts: ts);
    return _writeAt(
      path: path,
      petId: petId,
      type: type,
      title: title,
      body: body,
      ts: ts,
    );
  }

  /// Rebuild a pet's `entries` rows from the files on disk. Files whose
  /// body hash already matches the indexed row are skipped. Rows whose
  /// files no longer exist are deleted.
  Future<void> rebuildIndex(int petId) async {
    final diskPaths = (await _wiki.listForPet(petId)).toSet();
    final indexed = await (_db.select(_db.entries)
          ..where((e) => e.petId.equals(petId)))
        .get();

    // Drop rows whose files are gone.
    for (final row in indexed) {
      if (!diskPaths.contains(row.path)) {
        await (_db.delete(_db.entries)..where((e) => e.id.equals(row.id)))
            .go();
        await _db.customStatement(
          'DELETE FROM entries_fts5 WHERE rowid = ?',
          [row.id],
        );
      }
    }

    final byPath = {for (final r in indexed) r.path: r};
    for (final path in diskPaths) {
      final body = await _wiki.read(path);
      final hash = _hash(body);
      final existing = byPath[path];
      if (existing != null && existing.bodyHash == hash) continue;

      final parsed = parseEntryPath(path);
      if (parsed == null) continue;

      await _writeAt(
        path: path,
        petId: petId,
        type: parsed.type,
        title: parsed.title,
        body: body,
        ts: parsed.ts,
        skipFileWrite: true,
      );
    }
  }

  /// Internal: index the entry whose body is already at [path] (or write it
  /// when [skipFileWrite] is false).
  Future<int> _writeAt({
    required String path,
    required int petId,
    required String type,
    required String title,
    required String body,
    required DateTime ts,
    bool skipFileWrite = false,
  }) async {
    final hash = _hash(body);

    final id = await _db.transaction(() async {
      if (!skipFileWrite) {
        await _wiki.writeAtomic(path, body);
      }
      final existing = await (_db.select(_db.entries)
            ..where((e) => e.path.equals(path)))
          .getSingleOrNull();

      if (existing == null) {
        final newId = await _db.into(_db.entries).insert(
              EntriesCompanion.insert(
                petId: petId,
                path: path,
                type: type,
                ts: ts,
                title: title,
                bodyHash: hash,
              ),
            );
        await _db.customStatement(
          'INSERT INTO entries_fts5 (rowid, title, body) VALUES (?, ?, ?)',
          [newId, title, body],
        );
        return newId;
      } else {
        await (_db.update(_db.entries)
              ..where((e) => e.id.equals(existing.id)))
            .write(
          EntriesCompanion(
            ts: Value(ts),
            type: Value(type),
            title: Value(title),
            bodyHash: Value(hash),
          ),
        );
        await _db.customStatement(
          'UPDATE entries_fts5 SET title = ?, body = ? WHERE rowid = ?',
          [title, body, existing.id],
        );
        return existing.id;
      }
    });

    // Embedding is queued *outside* the txn so a slow/failing model in 1.12
    // doesn't roll back the file + index. The entry is durable; the
    // embedding catches up on the next rebuildIndex if it fails here.
    await _embeddings?.enqueue(entryId: id, body: body);
    return id;
  }
}

String _hash(String body) =>
    sha256.convert(utf8.encode(body)).toString();

/// Path the wiki uses for a new entry of [type] at [ts] with [title].
String entryPath({
  required int petId,
  required String type,
  required String title,
  required DateTime ts,
}) {
  final date = '${ts.year.toString().padLeft(4, '0')}-'
      '${ts.month.toString().padLeft(2, '0')}-'
      '${ts.day.toString().padLeft(2, '0')}';
  return 'wiki/$petId/$type/$date-${slugify(title)}.md';
}

/// Parsed view of an entry path: `wiki/<petId>/<type>/<YYYY-MM-DD>-<slug>.md`.
class ParsedEntryPath {
  ParsedEntryPath({
    required this.petId,
    required this.type,
    required this.ts,
    required this.title,
  });

  final int petId;
  final String type;
  final DateTime ts;
  final String title;
}

/// Parse a wiki-relative entry path. Returns null if the shape doesn't match
/// the documented `wiki/<petId>/<type>/<date>-<slug>.md` layout — e.g.
/// SOUL.md or weight/log.md, which rebuildIndex skips.
ParsedEntryPath? parseEntryPath(String path) {
  final m = RegExp(
    r'^wiki/(\d+)/([^/]+)/(\d{4})-(\d{2})-(\d{2})-([^/]+)\.md$',
  ).firstMatch(path);
  if (m == null) return null;
  final petId = int.parse(m.group(1)!);
  final type = m.group(2)!;
  final year = int.parse(m.group(3)!);
  final month = int.parse(m.group(4)!);
  final day = int.parse(m.group(5)!);
  final slug = m.group(6)!;
  return ParsedEntryPath(
    petId: petId,
    type: type,
    ts: DateTime(year, month, day),
    title: slug.replaceAll('-', ' '),
  );
}

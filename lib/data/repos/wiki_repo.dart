import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../harness/retrieval/embedding_worker.dart';
import '../db/database.dart';
import '../photo_id.dart';
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

  /// Phase 6 task 6.1 — write a photo entry: the `.jpg` (or other
  /// image) binary plus its sidecar `.md`. The sidecar is the indexed
  /// `Entry` (the binary lives next to it on disk but never in the
  /// `entries` table) — its frontmatter carries an `image:` pointer to
  /// the binary's filename. FTS5 indexes the sidecar's caption body.
  ///
  /// Atomic-write semantics: writes the `.jpg` first, then the sidecar
  /// `.md`. If the `.md` write throws, the orphaned `.jpg` is deleted
  /// so storage accounting stays honest (sidecar is the source of
  /// truth for "this photo exists").
  ///
  /// Storage budget (locked thresholds):
  ///   warn at  500 MB / pet → result includes `warningBytes`
  ///   reject at  1 GB / pet → write doesn't run, returns `error =
  ///                          PhotoSaveError.storageFull`
  /// The pre-write check is intentionally not transactional with the
  /// write — single-user app, no parallel-save race in v1. Pre-write
  /// resize lands at task 6.6 to keep the budget honest (~600 KB per
  /// saved photo); 6.1 just persists raw bytes.
  Future<PhotoSaveResult> writePhoto({
    required int petId,
    required Uint8List imageBytes,
    required String caption,
    DateTime? ts,
    String mimeType = 'image/jpeg',
    String? photoId,
    // Budget thresholds default to the locked constants. Overrides
    // exist for testability (the budget paths are otherwise hard to
    // exercise without 500 MB of scratch files); production callers
    // never set them.
    int warnBytes = photoStorageWarnBytes,
    int hardLimitBytes = photoStorageHardLimitBytes,
  }) async {
    final usedBefore = await _wiki.bytesForPet(petId);
    final incomingBytes = imageBytes.length;
    if (usedBefore + incomingBytes >= hardLimitBytes) {
      return PhotoSaveResult.failed(
        PhotoSaveError.storageFull,
        bytesUsed: usedBefore,
      );
    }

    final id = photoId ?? newPhotoId();
    final ext = _extForMimeType(mimeType);
    final binaryPath = photoBinaryPath(petId: petId, photoId: id, ext: ext);
    final sidecarPath = photoSidecarPath(petId: petId, photoId: id);
    final timestamp = ts ?? DateTime.now();
    final sidecarBody = _composePhotoSidecar(
      imageFilename: '$id.$ext',
      ts: timestamp,
      byteSize: incomingBytes,
      caption: caption,
    );

    // Binary lands first. If the sidecar write fails after this, we
    // clean up the orphan so a follow-up call sees a consistent state.
    await _wiki.writeBytesAtomic(binaryPath, imageBytes);
    try {
      // Empty captions fall back to "Photo" for the indexed title —
      // surfaces cleanly in the journal browser tile + FTS5 row
      // without leaking the UUID. The user can edit the caption in
      // 6.6's form preview to set a real title.
      await _writeAt(
        path: sidecarPath,
        petId: petId,
        type: 'photos',
        title: caption.trim().isEmpty ? 'Photo' : caption.trim(),
        body: sidecarBody,
        ts: timestamp,
      );
    } catch (_) {
      // Best-effort cleanup. If this also fails, log via the next
      // bytesForPet read — the orphan stays until rebuildIndex picks
      // it up. We don't escalate the cleanup error; the original
      // sidecar-write failure is what the caller needs to see.
      await _wiki.deleteIfExists(binaryPath);
      rethrow;
    }

    final usedAfter = usedBefore + incomingBytes + sidecarBody.length;
    final warning = usedAfter >= warnBytes ? usedAfter : null;
    return PhotoSaveResult.success(
      sidecarPath: sidecarPath,
      binaryPath: binaryPath,
      photoId: id,
      bytesUsed: usedAfter,
      warningBytes: warning,
    );
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

/// Photo storage budget thresholds (Phase 6 task 6.1, ROADMAP lock).
/// Soft warn at 500 MB so the UI can surface a banner; hard reject at
/// 1 GB so a runaway pet doesn't fill the device. Pre-write resize at
/// 6.6 keeps the running budget honest (~600 KB / saved photo).
const int photoStorageWarnBytes = 500 * 1024 * 1024;
const int photoStorageHardLimitBytes = 1024 * 1024 * 1024;

/// Wiki-relative path to a photo's binary file. The file extension
/// derives from the mime type — JPEG saves as `.jpg`, PNG as `.png`.
/// The 6.6 pre-write resize normalises everything to JPEG so most
/// real photos land at `.jpg`.
String photoBinaryPath({
  required int petId,
  required String photoId,
  String ext = 'jpg',
}) =>
    'wiki/$petId/photos/$photoId.$ext';

/// Wiki-relative path to a photo's sidecar `.md`. The sidecar is the
/// indexed entry; its frontmatter `image:` pointer carries the
/// matching binary filename. `parseEntryPath()` returns null for this
/// shape (no date prefix); photo entries don't fit the
/// `<YYYY-MM-DD>-<slug>.md` template.
String photoSidecarPath({required int petId, required String photoId}) =>
    'wiki/$petId/photos/$photoId.md';

String _extForMimeType(String mime) {
  switch (mime.toLowerCase()) {
    case 'image/jpeg':
    case 'image/jpg':
      return 'jpg';
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    case 'image/heic':
    case 'image/heif':
      return 'heic';
    default:
      // Fall back to jpg — Anthropic's vision API also accepts the
      // less-common types (webp, gif) but the 6.6 resize normalises
      // to jpeg before they reach disk.
      return 'jpg';
  }
}

/// Compose a photo sidecar body from its 6.1-minimum frontmatter +
/// freeform caption. The optional fields (`setting`, `activity`,
/// `demeanor`, `notable_objects`, `enrichment_hints`, `red_flag_match`)
/// are additive at 6.5 / 6.7 via `mergeFrontmatter` — leaving them off
/// at 6.1 keeps the sidecar small and the schema additive.
String _composePhotoSidecar({
  required String imageFilename,
  required DateTime ts,
  required int byteSize,
  required String caption,
}) {
  final iso =
      '${ts.year.toString().padLeft(4, '0')}-'
      '${ts.month.toString().padLeft(2, '0')}-'
      '${ts.day.toString().padLeft(2, '0')}T'
      '${ts.hour.toString().padLeft(2, '0')}:'
      '${ts.minute.toString().padLeft(2, '0')}:'
      '${ts.second.toString().padLeft(2, '0')}';
  final safeCaption = caption.trim();
  return '---\n'
      'type: photos\n'
      'image: $imageFilename\n'
      'ts: $iso\n'
      'byte_size: $byteSize\n'
      '---\n'
      '\n'
      '$safeCaption${safeCaption.isEmpty ? '' : '\n'}';
}

/// Outcome of a [WikiRepo.writePhoto] call. Sealed via factory
/// constructors so callers can pattern-match success / warning /
/// error without try/catch around foreseeable failure modes.
class PhotoSaveResult {
  const PhotoSaveResult._({
    required this.success,
    this.sidecarPath,
    this.binaryPath,
    this.photoId,
    this.bytesUsed = 0,
    this.warningBytes,
    this.error,
  });

  factory PhotoSaveResult.success({
    required String sidecarPath,
    required String binaryPath,
    required String photoId,
    required int bytesUsed,
    int? warningBytes,
  }) =>
      PhotoSaveResult._(
        success: true,
        sidecarPath: sidecarPath,
        binaryPath: binaryPath,
        photoId: photoId,
        bytesUsed: bytesUsed,
        warningBytes: warningBytes,
      );

  factory PhotoSaveResult.failed(
    PhotoSaveError error, {
    required int bytesUsed,
  }) =>
      PhotoSaveResult._(
        success: false,
        bytesUsed: bytesUsed,
        error: error,
      );

  final bool success;
  final String? sidecarPath;
  final String? binaryPath;
  final String? photoId;

  /// Total bytes used by the pet's wiki dir AFTER this write (or
  /// pre-rejection bytes if [success] is false).
  final int bytesUsed;

  /// Non-null when the post-write usage crossed the 500 MB warn
  /// threshold. The caller surfaces a banner; the write still
  /// succeeded.
  final int? warningBytes;

  /// Non-null on failure (storage full, IO error). [success] is then
  /// false and the binary + sidecar weren't written.
  final PhotoSaveError? error;
}

enum PhotoSaveError {
  /// Pre-write check rejected: pet's bytes-used + incoming bytes
  /// would exceed [photoStorageHardLimitBytes].
  storageFull,
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

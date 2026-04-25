import 'package:drift/drift.dart';

import '../../data/db/database.dart';
import 'embedding_worker.dart' show floatsToBytes;

/// One result from a retrieval pass.
class Hit {
  Hit({
    required this.entryId,
    required this.path,
    required this.title,
    required this.score,
    this.snippet,
  });

  final int entryId;
  final String path;
  final String title;

  /// FTS5 snippet (with `«»` markers around matched terms) when the hit came
  /// from the keyword side; null for vector-only hits.
  final String? snippet;

  /// Fused score after reciprocal-rank fusion. Higher is better. Useful for
  /// debugging; callers should typically just consume the ranked order.
  final double score;
}

/// Hybrid retrieval over a single pet's wiki: FTS5 keyword search ∪ vector
/// kNN, fused with reciprocal-rank fusion (Cormack et al., 2009) and
/// deduped by entry id.
class HybridRetriever {
  HybridRetriever({required AppDatabase db, this.rrfK = 60}) : _db = db;

  final AppDatabase _db;

  /// RRF smoothing constant. 60 is the value from the original paper and a
  /// reasonable default; raising it dampens the influence of top-1 hits.
  final int rrfK;

  /// Returns up to [k] hits for [petId]. If [queryText] is empty, only the
  /// vector side runs; if [queryVector] is null, only the keyword side runs.
  Future<List<Hit>> search({
    required int petId,
    String queryText = '',
    List<double>? queryVector,
    int k = 10,
  }) async {
    final ftsQuery = _sanitizeFtsQuery(queryText);
    final ftsRows = ftsQuery.isEmpty
        ? const <QueryRow>[]
        : await _db.customSelect(
            '''
            SELECT e.id AS id, e.path AS path, e.title AS title,
                   snippet(entries_fts5, 1, '«', '»', '…', 12) AS snippet
            FROM entries_fts5
            JOIN entries e ON e.id = entries_fts5.rowid
            WHERE entries_fts5 MATCH ?
              AND e.pet_id = ?
            LIMIT ?
            ''',
            variables: [
              Variable<String>(ftsQuery),
              Variable<int>(petId),
              Variable<int>(k),
            ],
          ).get();

    final vecRows = queryVector == null
        ? const <QueryRow>[]
        : await _db.customSelect(
            '''
            SELECT e.id AS id, e.path AS path, e.title AS title,
                   vec_distance_l2(em.vector, ?) AS dist
            FROM embeddings em
            JOIN entries e ON e.id = em.entry_id
            WHERE e.pet_id = ?
            ORDER BY dist ASC
            LIMIT ?
            ''',
            variables: [
              Variable<Uint8List>(floatsToBytes(queryVector)),
              Variable<int>(petId),
              Variable<int>(k),
            ],
          ).get();

    final scores = <int, double>{};
    final paths = <int, String>{};
    final titles = <int, String>{};
    final snippets = <int, String>{};

    for (var i = 0; i < ftsRows.length; i++) {
      final row = ftsRows[i];
      final id = row.read<int>('id');
      scores[id] = (scores[id] ?? 0) + 1 / (rrfK + i + 1);
      paths[id] = row.read<String>('path');
      titles[id] = row.read<String>('title');
      snippets[id] = row.read<String>('snippet');
    }

    for (var i = 0; i < vecRows.length; i++) {
      final row = vecRows[i];
      final id = row.read<int>('id');
      scores[id] = (scores[id] ?? 0) + 1 / (rrfK + i + 1);
      paths.putIfAbsent(id, () => row.read<String>('path'));
      titles.putIfAbsent(id, () => row.read<String>('title'));
    }

    final ids = scores.keys.toList()
      ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
    return [
      for (final id in ids.take(k))
        Hit(
          entryId: id,
          path: paths[id]!,
          title: titles[id]!,
          score: scores[id]!,
          snippet: snippets[id],
        ),
    ];
  }
}

/// Convert a free-form natural-language query into safe FTS5 syntax: lowercase
/// the input, split on non-alphanumerics (Unicode-aware), then OR-join each
/// token as a prefix match (`token*`). This neutralises FTS5 metacharacters
/// (`?`, parens, `AND`/`OR`, `*`) that natural-language queries leak in, and
/// uses OR + prefix so a question like "what treats does Milo like?" still
/// matches an entry containing only "carrots" (the vector side picks up
/// semantic gaps the lexical side misses).
String _sanitizeFtsQuery(String input) {
  final tokens = input
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return '';
  return tokens.map((t) => '$t*').join(' OR ');
}

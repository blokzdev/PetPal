import 'dart:typed_data';

import '../../data/db/database.dart';
import 'embedding_provider.dart';

/// Computes and persists embeddings for entry bodies.
///
/// The current implementation is synchronous-on-call: [enqueue] runs the
/// provider inline and writes the row before returning. That keeps WikiRepo's
/// write-through invariant intact (an entry is never indexed without its
/// embedding). When 1.12 swaps in a network-bound model and bodies grow large
/// enough to chunk, the work moves to a workmanager-backed queue and this
/// surface stays the same.
class EmbeddingWorker {
  EmbeddingWorker({
    required AppDatabase db,
    required EmbeddingProvider provider,
  })  : _db = db,
        _provider = provider;

  final AppDatabase _db;
  final EmbeddingProvider _provider;

  /// Compute the embedding for [body] and upsert it as
  /// `embeddings(entry_id=entryId, chunk_idx=0, vector=...)`.
  Future<void> enqueue({required int entryId, required String body}) async {
    final vector = await _provider.embed(body);
    final bytes = floatsToBytes(vector);
    await _db.into(_db.embeddings).insertOnConflictUpdate(
          EmbeddingsCompanion.insert(
            entryId: entryId,
            chunkIdx: 0,
            vector: bytes,
          ),
        );
  }
}

/// Encode a list of doubles as little-endian float32 bytes — the format
/// sqlite-vec expects in BLOB columns.
Uint8List floatsToBytes(List<double> v) {
  final bd = ByteData(v.length * 4);
  for (var i = 0; i < v.length; i++) {
    bd.setFloat32(i * 4, v[i], Endian.little);
  }
  return bd.buffer.asUint8List();
}

import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'embedding_provider.dart';

/// Deterministic fake embedding. Same input → same vector across runs and
/// devices, different inputs → different vectors. Quality is not real —
/// don't use this for retrieval semantics, only for end-to-end mechanism
/// tests until 1.12 swaps in a real provider.
class StubEmbeddingProvider implements EmbeddingProvider {
  const StubEmbeddingProvider({this.dim = 32});

  @override
  final int dim;

  @override
  Future<List<double>> embed(
    String text, {
    EmbeddingKind kind = EmbeddingKind.document,
  }) async {
    // Walk the SHA-256 digest cyclically to fill `dim` floats in [-1, 1].
    final bytes = sha256.convert(utf8.encode(text)).bytes;
    final v = List<double>.filled(dim, 0);
    for (var i = 0; i < dim; i++) {
      v[i] = (bytes[i % bytes.length] / 127.5) - 1.0;
    }
    var sumSq = 0.0;
    for (final x in v) {
      sumSq += x * x;
    }
    final norm = math.sqrt(sumSq);
    if (norm > 0) {
      for (var i = 0; i < dim; i++) {
        v[i] = v[i] / norm;
      }
    }
    return v;
  }
}

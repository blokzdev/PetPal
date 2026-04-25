/// Whether the text being embedded is a *query* (a user's question — used to
/// look things up) or a *document* (a wiki entry being indexed).
///
/// Some retrieval models — notably arctic-embed — are trained with an
/// asymmetric instruction: queries get a fixed prefix prepended, documents
/// don't. The provider handles the prefix; callers only need to pick the
/// right kind.
enum EmbeddingKind { query, document }

/// Source of embedding vectors. The on-device implementation is
/// [OnnxEmbeddingProvider]; tests use [StubEmbeddingProvider] for speed and
/// determinism.
abstract class EmbeddingProvider {
  /// Vector dimensionality. All vectors a provider returns must match.
  int get dim;

  /// Return a unit-normalized embedding for [text]. [kind] defaults to
  /// [EmbeddingKind.document] because the most common caller is the
  /// embedding worker indexing wiki entries; retrieval call sites
  /// (SessionBuilder, search_wiki tool) pass [EmbeddingKind.query]
  /// explicitly.
  Future<List<double>> embed(
    String text, {
    EmbeddingKind kind = EmbeddingKind.document,
  });
}

/// Source of embedding vectors. Real implementation lands in 1.12 (Anthropic
/// or local model behind this same interface). For now [StubEmbeddingProvider]
/// returns deterministic fake vectors so the queue + storage path is
/// exercisable end-to-end.
abstract class EmbeddingProvider {
  /// Vector dimensionality. All vectors a provider returns must match.
  int get dim;

  /// Return a unit-normalized embedding for [text].
  Future<List<double>> embed(String text);
}

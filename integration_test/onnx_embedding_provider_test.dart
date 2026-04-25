// Real on-device embedding model exercise. Loads the bundled
// arctic-embed-xs INT8 ONNX from Flutter assets, runs inference, and
// asserts the model produces semantically-coherent vectors.
//
// Run with: flutter test integration_test
//
// Lives in integration_test/ rather than test/ because flutter_onnxruntime's
// native plugin side compiles into the Flutter app — `flutter test` on the
// host does not load it.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:petpal/harness/retrieval/embedding_provider.dart';
import 'package:petpal/harness/retrieval/onnx_embedding_provider.dart';

double _dot(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

double _norm(List<double> v) {
  var sum = 0.0;
  for (final x in v) {
    sum += x * x;
  }
  return math.sqrt(sum);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late OnnxEmbeddingProvider provider;

  setUpAll(() async {
    provider = await OnnxEmbeddingProvider.fromAssets();
  });

  tearDownAll(() async {
    await provider.close();
  });

  test('embeds to 384 unit-normalized float dimensions', () async {
    final v = await provider.embed('Milo is a friendly dog.');
    expect(v, hasLength(384));
    expect(_norm(v), closeTo(1.0, 1e-3));
  });

  test('semantic similarity ranks pet-relevant documents above unrelated '
      'documents for a pet-related query', () async {
    final query = await provider.embed(
      'what treats does my dog like',
      kind: EmbeddingKind.query,
    );
    final relevant = await provider.embed(
      'Milo loves frozen carrots and naps after.',
    );
    final unrelated = await provider.embed(
      'How to install Linux on a Raspberry Pi.',
    );

    final simRelevant = _dot(query, relevant);
    final simUnrelated = _dot(query, unrelated);

    expect(simRelevant, greaterThan(simUnrelated));
  });

  test('query and document of the same text produce different vectors '
      '(asymmetric model)', () async {
    const text = 'Milo loves frozen carrots';
    final asQuery = await provider.embed(text, kind: EmbeddingKind.query);
    final asDocument = await provider.embed(
      text,
      // ignore: avoid_redundant_argument_values
      kind: EmbeddingKind.document,
    );

    // Same model, different inputs (prefix differs), so the vectors must
    // differ. They'll be close but not identical.
    final identicalDot = _dot(asQuery, asDocument);
    expect(identicalDot, lessThan(0.999));
  });

  test('embedding the same text twice produces the same vector', () async {
    final a = await provider.embed('Milo is a rescue mutt.');
    final b = await provider.embed('Milo is a rescue mutt.');
    for (var i = 0; i < a.length; i++) {
      expect(a[i], closeTo(b[i], 1e-5));
    }
  });
}

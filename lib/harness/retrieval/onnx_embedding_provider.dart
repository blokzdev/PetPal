import 'dart:io';
import 'dart:math' as math;

import 'package:dart_wordpiece/dart_wordpiece.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'embedding_provider.dart';

/// On-device text embedding via Snowflake's
/// `snowflake-arctic-embed-xs` (INT8 ONNX, ~23 MB, 384-dim,
/// distilled from MiniLM-L6 — beats vanilla MiniLM on MTEB retrieval).
/// Tokenization is pure-Dart WordPiece via `dart_wordpiece`; inference is
/// `flutter_onnxruntime` which fetches official ORT shared libs at install
/// time. The whole pipeline runs offline — no network calls per turn.
///
/// arctic-embed is asymmetric: queries get a fixed prefix prepended,
/// documents don't. Callers signal which is which via [EmbeddingKind] —
/// the embedding worker indexing wiki entries gets the default
/// (`document`); SessionBuilder's per-turn search and the `search_wiki`
/// tool pass `query`.
///
/// Pooling is **CLS**, not mean — see the model's `1_Pooling/config.json`.
/// Vectors are L2-normalized so cosine similarity equals the dot product,
/// matching what sqlite-vec's `vec_distance_l2` expects in our index.
class OnnxEmbeddingProvider implements EmbeddingProvider {
  OnnxEmbeddingProvider._({
    required WordPieceTokenizer tokenizer,
    required OrtSession session,
    required this.queryPrefix,
  })  : _tokenizer = tokenizer,
        _session = session;

  static const _modelAsset = 'assets/models/arctic-embed-xs/model_int8.onnx';
  static const _vocabAsset = 'assets/models/arctic-embed-xs/vocab.txt';
  static const _defaultQueryPrefix =
      'Represent this sentence for searching relevant passages: ';
  static const _maxLength = 512;
  static const _hiddenSize = 384;

  final WordPieceTokenizer _tokenizer;
  final OrtSession _session;

  /// Prefix prepended to query texts. arctic-embed-xs's
  /// `config_sentence_transformers.json` defines this.
  final String queryPrefix;

  @override
  int get dim => _hiddenSize;

  /// Production loader: reads model + vocab from Flutter assets via
  /// [rootBundle]. Requires a Flutter binding (app or widget test).
  static Future<OnnxEmbeddingProvider> fromAssets({
    String modelAsset = _modelAsset,
    String vocabAsset = _vocabAsset,
    String queryPrefix = _defaultQueryPrefix,
  }) async {
    final vocabText = await rootBundle.loadString(vocabAsset);
    final tokenizer = _buildTokenizer(vocabText);
    final session = await OnnxRuntime().createSessionFromAsset(modelAsset);
    return OnnxEmbeddingProvider._(
      tokenizer: tokenizer,
      session: session,
      queryPrefix: queryPrefix,
    );
  }

  /// Test loader: reads model + vocab from the host filesystem. Useful when
  /// `flutter test` runs on Linux/macOS and `rootBundle` has no asset bundle
  /// to draw from.
  static Future<OnnxEmbeddingProvider> fromFiles({
    required String modelPath,
    required String vocabPath,
    String queryPrefix = _defaultQueryPrefix,
  }) async {
    final vocabText = await File(vocabPath).readAsString();
    final tokenizer = _buildTokenizer(vocabText);
    final session = await OnnxRuntime().createSession(modelPath);
    return OnnxEmbeddingProvider._(
      tokenizer: tokenizer,
      session: session,
      queryPrefix: queryPrefix,
    );
  }

  static WordPieceTokenizer _buildTokenizer(String vocabText) {
    final vocab = VocabLoader.fromString(vocabText);
    return WordPieceTokenizer(
      vocab: vocab,
      config: const TokenizerConfig(maxLength: _maxLength),
    );
  }

  @override
  Future<List<double>> embed(
    String text,
    {EmbeddingKind kind = EmbeddingKind.document}) async {
    final input = kind == EmbeddingKind.query ? '$queryPrefix$text' : text;
    final encoded = _tokenizer.encode(input);

    final seqLen = encoded.inputIdsInt64.length;
    final shape = [1, seqLen];

    final inputs = <String, OrtValue>{
      'input_ids': await OrtValue.fromList(encoded.inputIdsInt64, shape),
      'attention_mask':
          await OrtValue.fromList(encoded.attentionMaskInt64, shape),
      'token_type_ids':
          await OrtValue.fromList(encoded.tokenTypeIdsInt64, shape),
    };

    Map<String, OrtValue> outputs;
    try {
      outputs = await _session.run(inputs);
    } finally {
      for (final v in inputs.values) {
        await v.dispose();
      }
    }

    try {
      final flat = await outputs['last_hidden_state']!.asFlattenedList();
      // flat layout is row-major [1, seqLen, 384]; CLS pooling = the first
      // 384 floats (batch=0, seq=0, all hidden dims).
      final pooled = List<double>.filled(_hiddenSize, 0);
      for (var i = 0; i < _hiddenSize; i++) {
        pooled[i] = (flat[i] as num).toDouble();
      }
      return _l2Normalize(pooled);
    } finally {
      for (final v in outputs.values) {
        await v.dispose();
      }
    }
  }

  /// Frees the ONNX session. Call when the provider is no longer needed —
  /// typically once at app shutdown.
  Future<void> close() => _session.close();
}

List<double> _l2Normalize(List<double> v) {
  var sumSq = 0.0;
  for (final x in v) {
    sumSq += x * x;
  }
  final norm = math.sqrt(sumSq);
  if (norm == 0) return v;
  for (var i = 0; i < v.length; i++) {
    v[i] = v[i] / norm;
  }
  return v;
}

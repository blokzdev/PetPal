import 'dart:async';
import 'dart:convert';

import '../agent/llm_client.dart';
import '../agent/messages.dart';
import '../retrieval/embedding_provider.dart';
import '../retrieval/hybrid_retriever.dart';
import 'affective_observation.dart';

/// Phase 6 task 6.8 — affective observation runner.
///
/// Takes a just-saved photo's caption, retrieves 3–5 prior memories
/// for the active pet via the existing FTS5 + vector hybrid retriever,
/// and asks Haiku to either (a) emit one warm grounded observation
/// or (b) decline. Returns null when:
///
///   - no prior memories were retrieved (nothing to ground on),
///   - the model declines or returns malformed JSON,
///   - the model claims `confidence` < `high`,
///   - the grounding citation is empty (ungrounded → drop),
///   - the call exceeds the timeout.
///
/// **Three compounding gates** per DECISIONS row 41 (b):
///   1. Grounding requirement (prompt + parse).
///   2. Confidence == high (parse-side gate).
///   3. Frequency cap (1-per-5-saves) — enforced by the **caller**
///      (`photo_capture_screen` consults SettingsStorage before
///      invoking this class; the observer never opens the second-
///      Anthropic call when the cap blocks).
///
/// **Build last + cuttable.** This whole module is behind the
/// "showAffectiveObservations" Settings toggle. Cutting to v1.2 = the
/// home-screen card stops surfacing + the observer is never invoked;
/// no schema changes to undo.
class AffectiveObserver {
  AffectiveObserver({
    required LlmClient llm,
    required HybridRetriever retriever,
    required EmbeddingProvider embeddings,
    Duration timeout = const Duration(seconds: 8),
  })  : _llm = llm,
        _retriever = retriever,
        _embeddings = embeddings,
        _timeout = timeout;

  final LlmClient _llm;
  final HybridRetriever _retriever;
  final EmbeddingProvider _embeddings;
  final Duration _timeout;

  /// The system-prompt anchor — locked verbatim per DECISIONS row 41
  /// (b). The model is REQUIRED to:
  ///
  ///  - cite a specific prior memory by date or title,
  ///  - hedge ("looks more relaxed", "seems livelier than"),
  ///  - return JSON only,
  ///  - decline cleanly when grounding is weak.
  ///
  /// VOICE.md §2 register applies: never diagnose, never project,
  /// never invent emotion. The locked phrasing is "warm-natural" — if
  /// production output drifts to scripted, this prompt is the lever
  /// to tighten.
  static const String _systemPrompt = '''
You are PetPal's affective layer. After the user saves a photo memory of
their pet, you read the new caption AND a small set of retrieved prior
memories, and either emit ONE warm sentence noticing a connection — or
you decline.

Output format. Return ONLY valid JSON. No prose, no markdown fences:

{
  "observation": "one short sentence, present tense, hedged",
  "grounding_ref": "short reference to the cited prior memory (e.g. 'the vet visit on March 12' or 'Loki at the trailhead last month')",
  "confidence": "low" | "med" | "high"
}

Or, when nothing genuine connects:

{ "decline": true }

HARD RULES — apply silently, never narrate them.

1. Cite a specific prior memory by date or title. The grounding_ref
   field MUST point at one of the retrieved memories. Don't invent
   memories; if none of the retrieved set fits, decline.
2. Hedge. "Looks more relaxed", "seems livelier than", "appears
   calmer". Never claim emotion as fact.
3. Never diagnose. Never project a vet finding. Never speculate about
   medical state. Behavioural observations only.
4. Never project. Don't put thoughts in the pet's head ("Loki was
   dreaming of frozen carrots"). Stay observational.
5. One sentence. Two at most. Short. The user is glancing at this
   from a snackbar, not reading a paragraph.
6. confidence: high ONLY when the connection is unambiguous AND the
   tone earns the warmth. Otherwise med or low — those will be
   filtered by the caller.

Decline when:
  - no retrieved memory plausibly connects to this photo,
  - the only plausible connection is medical or symptomatic (those
    are red-flag territory, not affective territory),
  - your honest confidence is med or low.
''';

  /// Run the observation pipeline. Returns null when any gate blocks.
  Future<AffectiveObservation?> observe({
    required int petId,
    required String caption,
    int retrievalK = 5,
  }) async {
    if (caption.trim().isEmpty) return null;

    try {
      // Retrieve 3–5 prior memories the caption might evoke. Use the
      // caption itself as both FTS5 keyword query and vector query —
      // that's the same shape SessionBuilder uses for chat retrieval.
      final queryVec = await _embeddings
          .embed(caption, kind: EmbeddingKind.query)
          .timeout(_timeout, onTimeout: () => const <double>[]);
      if (queryVec.isEmpty) return null;
      final hits = await _retriever.search(
        petId: petId,
        queryText: caption,
        queryVector: queryVec,
        k: retrievalK,
      );
      if (hits.isEmpty) return null;

      // Compose the user-turn body: the new caption + the retrieved
      // memories' titles + snippets. The model has everything it
      // needs to ground without us spoon-feeding which one to pick.
      final buf = StringBuffer()
        ..writeln('# New photo caption')
        ..writeln(caption)
        ..writeln()
        ..writeln('# Prior memories (retrieved, in score order)');
      for (final h in hits) {
        buf
          ..writeln('- "${h.title}"')
          ..writeln('  path: ${h.path}');
        if (h.snippet != null && h.snippet!.trim().isNotEmpty) {
          buf.writeln('  snippet: ${h.snippet}');
        }
      }

      final response = await _llm
          .turn(
            systemPrompt: _systemPrompt,
            history: [
              Message(
                role: Message.userRole,
                content: [TextBlock(buf.toString())],
              ),
            ],
          )
          .timeout(_timeout);

      final raw = _extractText(response);
      if (raw.isEmpty) return null;
      final json = _parseJson(raw);
      if (json == null) return null;

      // Decline path — clean exit.
      if (json['decline'] == true) return null;

      // confidence gate — high only.
      final conf = json['confidence'];
      if (conf is! String || conf.toLowerCase() != 'high') return null;

      // Grounding gate — non-empty ref required.
      final groundingRef = json['grounding_ref'];
      if (groundingRef is! String || groundingRef.trim().isEmpty) {
        return null;
      }

      // Build the observation. fromJson does the final shape check.
      return AffectiveObservation.fromJson({
        'text': json['observation'],
        'grounding_ref': groundingRef,
      });
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  String _extractText(Message response) {
    for (final block in response.content) {
      if (block is TextBlock) return block.text;
    }
    return '';
  }

  /// The model is told to return raw JSON, but defends against the
  /// common drift of wrapping in ```json fences (same pattern as
  /// PhotoExtractor.extract).
  Map<String, Object?>? _parseJson(String raw) {
    var trimmed = raw.trim();
    if (trimmed.startsWith('```')) {
      // Strip the opening fence (with or without `json`) and the
      // closing fence.
      final firstNl = trimmed.indexOf('\n');
      if (firstNl != -1) trimmed = trimmed.substring(firstNl + 1);
      final lastFence = trimmed.lastIndexOf('```');
      if (lastFence != -1) trimmed = trimmed.substring(0, lastFence);
      trimmed = trimmed.trim();
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, Object?>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }
}

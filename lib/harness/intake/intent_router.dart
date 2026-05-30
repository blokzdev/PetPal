import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../agent/llm_client.dart';
import '../agent/messages.dart';
import '../vision/vision_gate.dart';

/// Phase 8 task 8.0 — intake intent router. New harness primitive
/// per CLAUDE.md §3.5 + DECISIONS rows 98 + 104.
///
/// Today every photo becomes a generic memory; this router resolves
/// a snapped photo to an [IntakeIntent] so future lenses (food
/// first, then grooming / enclosure / activity / body-condition) can
/// branch the capture flow without reinventing classification.
///
/// **Hybrid resolution** (row 98 locked):
/// - [explicitHint] non-null → returned immediately, no LLM call.
/// - Otherwise → lightweight Haiku classification on the photo +
///   optional caption (DECISIONS row 41 (f) precedent for "Sonnet
///   for extraction, Haiku for lightweight classification").
///
/// **Always-safe contract**: every failure path (gate block, LLM
/// throw, timeout, parse failure, value drift) degrades to
/// [IntakeIntent.generalMemory]. The router is the always-safe
/// dispatcher; the capture flow can always proceed.
///
/// **Free per DECISIONS row 102** — intake is FREE, but the call
/// still routes through [VisionGate] so the entitlement / BYOK /
/// quota path stays uniform with the food extractor (8.1) and the
/// rest of the photo intake stack.
class IntakeIntentRouter {
  IntakeIntentRouter({
    required LlmClient llm,
    required VisionGate gate,
    Duration timeout = const Duration(seconds: 8),
  })  : _llm = llm,
        _gate = gate,
        _timeout = timeout;

  final LlmClient _llm;
  final VisionGate _gate;
  final Duration _timeout;

  /// Resolves intake intent for a photo capture.
  ///
  /// If [explicitHint] is non-null, returns it immediately — the
  /// caller (typically the Phase 8.4 form-preview toggle) already
  /// resolved intent. Otherwise runs the soft-case classifier.
  ///
  /// [userCaption] is an optional owner-typed draft; threaded into
  /// the classifier as a steering text block.
  Future<IntakeIntent> resolve({
    required Uint8List imageBytes,
    String? userCaption,
    IntakeIntent? explicitHint,
    String mediaType = 'image/jpeg',
  }) async {
    if (explicitHint != null) return explicitHint;

    final decision = await _gate.check();
    if (!decision.isAllowed) return IntakeIntent.generalMemory;

    final userBlocks = <ContentBlock>[
      ImageBlock(
        bytes: imageBytes,
        mediaType: mediaType,
        // One-shot classification; the same image isn't referenced
        // on follow-up turns so prompt-cache eligibility is wasted
        // overhead (mirrors photo_extractor.dart:75).
        cacheControl: false,
      ),
      if (userCaption != null && userCaption.trim().isNotEmpty)
        TextBlock('Caption: ${userCaption.trim()}'),
      const TextBlock(_userInstruction),
    ];

    try {
      final response = await _llm.turn(
        systemPrompt: _systemPrompt,
        history: [Message(role: Message.userRole, content: userBlocks)],
      ).timeout(_timeout);
      return _parse(response.text.trim());
    } on TimeoutException {
      return IntakeIntent.generalMemory;
    } catch (_) {
      return IntakeIntent.generalMemory;
    }
  }

  IntakeIntent _parse(String text) {
    // The model may wrap JSON in code fences despite the prompt.
    // Strip a leading ```json / ``` and trailing ``` (matches the
    // photo extractor's tolerance — see photo_extractor.dart:99).
    var json = text.trim();
    if (json.startsWith('```')) {
      json = json.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      if (json.endsWith('```')) {
        json = json.substring(0, json.length - 3).trim();
      }
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return IntakeIntent.generalMemory;
    }
    if (decoded is! Map<String, Object?>) return IntakeIntent.generalMemory;
    return IntakeIntent.fromIdOrFallback(decoded['intent'] as String?);
  }
}

/// Locked schema per DECISIONS row 104. Flat enum, lens-extensible —
/// future lenses add cases (e.g. `logGroomingAfter`) without
/// restructuring. `generalMemory` is the always-safe fallback when
/// the classifier drifts or fails.
enum IntakeIntent {
  /// Photo of a meal that was served or eaten (bowl with food, a
  /// treat being given, the pet eating). Routes to the food lens
  /// in log mode.
  logMealAfter,

  /// Photo of a food item the owner is considering — uncooked
  /// food, food on a counter, "can my pet have this?". Routes to
  /// the food lens in pre-feeding mode (hazard check + optional
  /// schedule).
  checkMealBefore,

  /// Not a meal. Generic memory — the existing photo extractor
  /// flow handles it. Also the always-safe fallback when
  /// classification fails or returns an unknown value.
  generalMemory;

  /// Drift-tolerant parsing — unknown string → safe fallback to
  /// [generalMemory] (mirrors PhotoSetting.fromIdOrOther in
  /// photo_extractor.dart:167).
  static IntakeIntent fromIdOrFallback(String? id) {
    for (final i in values) {
      if (i.name == id) return i;
    }
    return IntakeIntent.generalMemory;
  }
}

/// System prompt locked per DECISIONS row 104. Three-class
/// classifier with conservative bias rules ("when unsure, prefer
/// the safer-for-the-user fallback") so soft cases degrade
/// gracefully.
const _systemPrompt = '''
You classify a pet-owner photo's intent for the PetPal app.

Given a photo (and optional user-typed caption), return one of
three intents:

- "logMealAfter": the photo shows a meal that was just served or
  eaten (a bowl with food, a treat being given, the pet eating).
- "checkMealBefore": the photo shows a food item the owner is
  considering feeding — uncooked food, food on a counter, a
  question about whether the pet can have this. The owner has NOT
  fed the pet yet.
- "generalMemory": the photo is not a meal at all (the pet, an
  environment, an object, a vet visit, etc.).

Be conservative:
- When unsure between checkMealBefore and logMealAfter, choose
  logMealAfter.
- When unsure between any meal intent and generalMemory, choose
  generalMemory.

Respond with ONLY a JSON object: {"intent": "<one of the three>"}.
No prose, no markdown, no code fences.
''';

const _userInstruction =
    'Classify the photo intent as JSON per the system prompt. '
    'Single object, no surrounding prose.';

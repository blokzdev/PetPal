import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../agent/llm_client.dart';
import '../agent/messages.dart';
import 'vision_gate.dart';

/// Phase 6 task 6.5 — photo extractor utility. NOT a registered
/// agent tool — the camera-as-memory flow doesn't need agent
/// reasoning, the form preview wants typed data. A direct utility
/// that takes image bytes, calls Sonnet through the LLM client +
/// ImageBlock from 6.4, and returns a structured [PhotoExtraction].
///
/// Schema locked at DECISIONS row 41:
/// - `setting` enum: home / outdoors / vet / grooming / car / other
/// - `activity` enum: resting / playing / eating / grooming / walking
///   / exam / other
/// - `demeanor` optional hedged string ("looks relaxed", "appears
///   curious") — NEVER a confident emotional claim
/// - `notable_objects: List<String>` — visible objects only; no
///   invented props
/// - `freeform_caption: String` — natural-language one-liner
/// - `enrichment_hints: List<String>` — 1–2 optional follow-up
///   question strings the form-preview surfaces as additional
///   editable rows
///
/// Constraints encoded in the system prompt:
/// - **No diagnosis** (mirrors the 6.9 chat constraint + DECISIONS
///   row 25 medical-vision lockout).
/// - **Hedge demeanor** — phrasings like "looks ...", "appears ..."
///   only.
/// - **Don't invent objects** — only list what's visible.
///
/// **Timeout:** 15s. The 6.6 form-preview save flow uses this as
/// the cutoff before falling back to a bare freeform caption.
/// **Failure mode:** returns null on timeout, gate-block, parse
/// failure, or transport error — extraction is best-effort, the
/// save-path never blocks.
class PhotoExtractor {
  PhotoExtractor({
    required LlmClient llm,
    required VisionGate gate,
    Duration timeout = const Duration(seconds: 15),
  })  : _llm = llm,
        _gate = gate,
        _timeout = timeout;

  final LlmClient _llm;
  final VisionGate _gate;
  final Duration _timeout;

  /// Extract structured fields from [imageBytes]. Returns null on
  /// any failure (gate-block, timeout, transport error, parse
  /// failure) — the caller falls back to a bare freeform caption.
  ///
  /// [userHint] is an optional user-typed caption draft. When
  /// present, the model uses it as a steering signal but is free
  /// to refine / replace.
  Future<PhotoExtraction?> extract({
    required Uint8List imageBytes,
    String? userHint,
    String mediaType = 'image/jpeg',
  }) async {
    final decision = await _gate.check();
    if (!decision.isAllowed) return null;

    final userBlocks = <ContentBlock>[
      ImageBlock(
        bytes: imageBytes,
        mediaType: mediaType,
        // One-shot extraction; the same image isn't referenced on
        // a follow-up turn so prompt-cache eligibility is wasted
        // overhead.
        cacheControl: false,
      ),
      if (userHint != null && userHint.trim().isNotEmpty)
        TextBlock("The owner's caption draft: ${userHint.trim()}"),
      const TextBlock(_userInstruction),
    ];

    try {
      final response = await _llm.turn(
        systemPrompt: _systemPrompt,
        history: [Message(role: Message.userRole, content: userBlocks)],
      ).timeout(_timeout);
      final text = response.text.trim();
      return _parse(text);
    } on TimeoutException {
      return null;
    } catch (_) {
      // Transport error, decode failure, or anything else — the
      // caller falls back to bare freeform caption.
      return null;
    }
  }

  PhotoExtraction? _parse(String text) {
    // The model may wrap JSON in code fences despite the prompt.
    // Strip a leading ```json / ``` and trailing ``` if present.
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
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    return PhotoExtraction.fromJson(decoded);
  }

  /// Phase 8 task 8.1 — food-mode extraction. Sibling method to
  /// [extract], same class per the ROADMAP "keep one entry point"
  /// directive + DECISIONS row 105 (single-class, dual-method).
  /// Shares the constructor's [LlmClient], [VisionGate], and
  /// timeout posture; differs only in system prompt + return
  /// shape ([FoodExtraction]).
  ///
  /// Schema locked at DECISIONS row 105 (subset of row 99):
  /// - `food_type` (string, hedged) — "looks like dry kibble"
  /// - `identified_items: List<String>` — plain English names
  ///   (the input to Phase 8.3's `FoodHazardScreener`)
  /// - `portion_estimate` (string, hedged, optional)
  /// - `prep_notes` (string, optional) — "looks raw"
  /// - `freeform_caption` (string) — always-present fallback
  ///
  /// `meal_phase` + `fed_at` from row 99 are NOT extractor output
  /// — those are writer-level (Phase 8.2) derived from
  /// `IntakeIntent` + form clock.
  ///
  /// Constraints encoded in the system prompt:
  /// - **No nutritional claims** (extension of row 25 no-diagnosis
  ///   posture into the food domain).
  /// - **Hedge food identification** — "looks like ...", "appears
  ///   to be ..." only.
  /// - **Don't invent items** — only list what's visible.
  /// - **Hedge portions** — never exact gram weights.
  /// - **Plain English names** — `chicken`, `chocolate`, `onion` —
  ///   matches the hazard YAML's keyword vocabulary so the screener
  ///   can fire on the extraction (row 105 cross-cutting protection).
  ///
  /// **Timeout:** 15s (same as [extract]). **Failure mode:** returns
  /// null on timeout, gate-block, parse failure, or transport error
  /// — extraction is best-effort, the save-path never blocks.
  /// **Empty JSON `{}`** is a successful extraction with empty
  /// values (writer still has the freeform-caption fallback);
  /// distinct from null which means the LLM pass itself failed.
  Future<FoodExtraction?> extractFood({
    required Uint8List imageBytes,
    String? userHint,
    String mediaType = 'image/jpeg',
  }) async {
    final decision = await _gate.check();
    if (!decision.isAllowed) return null;

    final userBlocks = <ContentBlock>[
      ImageBlock(
        bytes: imageBytes,
        mediaType: mediaType,
        // One-shot extraction; mirrors extract()'s cache posture.
        cacheControl: false,
      ),
      if (userHint != null && userHint.trim().isNotEmpty)
        TextBlock("The owner's caption draft: ${userHint.trim()}"),
      const TextBlock(_foodUserInstruction),
    ];

    try {
      final response = await _llm.turn(
        systemPrompt: _foodSystemPrompt,
        history: [Message(role: Message.userRole, content: userBlocks)],
      ).timeout(_timeout);
      final text = response.text.trim();
      return _parseFood(text);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  FoodExtraction? _parseFood(String text) {
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
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    return FoodExtraction.fromJson(decoded);
  }
}

/// System prompt locked at DECISIONS row 41.
const _systemPrompt = '''
You are PetPal's photo describer. The user just saved a photo of
their pet to their journal; your job is to look at the photo and
produce a structured JSON description that the form-preview
screen will render as editable fields.

CRITICAL RULES:
1. Never diagnose. You are not a vet. Do not interpret medical
   conditions, injuries, body condition, or breed/species. Stay
   on observable behavior and visible context.
2. Hedge demeanor. Use phrasings like "looks relaxed", "appears
   curious", "seems alert" — NEVER confident emotional claims
   ("is happy", "is sad"). If the photo doesn't support a clear
   demeanor read, leave the field empty.
3. Don't invent objects. List only what's clearly visible in
   notable_objects. No "probably" or "might be a ...".

Respond with a single JSON object matching this shape, and
nothing else (no prose, no markdown, no code fences):

{
  "setting": "home" | "outdoors" | "vet" | "grooming" | "car" | "other",
  "activity": "resting" | "playing" | "eating" | "grooming" | "walking" | "exam" | "other",
  "demeanor": "looks relaxed" | "" (optional hedged string),
  "notable_objects": ["leash", "frozen carrot"],
  "freeform_caption": "a one-line natural-language description",
  "enrichment_hints": ["a follow-up question the owner might want to add"]
}

If you can't determine a field, use "other" for the enum slots,
empty string for demeanor, and empty arrays for the lists. The
form-preview will render only the populated fields.
''';

const _userInstruction =
    'Describe the photo as JSON per the system prompt. Single object, '
    'no surrounding prose.';

/// Locked schema per DECISIONS row 41.
enum PhotoSetting {
  home,
  outdoors,
  vet,
  grooming,
  car,
  other;

  static PhotoSetting fromIdOrOther(String? id) {
    for (final s in values) {
      if (s.name == id) return s;
    }
    return PhotoSetting.other;
  }
}

enum PhotoActivity {
  resting,
  playing,
  eating,
  grooming,
  walking,
  exam,
  other;

  static PhotoActivity fromIdOrOther(String? id) {
    for (final a in values) {
      if (a.name == id) return a;
    }
    return PhotoActivity.other;
  }
}

class PhotoExtraction {
  const PhotoExtraction({
    required this.setting,
    required this.activity,
    required this.demeanor,
    required this.notableObjects,
    required this.freeformCaption,
    required this.enrichmentHints,
  });

  factory PhotoExtraction.fromJson(Map<String, Object?> json) {
    final demeanorRaw = json['demeanor'];
    final demeanor =
        (demeanorRaw is String && demeanorRaw.trim().isNotEmpty)
            ? demeanorRaw.trim()
            : null;
    return PhotoExtraction(
      setting: PhotoSetting.fromIdOrOther(json['setting'] as String?),
      activity: PhotoActivity.fromIdOrOther(json['activity'] as String?),
      demeanor: demeanor,
      notableObjects: _stringList(json['notable_objects']),
      freeformCaption: (json['freeform_caption'] as String?)?.trim() ?? '',
      enrichmentHints: _stringList(json['enrichment_hints']),
    );
  }

  final PhotoSetting setting;
  final PhotoActivity activity;
  final String? demeanor;
  final List<String> notableObjects;
  final String freeformCaption;
  final List<String> enrichmentHints;

  /// Render the extraction back into the additive frontmatter keys
  /// for `_composePhotoSidecar` / `mergeFrontmatter` callers.
  /// Defaults / empty values are dropped so the sidecar stays
  /// minimal — the 6.3 photo entry view + the renderTemplate
  /// strip-empty pass both read absent fields as "unset".
  Map<String, Object?> toFrontmatterPatch() {
    return <String, Object?>{
      if (setting != PhotoSetting.other) 'setting': setting.name,
      if (activity != PhotoActivity.other) 'activity': activity.name,
      if (demeanor != null) 'demeanor': demeanor,
      if (notableObjects.isNotEmpty) 'notable_objects': notableObjects,
      if (enrichmentHints.isNotEmpty) 'enrichment_hints': enrichmentHints,
    };
  }
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return [for (final e in raw) if (e is String && e.trim().isNotEmpty) e.trim()];
}

/// Phase 8 task 8.1 — food-mode system prompt locked at DECISIONS
/// row 105. Hedged-language wall (rules 1–4) is the row 25
/// no-diagnosis posture extended into the food domain. Rule 5 is
/// the cross-cutting protection between this extractor and Phase
/// 8.3's `FoodHazardScreener` — the screener matches plain English
/// keyword names against `assets/hazards/food_toxins.yaml`; an
/// extraction of "fowl" would miss the chicken pattern, an
/// extraction of "Theobroma cacao" would miss chocolate.
const _foodSystemPrompt = '''
You are PetPal's food describer. The user just photographed food
they're about to give their pet, or just gave. Your job is to look
at the photo and produce a structured JSON description of what's
IN the photo.

CRITICAL RULES:
1. Never make nutritional claims. You are not a nutritionist or a
   vet. Do not opine on whether food is healthy, balanced,
   appropriate, safe to feed, the right portion, or contains
   specific nutrients. Stay on observable items and visible
   preparation only.
2. Hedge language. Use phrasings like "looks like kibble",
   "appears to be chicken", "what may be a small carrot piece" —
   NEVER confident food-identification claims ("this is X", "the
   pet should/shouldn't eat ...").
3. Don't invent items. List only what's clearly visible in
   identified_items. No "probably" or "might also contain ...".
4. Hedge portions. Use phrasings like "appears to be about a half
   cup" — never exact gram weights. Leave portion_estimate empty
   if you can't see enough to estimate.
5. Use plain English names for identified_items (chicken, onion,
   chocolate, grape, carrot) — common names a pet owner would
   recognize, not Latin or scientific names. This is the input to
   the hazard screener.

Respond with a single JSON object matching this shape, and
nothing else (no prose, no markdown, no code fences):

{
  "food_type": "looks like dry kibble" or "",
  "identified_items": ["chicken", "carrot piece"],
  "portion_estimate": "appears to be about a half cup" or "",
  "prep_notes": "looks raw" or "",
  "freeform_caption": "one-line natural-language description"
}

If you can't determine a field, use empty string or empty list.
freeform_caption should always be populated as a fallback.
''';

const _foodUserInstruction =
    'Describe the food in the photo as JSON per the system prompt. '
    'Single object, no surrounding prose.';

/// Locked schema per DECISIONS row 105. Strict subset of row 99's
/// stored frontmatter — `meal_phase` + `fed_at` are writer-level
/// (Phase 8.2) concerns and are not produced by the extractor.
///
/// All optional fields are empty-string-or-empty-list, not
/// nullable, mirroring [PhotoExtraction]'s drop-empty posture so
/// [toFrontmatterPatch] composes a minimal patch the 8.2 writer
/// merges into the final frontmatter.
class FoodExtraction {
  const FoodExtraction({
    required this.foodType,
    required this.identifiedItems,
    required this.portionEstimate,
    required this.prepNotes,
    required this.freeformCaption,
  });

  factory FoodExtraction.fromJson(Map<String, Object?> json) {
    return FoodExtraction(
      foodType: (json['food_type'] as String?)?.trim() ?? '',
      identifiedItems: _stringList(json['identified_items']),
      portionEstimate: (json['portion_estimate'] as String?)?.trim() ?? '',
      prepNotes: (json['prep_notes'] as String?)?.trim() ?? '',
      freeformCaption: (json['freeform_caption'] as String?)?.trim() ?? '',
    );
  }

  /// Hedged food-type description ('looks like dry kibble').
  /// Empty string when the model can't determine.
  final String foodType;

  /// Plain English food item names ('chicken', 'chocolate',
  /// 'onion'). The vocabulary the 8.3 hazard screener matches
  /// against. Always non-null; may be empty.
  final List<String> identifiedItems;

  /// Hedged portion estimate ('appears to be about a half cup').
  /// Empty string when the model can't see enough to estimate.
  final String portionEstimate;

  /// Visible preparation notes ('looks raw', 'appears cooked').
  /// Empty string when not applicable / determinable.
  final String prepNotes;

  /// Always-present one-line natural-language description. The
  /// writer falls back to this when other fields are empty.
  final String freeformCaption;

  /// Render the extraction into the additive frontmatter keys the
  /// 8.2 `WikiRepo.writeFoodEntry` writer merges. Empty values are
  /// dropped so the sidecar stays minimal (matches
  /// [PhotoExtraction.toFrontmatterPatch]). `freeform_caption` is
  /// not in the patch — it lands in the entry body, same posture as
  /// PhotoExtraction.
  Map<String, Object?> toFrontmatterPatch() {
    return <String, Object?>{
      if (foodType.isNotEmpty) 'food_type': foodType,
      if (identifiedItems.isNotEmpty) 'items': identifiedItems,
      if (portionEstimate.isNotEmpty) 'portion': portionEstimate,
      if (prepNotes.isNotEmpty) 'prep_notes': prepNotes,
    };
  }
}

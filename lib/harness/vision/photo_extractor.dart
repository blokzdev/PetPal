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

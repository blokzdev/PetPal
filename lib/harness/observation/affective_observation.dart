/// Phase 6 task 6.8 — affective observation data class.
///
/// An "affective observation" is a single warm, optional sentence
/// PetPal surfaces after a photo memory is saved, citing a prior
/// memory the photo evoked ("looks more relaxed than at the vet visit
/// last month"). DECISIONS row 41 (b) locks the v1 contract:
///
///   - **Memory-grounded only** in v1. The model MUST cite a prior
///     memory; ungrounded observations are dropped client-side.
///   - **`confidence: high`** required. Anything else is dropped.
///   - **Frequency cap** of one observation per five saves, tracked
///     in SettingsStorage (the `affective_count_at_last_fire_<petId>`
///     int counter).
///
/// Bare ungrounded observations defer to v1.2; the cuttable scope
/// shape is the whole layer behind a feature flag.
class AffectiveObservation {
  const AffectiveObservation({
    required this.text,
    required this.groundingRef,
  });

  /// The observation sentence itself. Warm, hedged ("looks more
  /// relaxed", "seems livelier than"), one or two sentences max.
  /// VOICE.md §2 register applies — never diagnose, never project.
  final String text;

  /// The prior memory the observation cites — typically a short
  /// reference like "the vet visit last month" or "Loki at the
  /// trailhead on April 12th". Drawn from the model's grounding
  /// claim; persisted alongside the text so the entry view + the
  /// home-screen card can show the link if the user wants to tap
  /// through.
  final String groundingRef;

  Map<String, Object?> toJson() => {
        'text': text,
        'grounding_ref': groundingRef,
      };

  static AffectiveObservation? fromJson(Map<String, Object?> json) {
    final text = json['text'];
    final ref = json['grounding_ref'];
    if (text is! String || text.trim().isEmpty) return null;
    if (ref is! String || ref.trim().isEmpty) return null;
    return AffectiveObservation(
      text: text.trim(),
      groundingRef: ref.trim(),
    );
  }
}

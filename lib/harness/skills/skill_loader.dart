import 'skill_source.dart';

/// One fragment produced by [SkillLoader.match]. Identifies the skill it
/// came from + the filename so the caller (SessionBuilder in 3.3) can
/// attribute and de-duplicate, and carries the raw text the loader read
/// off the source.
class MatchedFragment {
  const MatchedFragment({
    required this.skillId,
    required this.filename,
    required this.text,
  });
  final String skillId;
  final String filename;
  final String text;
}

/// Selects and loads skill fragments to inject into the next agent turn.
///
/// Three-stage filter, in order — CLAUDE.md §9 + Phase 7 task C.3:
/// 1. **Category filter** (the only category-aware code path in the
///    harness per CLAUDE.md §3). Skills whose `category:` list doesn't
///    include the active pet's category are dropped. An empty/omitted
///    list = "any".
/// 2. **Entitlement gate** (Phase 7 task C.3). Skills with
///    `requires_pro: true` are dropped unless EITHER the active
///    entitlement is Pro OR the user has purchased the care pack
///    that unlocks the skill (skill ID is in [ownedCarePackSkillIds]).
///    Both gates collapse to "always allowed" when neither requirement
///    applies — pre-Phase-7 behavior on every shipped skill that
///    keeps `requires_pro: false`.
/// 3. **Trigger match.** At least one of the skill's `triggers:` must
///    appear (case-insensitively) as a substring of the user input.
///
/// When a skill survives all three filters, every fragment in its
/// `loads:` is read and emitted, in declaration order. Skills that
/// don't survive contribute nothing — "never the whole skill catalog"
/// (CLAUDE.md §9).
class SkillLoader {
  SkillLoader({
    required SkillSource source,
    this.isPro = false,
    this.ownedCarePackSkillIds = const <String>{},
  }) : _source = source;

  final SkillSource _source;

  /// True when the active user has a Pro subscription. Pro implicitly
  /// unlocks every `requires_pro` skill regardless of care pack
  /// ownership. Defaults to false; the provider wires the active
  /// entitlement state per session.
  final bool isPro;

  /// Skill IDs the user has unlocked via standalone care pack
  /// purchases (Phase 7 task C.3). Free + BYOK users can buy
  /// individual care packs; Pro users get the full set without
  /// needing this field. Defaults to empty.
  final Set<String> ownedCarePackSkillIds;

  Future<List<MatchedFragment>> match({
    required String petCategory,
    required String userInput,
  }) async {
    final input = userInput.toLowerCase();
    final entries = await _source.list();
    final out = <MatchedFragment>[];
    for (final entry in entries) {
      final manifest = entry.manifest;
      if (!manifest.matchesCategory(petCategory)) continue;
      if (manifest.requiresPro &&
          !isPro &&
          !ownedCarePackSkillIds.contains(manifest.id)) {
        continue;
      }
      final triggerHit = manifest.triggers.any(
        (t) => input.contains(t.toLowerCase()),
      );
      if (!triggerHit) continue;
      for (final filename in manifest.loads) {
        final text = await entry.readFragment(filename);
        out.add(MatchedFragment(
          skillId: manifest.id,
          filename: filename,
          text: text,
        ));
      }
    }
    return out;
  }
}

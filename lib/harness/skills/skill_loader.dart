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
/// Two-stage filter, in order — see CLAUDE.md §9:
/// 1. **Species filter** (the only species-aware code path in the harness
///    per CLAUDE.md §3). Skills whose `species:` list doesn't include the
///    active pet's species are dropped. An empty/omitted list = "any".
/// 2. **Trigger match.** At least one of the skill's `triggers:` must
///    appear (case-insensitively) as a substring of the user input.
///
/// When a skill survives both filters, every fragment in its `loads:` is
/// read and emitted, in declaration order. Skills that don't survive
/// contribute nothing — "never the whole skill catalog" (CLAUDE.md §9).
class SkillLoader {
  SkillLoader({required SkillSource source}) : _source = source;
  final SkillSource _source;

  Future<List<MatchedFragment>> match({
    required String petSpecies,
    required String userInput,
  }) async {
    final input = userInput.toLowerCase();
    final entries = await _source.list();
    final out = <MatchedFragment>[];
    for (final entry in entries) {
      final manifest = entry.manifest;
      if (!manifest.matchesSpecies(petSpecies)) continue;
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

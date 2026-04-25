import '../../data/soul_file.dart' show parseSoul;

/// Parsed skill manifest. Shape lives in CLAUDE.md §9. Skills are
/// directories under `assets/skills/<id>/` containing a root markdown
/// file with YAML frontmatter; the body of that root file is unused
/// (the loaded fragments live in sibling `.md` files listed in [loads]).
class SkillManifest {
  const SkillManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.species,
    required this.triggers,
    required this.loads,
    required this.requiresPro,
  });

  final String id;
  final String name;
  final int version;

  /// Species this skill applies to. **Empty list means "any species"** —
  /// the harness never silently filters out a skill that didn't declare a
  /// species list. Use an explicit `species: [dog]` in the manifest to
  /// gate by species.
  final List<String> species;

  final List<String> triggers;
  final List<String> loads;
  final bool requiresPro;

  /// Whether this skill is applicable to a pet of [petSpecies]. The
  /// harness's only species-aware code path (CLAUDE.md §3) — [SkillLoader]
  /// calls this before running trigger matching.
  bool matchesSpecies(String petSpecies) {
    if (species.isEmpty) return true;
    return species.contains(petSpecies);
  }
}

class SkillManifestException implements Exception {
  SkillManifestException(this.message);
  final String message;

  @override
  String toString() => 'SkillManifestException: $message';
}

/// Parse a skill manifest from a root file's text. The frontmatter
/// extraction is shared with `SOUL.md` (`parseSoul`) — same `--- yaml ---`
/// shape — but the body is intentionally discarded here. The body of a
/// skill's root file is **not** what gets loaded into the system prompt;
/// only the fragments enumerated in `loads:` are injected, and only when
/// their triggers match (see [SkillLoader] in 3.2).
SkillManifest parseSkillManifest(String text) {
  final fm = parseSoul(text).frontmatter;

  final id = fm['id'];
  if (id is! String || id.isEmpty) {
    throw SkillManifestException('manifest missing required `id`');
  }
  final name = fm['name'];
  if (name is! String || name.isEmpty) {
    throw SkillManifestException('manifest missing required `name`');
  }
  final version = fm['version'];
  if (version is! int) {
    throw SkillManifestException(
      'manifest `version` must be an integer (got ${version.runtimeType})',
    );
  }

  return SkillManifest(
    id: id,
    name: name,
    version: version,
    species: _stringList(fm['species']),
    triggers: _stringList(fm['triggers']),
    loads: _stringList(fm['loads']),
    requiresPro: fm['requires_pro'] == true,
  );
}

List<String> _stringList(Object? raw) {
  if (raw is List) return raw.map((e) => e.toString()).toList();
  return const [];
}

import 'skill_manifest.dart';

/// Abstract over where skills come from. The production loader reads
/// from Flutter assets (Phase 3.5 ships bundled skills); tests use an
/// in-memory fake. Keeping this abstract lets the loader logic in
/// [SkillLoader] stay platform-free.
abstract class SkillSource {
  /// Every skill currently visible to the loader, with a lazy fragment
  /// reader bound to that skill's directory.
  Future<List<SkillSourceEntry>> list();
}

class SkillSourceEntry {
  const SkillSourceEntry({
    required this.manifest,
    required this.readFragment,
  });

  final SkillManifest manifest;

  /// Reads one fragment by its filename (as it appears in
  /// `manifest.loads`). The skill's directory is bound at construction;
  /// this function only takes the basename.
  final Future<String> Function(String filename) readFragment;
}

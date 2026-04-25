import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import 'skill_manifest.dart';
import 'skill_source.dart';

/// Production [SkillSource] that discovers skills via the Flutter
/// `AssetManifest`. Every directory under `assets/skills/<id>/` that
/// contains a `manifest.md` is a skill; the loader reads that manifest
/// for shape and lazily reads sibling fragment files when the
/// [SkillLoader] decides the skill is relevant.
///
/// The set of bundled skills is fixed at app build time (declared in
/// `pubspec.yaml`). User-installed skills (loading from the filesystem)
/// is a future feature; for now, the source is read-only.
class AssetSkillSource implements SkillSource {
  const AssetSkillSource();

  static const _root = 'assets/skills/';
  static const _manifestFilename = 'manifest.md';

  @override
  Future<List<SkillSourceEntry>> list() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final manifestPaths = manifest
        .listAssets()
        .where((p) => p.startsWith(_root) && p.endsWith('/$_manifestFilename'))
        .toList();

    final out = <SkillSourceEntry>[];
    for (final manifestPath in manifestPaths) {
      final raw = await rootBundle.loadString(manifestPath);
      final parsedManifest = parseSkillManifest(raw);
      final dir = manifestPath.substring(
        0,
        manifestPath.length - _manifestFilename.length - 1,
      );
      out.add(
        SkillSourceEntry(
          manifest: parsedManifest,
          readFragment: (filename) =>
              rootBundle.loadString('$dir/$filename'),
        ),
      );
    }
    return out;
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/skills/skill_manifest.dart';

/// Disk-level validation of the launch skill packs shipped under
/// `assets/skills/`. Catches manifest typos, missing `loads:` files,
/// and category values that don't appear in the supported set —
/// problems that would otherwise only surface at runtime on a real
/// device.
///
/// Tests deliberately read from disk (not via rootBundle): the assets
/// are committed in the repo and `flutter test` runs from the project
/// root.
void main() {
  final root = Directory(
    '${Directory.current.path}/assets/skills',
  );

  /// The set of category ids the harness recognises (from
  /// `lib/data/onboarding_templates.dart` `Category` enum). Kept as a
  /// literal here so this test fails loudly if a manifest declares a
  /// category we never seed.
  const knownCategory = {
    'dog',
    'cat',
    'bird',
    'rabbit',
    'reptile',
    'fish',
    'small-mammal',
    'exotic',
  };

  late List<Directory> skillDirs;

  setUpAll(() {
    skillDirs = root
        .listSync()
        .whereType<Directory>()
        .where(
          (d) => File('${d.path}/manifest.md').existsSync(),
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  });

  test('the three Phase 3.5 launch packs are present', () {
    final ids = skillDirs.map((d) => d.path.split('/').last).toSet();
    expect(ids, containsAll(<String>{'puppy', 'senior-dog', 'new-cat'}));
  });

  test('every shipped manifest parses cleanly', () {
    for (final dir in skillDirs) {
      final raw = File('${dir.path}/manifest.md').readAsStringSync();
      final manifest = parseSkillManifest(raw);
      expect(manifest.id, isNotEmpty,
          reason: '${dir.path}: id must be non-empty');
      expect(manifest.name, isNotEmpty,
          reason: '${dir.path}: name must be non-empty');
      expect(manifest.version, greaterThan(0),
          reason: '${dir.path}: version must be > 0');
    }
  });

  test('every category declared in a manifest is in the supported set',
      () {
    for (final dir in skillDirs) {
      final manifest = parseSkillManifest(
        File('${dir.path}/manifest.md').readAsStringSync(),
      );
      for (final s in manifest.category) {
        expect(
          knownCategory,
          contains(s),
          reason:
              'skill ${manifest.id} declares unknown category "$s"',
        );
      }
    }
  });

  test('every file in `loads:` exists alongside the manifest', () {
    for (final dir in skillDirs) {
      final manifest = parseSkillManifest(
        File('${dir.path}/manifest.md').readAsStringSync(),
      );
      for (final filename in manifest.loads) {
        final path = '${dir.path}/$filename';
        expect(
          File(path).existsSync(),
          isTrue,
          reason:
              'skill ${manifest.id} loads "$filename" but $path '
              'does not exist',
        );
      }
    }
  });

  test('every shipped manifest has at least one trigger and one fragment',
      () {
    for (final dir in skillDirs) {
      final manifest = parseSkillManifest(
        File('${dir.path}/manifest.md').readAsStringSync(),
      );
      expect(manifest.triggers, isNotEmpty,
          reason: '${manifest.id}: empty triggers means it never fires');
      expect(manifest.loads, isNotEmpty,
          reason: '${manifest.id}: empty loads means firing yields nothing');
    }
  });

  test('puppy skill is dog-only and has the canonical fragments', () {
    final puppyDir = skillDirs.firstWhere(
      (d) => d.path.endsWith('/puppy'),
    );
    final manifest = parseSkillManifest(
      File('${puppyDir.path}/manifest.md').readAsStringSync(),
    );
    expect(manifest.category, ['dog']);
    expect(manifest.loads, [
      'overview.md',
      'house-training.md',
      'socialization.md',
    ]);
    expect(manifest.matchesCategory('dog'), isTrue);
    expect(manifest.matchesCategory('cat'), isFalse);
  });

  test('new-cat skill is cat-only', () {
    final newCatDir = skillDirs.firstWhere(
      (d) => d.path.endsWith('/new-cat'),
    );
    final manifest = parseSkillManifest(
      File('${newCatDir.path}/manifest.md').readAsStringSync(),
    );
    expect(manifest.category, ['cat']);
    expect(manifest.matchesCategory('cat'), isTrue);
    expect(manifest.matchesCategory('dog'), isFalse);
  });
}

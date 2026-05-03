import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/skills/skill_manifest.dart';

/// Task 5.14 — three new bundled skill packs:
/// `reactive-dog` (dog), `senior-cat` (cat), `multi-cat` (cat).
///
/// AssetSkillSource discovers packs at runtime via the Flutter
/// AssetManifest, so a typo in `pubspec.yaml` or a missing
/// `loads:` file shows up only on a real launch (or by user
/// reports). This test reads each pack from the local filesystem
/// (where `flutter test` runs from the project root) and asserts
/// the manifests parse, the category filter is set as the roadmap
/// requires, and every fragment listed in `loads:` actually
/// exists on disk.
///
/// If a future task adds a pack without registering it here, the
/// per-pack expectation is one line; the cost is intentionally
/// low so there's no excuse to skip it.
void main() {
  final packsDir = Directory('assets/skills');

  group('bundled skill packs', () {
    test('all packs parse + their loads files all exist', () {
      final packDirs = packsDir
          .listSync()
          .whereType<Directory>()
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      // At least the three new packs plus the three pre-5.14 ones.
      expect(packDirs.length, greaterThanOrEqualTo(6),
          reason: 'expected six or more bundled packs after 5.14');

      for (final dir in packDirs) {
        final manifestFile = File('${dir.path}/manifest.md');
        expect(manifestFile.existsSync(), isTrue,
            reason: '${dir.path}: missing manifest.md');

        final raw = manifestFile.readAsStringSync();
        final manifest = parseSkillManifest(raw);

        expect(manifest.id, isNotEmpty,
            reason: '${dir.path}: manifest id must be non-empty');
        expect(manifest.triggers, isNotEmpty,
            reason: '${manifest.id}: needs at least one trigger');
        expect(manifest.loads, isNotEmpty,
            reason: '${manifest.id}: needs at least one fragment '
                'in `loads:`');

        for (final fragment in manifest.loads) {
          final fragmentFile = File('${dir.path}/$fragment');
          expect(fragmentFile.existsSync(), isTrue,
              reason: '${manifest.id}: missing fragment file '
                  '"$fragment" listed in loads:');
        }
      }
    });

    test('reactive-dog targets dogs only', () {
      final raw = File('assets/skills/reactive-dog/manifest.md')
          .readAsStringSync();
      final manifest = parseSkillManifest(raw);
      expect(manifest.id, 'reactive-dog');
      expect(manifest.category, ['dog']);
      // Trigger sanity — reactivity vocabulary the user is likely
      // to type. The exact list will evolve; pin only the must-haves.
      expect(manifest.triggers, contains('reactive'));
      expect(manifest.triggers, contains('lunging'));
    });

    test('senior-cat targets cats only', () {
      final raw = File('assets/skills/senior-cat/manifest.md')
          .readAsStringSync();
      final manifest = parseSkillManifest(raw);
      expect(manifest.id, 'senior-cat');
      expect(manifest.category, ['cat']);
      expect(manifest.triggers, contains('senior cat'));
      // Symptom-based triggers (kidney, hyperthyroidism, weight
      // loss) — these are the phrases owners actually type when
      // worried, and the pack's red-flags fragment depends on
      // catching them.
      expect(manifest.triggers, contains('kidney'));
      expect(manifest.triggers, contains('weight loss'));
    });

    test('multi-cat targets cats only', () {
      final raw = File('assets/skills/multi-cat/manifest.md')
          .readAsStringSync();
      final manifest = parseSkillManifest(raw);
      expect(manifest.id, 'multi-cat');
      expect(manifest.category, ['cat']);
      expect(manifest.triggers, contains('introducing'));
      expect(manifest.triggers, contains('fighting'));
    });

    test('cat-track 5.14 packs (senior-cat, multi-cat) stay free-tier', () {
      // Phase 7 task C.3 flipped reactive-dog to requires_pro: true
      // (the v1 starter care pack — care_pack_reactive_dog at $2.99,
      // unlocks the reactive-dog skill ID). senior-cat + multi-cat
      // stay free pending the cat-track care pack registration in
      // v1.x.
      for (final id in const ['senior-cat', 'multi-cat']) {
        final raw =
            File('assets/skills/$id/manifest.md').readAsStringSync();
        final manifest = parseSkillManifest(raw);
        expect(manifest.requiresPro, isFalse,
            reason: '$id stays free pending v1.x cat-track care pack');
      }
    });

    test('reactive-dog ships as Pro-gated (Phase 7 task C.3 — '
        'unlocked by care_pack_reactive_dog IAP or any Pro tier)', () {
      final raw =
          File('assets/skills/reactive-dog/manifest.md').readAsStringSync();
      final manifest = parseSkillManifest(raw);
      expect(manifest.requiresPro, isTrue,
          reason: 'reactive-dog is the v1 starter care pack '
              '(ProductIds.carePackReactiveDog → reactive-dog skill ID)');
    });
  });
}

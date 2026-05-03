import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/account/local_data_wipe.dart';
import 'package:petpal/data/wiki_io.dart';

/// Phase 7 task H.1.d.wipe — local data wipe service tests.

class _RecordingWiki implements WikiIo {
  int deleteAllCalls = 0;
  Object? scriptedError;

  @override
  String petDir(int petId) => 'wiki/$petId';
  @override
  String soulPath(int petId) => 'wiki/$petId/SOUL.md';
  @override
  Future<void> writeAtomic(String relPath, String body) async {}
  @override
  Future<String> read(String relPath) async => '';
  @override
  Future<List<String>> listForPet(int petId) async => const [];
  @override
  Future<void> writeBytesAtomic(String relPath, Uint8List bytes) async {}
  @override
  Future<Uint8List> readBytes(String relPath) async => Uint8List(0);
  @override
  Future<void> deleteIfExists(String relPath) async {}
  @override
  Future<int> bytesForPet(int petId) async => 0;

  @override
  Future<void> deleteAll() async {
    deleteAllCalls++;
    final err = scriptedError;
    if (err != null) {
      scriptedError = null;
      throw err;
    }
  }
}

void main() {
  group('LocalDataWipe.wipe', () {
    test('happy path — deleteAll fires + drift file deleted + invalidations '
        'fire in order', () async {
      final wiki = _RecordingWiki();
      var driftDeleted = 0;
      final order = <String>[];

      final wipe = LocalDataWipe(
        deleteDriftFile: () async {
          driftDeleted++;
          order.add('drift');
        },
      );
      await wipe.wipe(
        wikiIo: wiki,
        invalidateDatabase: () => order.add('inv_db'),
        invalidateWikiIo: () => order.add('inv_wiki'),
      );

      expect(wiki.deleteAllCalls, 1);
      expect(driftDeleted, 1);
      // Sequence-of-operations invariant per DECISIONS row 90.
      expect(order, ['inv_db', 'drift', 'inv_wiki']);
    });

    test('wiki delete failure → reported but does not block subsequent '
        'steps', () async {
      final wiki = _RecordingWiki();
      wiki.scriptedError = StateError('disk full');
      final errors = <String>[];
      var driftDeleted = 0;
      var invalidateWikiCalled = false;

      final wipe = LocalDataWipe(
        deleteDriftFile: () async {
          driftDeleted++;
        },
        onError: (stage, e) => errors.add('$stage:$e'),
      );

      await wipe.wipe(
        wikiIo: wiki,
        invalidateDatabase: () {},
        invalidateWikiIo: () {
          invalidateWikiCalled = true;
        },
      );

      expect(errors, hasLength(1));
      expect(errors.first, startsWith('wiki_files:'));
      expect(driftDeleted, 1, reason: 'drift step must still run');
      expect(invalidateWikiCalled, isTrue,
          reason: 'invalidate step must still run');
    });

    test('drift delete failure → reported but does not block invalidation',
        () async {
      final wiki = _RecordingWiki();
      final errors = <String>[];
      var invalidateWikiCalled = false;

      final wipe = LocalDataWipe(
        deleteDriftFile: () async {
          throw const FileSystemException('cannot delete');
        },
        onError: (stage, e) => errors.add('$stage:$e'),
      );
      await wipe.wipe(
        wikiIo: wiki,
        invalidateDatabase: () {},
        invalidateWikiIo: () {
          invalidateWikiCalled = true;
        },
      );

      expect(errors, hasLength(1));
      expect(errors.first, startsWith('drift_file:'));
      expect(wiki.deleteAllCalls, 1);
      expect(invalidateWikiCalled, isTrue);
    });

    test('invalidate failure is reported but does not throw', () async {
      final wiki = _RecordingWiki();
      final errors = <String>[];

      final wipe = LocalDataWipe(
        deleteDriftFile: () async {},
        onError: (stage, e) => errors.add('$stage:$e'),
      );
      // wipe() should never throw — the final-stage error is captured
      // via onError.
      await wipe.wipe(
        wikiIo: wiki,
        invalidateDatabase: () {},
        invalidateWikiIo: () {
          throw StateError('riverpod kaboom');
        },
      );

      expect(errors, hasLength(1));
      expect(errors.first, startsWith('invalidate_providers:'));
    });

    test('all three steps fail — all errors reported, wipe still completes',
        () async {
      final wiki = _RecordingWiki();
      wiki.scriptedError = StateError('w');
      final errors = <String>[];

      final wipe = LocalDataWipe(
        deleteDriftFile: () async => throw StateError('d'),
        onError: (stage, e) => errors.add(stage),
      );
      await wipe.wipe(
        wikiIo: wiki,
        invalidateDatabase: () {},
        invalidateWikiIo: () => throw StateError('i'),
      );

      expect(errors, ['wiki_files', 'drift_file', 'invalidate_providers']);
    });
  });
}

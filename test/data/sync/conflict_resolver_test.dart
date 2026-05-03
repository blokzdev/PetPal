import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/sync/conflict_resolver.dart';

/// Phase 7 task G.3 — conflict resolver unit tests.
///
/// Pins DECISIONS row 72's locked rules:
///   - Pure LWW outside the 5s skew window.
///   - Within 5s: structural changes → conflict file, body-only
///     edits → LWW with deterministic tiebreak.
///   - Identical bodies → no-op regardless of ts.
///   - Local with no recorded ts + diverged body → defensive
///     conflict file (preserves the user's edit).
///   - Determinism across devices: both sides of the same conflict
///     produce the same survivor + same loser bytes.
void main() {
  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  ConflictParticipant local(String body, {DateTime? ts}) =>
      ConflictParticipant(bytes: bytes(body), writeTs: ts);
  ConflictParticipant remote(String body, {required DateTime ts}) =>
      ConflictParticipant(bytes: bytes(body), writeTs: ts);

  group('LWW outside the 5s skew window', () {
    test('remote ts > local + 5s → KeepRemote', () {
      final r = const ConflictResolver().resolve(
        local: local('local body', ts: DateTime.utc(2026, 5, 1, 10, 0, 0)),
        remote: remote('remote body', ts: DateTime.utc(2026, 5, 1, 10, 0, 6)),
      );
      expect(r, isA<KeepRemote>());
      expect((r as KeepRemote).bytes, equals(bytes('remote body')));
    });

    test('local ts > remote + 5s → KeepLocal', () {
      final r = const ConflictResolver().resolve(
        local: local('local body', ts: DateTime.utc(2026, 5, 1, 10, 0, 6)),
        remote: remote('remote body', ts: DateTime.utc(2026, 5, 1, 10, 0, 0)),
      );
      expect(r, isA<KeepLocal>());
    });
  });

  group('within 5s skew window — structural divergence emits conflict',
      () {
    test('different frontmatter keys → WriteWithConflict (later '
        'survives, earlier becomes .conflict.md)', () {
      final localBody = '---\nweight_kg: 14.2\n---\n\nbody';
      final remoteBody = '---\nweight_kg: 14.2\nallergies: [chicken]\n---\n\nbody';
      final r = const ConflictResolver().resolve(
        local: local(localBody, ts: DateTime.utc(2026, 5, 1, 10, 0, 0)),
        remote: remote(remoteBody, ts: DateTime.utc(2026, 5, 1, 10, 0, 2)),
      );
      expect(r, isA<WriteWithConflict>());
      final c = r as WriteWithConflict;
      expect(c.survivorBytes, equals(bytes(remoteBody)),
          reason: 'remote has the later ts → survives');
      expect(c.loserBytes, equals(bytes(localBody)));
      expect(c.survivorOrigin, equals(ConflictOrigin.remote));
      expect(c.loserOrigin, equals(ConflictOrigin.local));
    });

    test('local frontmatter has key remote lacks → WriteWithConflict',
        () {
      final localBody = '---\nweight_kg: 14.2\nmeds: [carafate]\n---\n\nbody';
      final remoteBody = '---\nweight_kg: 14.2\n---\n\nbody';
      final r = const ConflictResolver().resolve(
        local: local(localBody, ts: DateTime.utc(2026, 5, 1, 10, 0, 2)),
        remote: remote(remoteBody, ts: DateTime.utc(2026, 5, 1, 10, 0, 0)),
      );
      expect(r, isA<WriteWithConflict>());
      final c = r as WriteWithConflict;
      expect(c.survivorBytes, equals(bytes(localBody)),
          reason: 'local has the later ts → survives');
      expect(c.loserBytes, equals(bytes(remoteBody)));
    });

    test('determinism: device A and device B produce the same '
        'survivor + same loser bytes', () {
      // Setup: A wrote at t=10, B wrote at t=12 (both within 5s).
      // Both have structurally-divergent frontmatter (different
      // key sets).
      final aBody = '---\nfoo: 1\nshared: a\n---\n\na content';
      final bBody = '---\nbar: 2\nshared: a\n---\n\nb content';
      final aTs = DateTime.utc(2026, 5, 1, 10, 0, 10);
      final bTs = DateTime.utc(2026, 5, 1, 10, 0, 12);

      // Device A pulls B's version: A.local = aBody@aTs, A.remote = bBody@bTs
      final aResolution = const ConflictResolver().resolve(
        local: local(aBody, ts: aTs),
        remote: remote(bBody, ts: bTs),
      );
      // Device B pulls A's version: B.local = bBody@bTs, B.remote = aBody@aTs
      final bResolution = const ConflictResolver().resolve(
        local: local(bBody, ts: bTs),
        remote: remote(aBody, ts: aTs),
      );

      expect(aResolution, isA<WriteWithConflict>());
      expect(bResolution, isA<WriteWithConflict>());
      final aRes = aResolution as WriteWithConflict;
      final bRes = bResolution as WriteWithConflict;

      // Both devices: survivor = bBody (later ts); loser = aBody.
      expect(aRes.survivorBytes, equals(bytes(bBody)));
      expect(bRes.survivorBytes, equals(bytes(bBody)));
      expect(aRes.loserBytes, equals(bytes(aBody)));
      expect(bRes.loserBytes, equals(bytes(aBody)));
    });
  });

  group('within 5s skew window — body-only edits use simple LWW', () {
    test('same frontmatter keys, different body, later remote ts → '
        'KeepRemote (no .conflict.md)', () {
      final localBody = '---\nfoo: 1\n---\n\nlocal body text';
      final remoteBody = '---\nfoo: 1\n---\n\nremote body text';
      final r = const ConflictResolver().resolve(
        local: local(localBody, ts: DateTime.utc(2026, 5, 1, 10, 0, 0)),
        remote: remote(remoteBody, ts: DateTime.utc(2026, 5, 1, 10, 0, 2)),
      );
      expect(r, isA<KeepRemote>());
    });

    test('exact-tie ts: deterministic tiebreak by hash, BOTH devices '
        'pick the same survivor', () {
      final localBody = '---\nfoo: 1\n---\n\nbody A';
      final remoteBody = '---\nfoo: 1\n---\n\nbody B';
      final ts = DateTime.utc(2026, 5, 1);

      final aResolution = const ConflictResolver().resolve(
        local: local(localBody, ts: ts),
        remote: remote(remoteBody, ts: ts),
      );
      final bResolution = const ConflictResolver().resolve(
        local: local(remoteBody, ts: ts),
        remote: remote(localBody, ts: ts),
      );

      // Whichever side wins on device A also wins on device B.
      // (Hash-comparison-based tiebreak.)
      Uint8List winnerOn(ConflictResolution r, ConflictParticipant l, ConflictParticipant rem) {
        if (r is KeepLocal) return l.bytes;
        if (r is KeepRemote) return r.bytes;
        return (r as WriteWithConflict).survivorBytes;
      }

      final aLocal = local(localBody, ts: ts);
      final aRemote = remote(remoteBody, ts: ts);
      final bLocal = local(remoteBody, ts: ts);
      final bRemote = remote(localBody, ts: ts);

      final aWinner = winnerOn(aResolution, aLocal, aRemote);
      final bWinner = winnerOn(bResolution, bLocal, bRemote);
      expect(aWinner, equals(bWinner),
          reason: 'tie-break must be deterministic across devices');
    });
  });

  group('identical-body short-circuit', () {
    test('local.bytes == remote.bytes → KeepLocal regardless of ts',
        () {
      final body = '---\nfoo: 1\n---\n\nbody';
      final r = const ConflictResolver().resolve(
        local: local(body, ts: DateTime.utc(2026, 5, 1, 10, 0, 0)),
        remote: remote(body, ts: DateTime.utc(2026, 5, 1, 10, 0, 100)),
      );
      expect(r, isA<KeepLocal>(),
          reason: 'identical body = no-op, no rewrite');
    });
  });

  group('first-pull on a device with no local file', () {
    test('local == null → KeepRemote', () {
      final r = const ConflictResolver().resolve(
        local: null,
        remote: remote('body', ts: DateTime.utc(2026, 5, 1)),
      );
      expect(r, isA<KeepRemote>());
    });
  });

  group('post-restart local ts unknown', () {
    test('local body == remote body → KeepLocal (no-op even '
        'without a ts)', () {
      final body = 'identical body';
      final r = const ConflictResolver().resolve(
        local: local(body), // no ts
        remote: remote(body, ts: DateTime.utc(2026, 5, 1)),
      );
      expect(r, isA<KeepLocal>());
    });

    test('local body != remote body, no local ts → defensive '
        'WriteWithConflict (preserves the user edit)', () {
      final r = const ConflictResolver().resolve(
        local: local('local pre-restart edit'), // no ts
        remote: remote('older remote', ts: DateTime.utc(2026, 5, 1)),
      );
      expect(r, isA<WriteWithConflict>());
      final c = r as WriteWithConflict;
      // Remote becomes the survivor (LWW assumption when ts is
      // unknown is "trust remote"); local goes to .conflict.md
      // so the user can review their pre-restart edit.
      expect(c.survivorBytes, equals(bytes('older remote')));
      expect(c.loserBytes, equals(bytes('local pre-restart edit')));
      expect(c.loserTs, isNull,
          reason: 'loser ts is unknown when the user edited offline + '
              'restarted before the next sync');
    });
  });

  group('conflictPathFor', () {
    test('strips .md and appends .conflict.md', () {
      expect(conflictPathFor('vet/checkup.md'), equals('vet/checkup.conflict.md'));
    });

    test('non-.md path appends .conflict.md verbatim', () {
      expect(conflictPathFor('photos/abc.jpg'),
          equals('photos/abc.jpg.conflict.md'));
    });
  });

  group('configurable skew tolerance', () {
    test('a 1-second tolerance widens the LWW boundary', () {
      // With default 5s tolerance, a 4s gap is concurrent →
      // structural diverge would fire. With 1s tolerance, 4s
      // is outside the window → pure LWW.
      final localBody = '---\nfoo: 1\n---\n\nbody';
      final remoteBody = '---\nfoo: 1\nbar: 2\n---\n\nbody';
      final tight = const ConflictResolver(
        skewTolerance: Duration(seconds: 1),
      ).resolve(
        local: local(localBody, ts: DateTime.utc(2026, 5, 1, 10, 0, 0)),
        remote: remote(remoteBody, ts: DateTime.utc(2026, 5, 1, 10, 0, 4)),
      );
      expect(tight, isA<KeepRemote>(),
          reason: '4s outside the 1s window → pure LWW');
    });
  });
}

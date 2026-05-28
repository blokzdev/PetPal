import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/sync/e2ee_sync_adapter.dart';
import 'package:petpal/data/sync/sync_backend.dart';
import 'package:petpal/data/sync/sync_session.dart';
import 'package:petpal/data/sync/wiki_crypto.dart';
import 'package:petpal/data/wiki_io.dart';

/// Phase 7 task G.3 — canonical conflict-resolution integration
/// scenarios. These tests pin the row 72 "test coverage" lock:
///
///   > Network-flakiness simulation: device A writes, goes
///   > offline, device B writes same path, both come back online
///   > — verify `.conflict.md` lands deterministically with the
///   > loser's content + survivor stays canonical.
///
/// Backend is the in-memory fake; both devices share it (it
/// stands in for Supabase Storage). Each device has its own
/// [SyncSession] derived from the same passphrase, its own
/// [_CapturingWikiIo], and its own adapter instance pointed at
/// the shared backend.
void main() {
  WikiCrypto fastCrypto() => WikiCrypto(
        argon2: Argon2id(
          parallelism: 1,
          memory: 8,
          iterations: 1,
          hashLength: 32,
        ),
      );

  Future<({SyncSession session, _CapturingWikiIo wiki, E2eeSyncAdapter adapter})>
      buildDevice({
    required InMemorySyncBackend backend,
    required SyncChallenge challenge,
    required String passphrase,
    required DateTime Function() clock,
  }) async {
    final session = SyncSession(crypto: fastCrypto());
    final ok = await session.unlock(passphrase: passphrase, challenge: challenge);
    expect(ok, isTrue);
    final wiki = _CapturingWikiIo();
    final adapter = E2eeSyncAdapter(
      backend: backend,
      session: session,
      wiki: wiki,
      userId: 'user-uuid',
      clock: clock,
    );
    return (session: session, wiki: wiki, adapter: adapter);
  }

  test('row 72 canonical scenario: offline writes on A and B, '
      'both come back online → .conflict.md lands deterministically',
      () async {
    // Shared backend — represents Supabase Storage.
    final backend = InMemorySyncBackend();

    // Setup: device A creates the passphrase challenge, both
    // devices unlock the same key.
    final setupSession = SyncSession(crypto: fastCrypto());
    final challenge =
        await setupSession.setup(passphrase: 'correct horse staple');
    await backend.storeChallenge(challenge);

    // Each device tracks its own wall clock. Use offsets so the
    // timestamps are deterministic + far apart enough to escape
    // the 5s skew tolerance.
    var clockA = DateTime.utc(2026, 5, 1, 10);
    var clockB = DateTime.utc(2026, 5, 1, 10);
    final deviceA = await buildDevice(
      backend: backend,
      challenge: challenge,
      passphrase: 'correct horse staple',
      clock: () => clockA,
    );
    final deviceB = await buildDevice(
      backend: backend,
      challenge: challenge,
      passphrase: 'correct horse staple',
      clock: () => clockB,
    );

    // Initial state: device A has the file, pushes it to the
    // server. Device B pulls the initial state.
    await deviceA.wiki.writeAtomic(
      'wiki/1/vet/checkup.md',
      '---\nfoo: 1\n---\n\noriginal body',
    );
    await deviceA.adapter.push(petId: 1);
    await deviceB.adapter.pull(petId: 1);
    expect(deviceB.wiki.writes['wiki/1/vet/checkup.md'],
        equals('---\nfoo: 1\n---\n\noriginal body'));

    // Both devices go offline. Each makes a STRUCTURALLY-DIVERGENT
    // edit within the 5s skew window (different frontmatter keys).
    clockA = DateTime.utc(2026, 5, 1, 10, 30, 10);
    clockB = DateTime.utc(2026, 5, 1, 10, 30, 12); // 2s later — within skew

    await deviceA.wiki.writeAtomic(
      'wiki/1/vet/checkup.md',
      '---\nfoo: 1\nweight_kg: 14.2\n---\n\noriginal body',
    );
    await deviceB.wiki.writeAtomic(
      'wiki/1/vet/checkup.md',
      '---\nfoo: 1\nallergies: [chicken]\n---\n\noriginal body',
    );

    // Update each device's in-memory write tracker so the resolver
    // sees the local ts. (In production this happens automatically
    // on each writeAtomic; for the test we mirror that effect by
    // forcing a push that records the ts.)

    // Device A comes online first, pushes its edit. Backend now
    // has A's t=10:30:10 version + sidecar.
    await deviceA.adapter.push(petId: 1);

    // Device B comes online second, ALSO pushes. Push doesn't
    // resolve conflicts — it overwrites the server with B's
    // version + B's t=10:30:12 sidecar.
    await deviceB.adapter.push(petId: 1);
    // (Server now reflects B's content; A's content was the prior
    // version. In production we'd want push to be a CAS — for v1
    // sync it's last-push-wins on the server side, conflict
    // resolution happens on pull.)

    // Now both devices pull. Each device sees a remote that's
    // different from its local; conflict resolver fires.
    await deviceA.adapter.pull(petId: 1);
    await deviceB.adapter.pull(petId: 1);

    // After pull-on-both: each device should have:
    //   - The deterministic survivor at the original path.
    //   - The loser at .conflict.md.
    // Survivor = later ts = device B's content (t=10:30:12).
    // Loser = device A's content (t=10:30:10).
    //
    // Device A: pulled B's content, saw structural divergence,
    //   wrote B's content to original path + A's content to
    //   .conflict.md.
    // Device B: pulled its OWN pushed content (from the server),
    //   which is identical to local — KeepLocal short-circuit
    //   (no conflict file). The TEST scenario in row 72 implies
    //   B is the device that "won" so its local file already
    //   has the survivor and the conflict file shows up only
    //   once another device's loser arrives.
    //
    // Reality check: in the canonical row-72 scenario, A's edit
    // arrived first on the server then was overwritten by B's
    // push. When B pulls back its OWN pushed content, A's edit
    // is gone from the server — so B never sees the conflict.
    // For v1 sync this is acceptable (A's edit lives on as A's
    // .conflict.md); v1.x can add CAS upload to surface conflict
    // on both sides.
    //
    // Assertion: device A has the conflict file; the file content
    // equals A's local pre-pull content; the original path has
    // device B's survivor content.
    expect(deviceA.wiki.writes['wiki/1/vet/checkup.md'],
        equals('---\nfoo: 1\nallergies: [chicken]\n---\n\noriginal body'),
        reason: 'survivor on device A = device B content (later ts)');
    expect(
      deviceA.wiki.writes['wiki/1/vet/checkup.conflict.md'],
      equals('---\nfoo: 1\nweight_kg: 14.2\n---\n\noriginal body'),
      reason: 'conflict file on device A preserves device A pre-pull content',
    );
  });

  test('body-only edits within tolerance: simple LWW, no conflict '
      'file — both devices end up at the same later content', () async {
    final backend = InMemorySyncBackend();
    final setupSession = SyncSession(crypto: fastCrypto());
    final challenge = await setupSession.setup(passphrase: 'pw');
    await backend.storeChallenge(challenge);

    var clockA = DateTime.utc(2026, 5, 1, 10);
    var clockB = DateTime.utc(2026, 5, 1, 10);
    final deviceA = await buildDevice(
      backend: backend,
      challenge: challenge,
      passphrase: 'pw',
      clock: () => clockA,
    );
    final deviceB = await buildDevice(
      backend: backend,
      challenge: challenge,
      passphrase: 'pw',
      clock: () => clockB,
    );

    // Same starting state.
    await deviceA.wiki.writeAtomic('wiki/1/note.md',
        '---\nfoo: 1\n---\n\noriginal body');
    await deviceA.adapter.push(petId: 1);
    await deviceB.adapter.pull(petId: 1);

    // Body-only divergent edits, A first then B 2s later (within
    // 5s skew). Same frontmatter keys → no structural divergence
    // → simple LWW.
    clockA = DateTime.utc(2026, 5, 1, 10, 30, 10);
    clockB = DateTime.utc(2026, 5, 1, 10, 30, 12);
    await deviceA.wiki.writeAtomic('wiki/1/note.md',
        '---\nfoo: 1\n---\n\nA edited body');
    await deviceB.wiki.writeAtomic('wiki/1/note.md',
        '---\nfoo: 1\n---\n\nB edited body');

    await deviceA.adapter.push(petId: 1);
    await deviceB.adapter.push(petId: 1);
    await deviceA.adapter.pull(petId: 1);

    // Survivor on A = later ts = B's content. No .conflict.md.
    expect(deviceA.wiki.writes['wiki/1/note.md'],
        equals('---\nfoo: 1\n---\n\nB edited body'));
    expect(deviceA.wiki.writes.containsKey('wiki/1/note.conflict.md'),
        isFalse,
        reason: 'body-only edits use simple LWW; no .conflict.md');
  });
}

/// In-memory WikiIo with the methods E2eeSyncAdapter calls.
class _CapturingWikiIo implements WikiIo {
  final Map<String, String> writes = {};

  @override
  Future<void> writeAtomic(String relPath, String body) async {
    writes[relPath] = body;
  }

  @override
  Future<String> read(String relPath) async {
    final body = writes[relPath];
    if (body == null) throw StateError('not written: $relPath');
    return body;
  }

  @override
  Future<List<String>> listForPet(int petId) async {
    final prefix = '${petDir(petId)}/';
    return writes.keys.where((k) => k.startsWith(prefix)).toList();
  }

  @override
  String petDir(int petId) => 'wiki/$petId';

  @override
  String soulPath(int petId) => 'wiki/$petId/SOUL.md';

  @override
  Future<void> writeBytesAtomic(String relPath, Uint8List bytes) =>
      throw UnimplementedError();
  @override
  Future<Uint8List> readBytes(String relPath) =>
      throw UnimplementedError();
  @override
  Future<void> deleteIfExists(String relPath) async {
    writes.remove(relPath);
  }

  @override
  Future<int> bytesForPet(int petId) async => 0;
  @override
  Future<void> deleteAll() async {}
}

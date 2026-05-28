import 'dart:typed_data';

import '../soul_file.dart';
import 'wiki_crypto.dart';

/// Phase 7 task G.3 — sync conflict resolution.
///
/// Implements DECISIONS row 72's locked behavior: deterministic
/// last-writer-wins outside the 5-second skew tolerance window;
/// `.conflict.md` fallback for genuinely-divergent edits within
/// the window OR when the user added/removed YAML frontmatter
/// keys (structural change).
///
/// **Determinism across devices.** Both devices must produce the
/// same survivor + same `.conflict.md` content. The resolver
/// achieves this by:
///
///   - Comparing `writeTs` symmetrically (no "local always wins
///     in tie" rule).
///   - Tie-breaking exact-tie-on-ts cases by lexicographic
///     comparison of `body_hash` (deterministic across devices —
///     both compute SHA-256 of the same bytes).
///   - On ts-unknown local + diverged body, defaulting to
///     remote-as-survivor + local-as-conflict (preserves the
///     user's pre-restart edit instead of silently losing it).
///
/// **Body-hash dedup short-circuit.** If `local.bytes ==
/// remote.bytes` the resolver always returns [KeepLocal] (no-op),
/// regardless of timestamps — equal content under different
/// timestamps means both devices ended up at the same place; no
/// reason to rewrite the file or split into a conflict.
class ConflictResolver {
  const ConflictResolver({
    this.skewTolerance = const Duration(seconds: 5),
  });

  /// Per DECISIONS row 72: writes within this window of each other
  /// are treated as concurrent. Outside this window: pure LWW.
  final Duration skewTolerance;

  ConflictResolution resolve({
    required ConflictParticipant? local,
    required ConflictParticipant remote,
  }) {
    // remote always carries a sidecar-recorded ts (ConflictParticipant
    // contract); only the local side may be ts-less.
    final remoteTs = remote.writeTs!;

    if (local == null) {
      return KeepRemote(bytes: remote.bytes, writeTs: remoteTs);
    }

    if (_bytesEqual(local.bytes, remote.bytes)) {
      return const KeepLocal();
    }

    final localTs = local.writeTs;
    if (localTs == null) {
      // _lastWriteTs tracker is missing this path — usually means
      // app relaunch hasn't seen this entry's prior write yet. We
      // can't perform LWW without a comparable ts; default to
      // remote-as-survivor + emit a .conflict.md to preserve the
      // user's local pre-restart edit. Better-safe than silently
      // overwriting work.
      return WriteWithConflict(
        survivorBytes: remote.bytes,
        survivorTs: remoteTs,
        survivorOrigin: ConflictOrigin.remote,
        loserBytes: local.bytes,
        loserTs: null,
        loserOrigin: ConflictOrigin.local,
      );
    }

    final delta = remoteTs.difference(localTs);
    if (delta > skewTolerance) {
      return KeepRemote(bytes: remote.bytes, writeTs: remoteTs);
    }
    if (-delta > skewTolerance) {
      return const KeepLocal();
    }

    // Within skew tolerance — concurrent edit. Per row 72:
    // structural changes (frontmatter key adds/removes) count as
    // genuine divergence; body-only edits within tolerance are
    // pure LWW with hash tiebreak.
    if (_structurallyDiverged(local.bytes, remote.bytes)) {
      final remoteIsLater = !delta.isNegative;
      if (delta.inMicroseconds == 0) {
        // Exact-tie ts + structural divergence — break by hash.
        final localHash = WikiCrypto.bodyHash(local.bytes);
        final remoteHash = WikiCrypto.bodyHash(remote.bytes);
        final remoteWins = remoteHash.compareTo(localHash) > 0;
        return _conflict(local: local, remote: remote, remoteWins: remoteWins);
      }
      return _conflict(local: local, remote: remote, remoteWins: remoteIsLater);
    }

    // Body-only edit within tolerance: LWW, with hash tiebreak on
    // exact ts ties for cross-device determinism.
    if (delta.inMicroseconds == 0) {
      final localHash = WikiCrypto.bodyHash(local.bytes);
      final remoteHash = WikiCrypto.bodyHash(remote.bytes);
      return remoteHash.compareTo(localHash) > 0
          ? KeepRemote(bytes: remote.bytes, writeTs: remoteTs)
          : const KeepLocal();
    }
    if (delta.isNegative) return const KeepLocal();
    return KeepRemote(bytes: remote.bytes, writeTs: remoteTs);
  }

  WriteWithConflict _conflict({
    required ConflictParticipant local,
    required ConflictParticipant remote,
    required bool remoteWins,
  }) {
    if (remoteWins) {
      return WriteWithConflict(
        survivorBytes: remote.bytes,
        survivorTs: remote.writeTs!,
        survivorOrigin: ConflictOrigin.remote,
        loserBytes: local.bytes,
        loserTs: local.writeTs,
        loserOrigin: ConflictOrigin.local,
      );
    }
    return WriteWithConflict(
      survivorBytes: local.bytes,
      survivorTs: local.writeTs!,
      survivorOrigin: ConflictOrigin.local,
      loserBytes: remote.bytes,
      loserTs: remote.writeTs,
      loserOrigin: ConflictOrigin.remote,
    );
  }

  bool _structurallyDiverged(Uint8List a, Uint8List b) {
    final aFm = parseSoul(String.fromCharCodes(a)).frontmatter.keys.toSet();
    final bFm = parseSoul(String.fromCharCodes(b)).frontmatter.keys.toSet();
    return aFm.difference(bFm).isNotEmpty || bFm.difference(aFm).isNotEmpty;
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Inputs to the resolver. `writeTs` is nullable on the local side
/// only — the remote side always has a sidecar-recorded ts.
class ConflictParticipant {
  const ConflictParticipant({
    required this.bytes,
    required this.writeTs,
  });

  final Uint8List bytes;
  final DateTime? writeTs;
}

/// Tagged result of a conflict resolution.
sealed class ConflictResolution {
  const ConflictResolution();
}

/// Local content stays canonical. No file writes. No conflict file.
final class KeepLocal extends ConflictResolution {
  const KeepLocal();
}

/// Remote wins LWW. Adapter writes [bytes] to the original path
/// and updates the local writeTs tracker to [writeTs]. No conflict
/// file.
final class KeepRemote extends ConflictResolution {
  const KeepRemote({required this.bytes, required this.writeTs});
  final Uint8List bytes;
  final DateTime writeTs;
}

/// Genuine divergence. Adapter writes [survivorBytes] to the
/// original path and writes [loserBytes] to the deterministically-
/// derived `<original-name>.conflict.md` path next to it.
///
/// The survivor is whichever side has the later ts (per LWW); on
/// exact-tie ts the lexicographically-larger `body_hash` survives
/// (so both devices pick the same survivor independently).
///
/// Pre-restart local edits with an unknown ts always survive as
/// the loser (preserved in `.conflict.md`); remote becomes the
/// canonical version. The adapter never silently overwrites a
/// diverged-body local edit.
final class WriteWithConflict extends ConflictResolution {
  const WriteWithConflict({
    required this.survivorBytes,
    required this.survivorTs,
    required this.survivorOrigin,
    required this.loserBytes,
    required this.loserTs,
    required this.loserOrigin,
  });

  final Uint8List survivorBytes;
  final DateTime survivorTs;
  final ConflictOrigin survivorOrigin;
  final Uint8List loserBytes;

  /// Null when the loser was a local pre-restart edit (no ts in
  /// the in-memory tracker). The loser content still lands in the
  /// `.conflict.md` file regardless.
  final DateTime? loserTs;
  final ConflictOrigin loserOrigin;
}

enum ConflictOrigin { local, remote }

/// Build the canonical `.conflict.md` path from the original
/// relative path. `vet/checkup.md` → `vet/checkup.conflict.md`.
/// Strips the trailing `.md` if present so two `.md.conflict.md`
/// suffixes don't accumulate; otherwise appends `.conflict.md`.
String conflictPathFor(String original) {
  if (original.endsWith('.md')) {
    return '${original.substring(0, original.length - 3)}.conflict.md';
  }
  return '$original.conflict.md';
}

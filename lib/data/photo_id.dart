import 'dart:math';

/// Mint a fresh photo id — UUID v4 (random, 122 bits of entropy). Used as
/// the filename stem for the `<id>.jpg` + `<id>.md` pair under
/// `wiki/<pet_id>/photos/`. Phase 6 task 6.1.
///
/// Inline rather than depending on `package:uuid` because PetPal already
/// has `crypto` for entropy-adjacent work, photo ids aren't security-
/// critical (no information leak, no auth path), and a one-function file
/// avoids the new-direct-dep + DECISIONS-row ceremony for a 10-line
/// utility. If photo storage scales to where we want timestamp-sortable
/// v7 ids, upgrade then.
String newPhotoId({Random? random}) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  // RFC 4122 v4 layout: bits set the version (4) and variant (RFC 4122).
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) => b
      .sublist(from, to)
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

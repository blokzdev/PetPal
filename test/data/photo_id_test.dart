import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/photo_id.dart';

void main() {
  group('newPhotoId (Phase 6 task 6.1)', () {
    test('produces canonical 36-char UUID v4 string with hyphens at '
        'positions 8/13/18/23', () {
      final id = newPhotoId();
      expect(id.length, 36);
      expect(id[8], '-');
      expect(id[13], '-');
      expect(id[18], '-');
      expect(id[23], '-');
    });

    test('encodes the UUID v4 version (4) and variant (RFC 4122) bits', () {
      final id = newPhotoId();
      // Position 14 is the version nibble — must be '4' for v4.
      expect(id[14], '4');
      // Position 19 is the high nibble of the variant byte — must be
      // 8/9/a/b for RFC 4122.
      expect('89ab'.contains(id[19]), isTrue, reason: 'variant nibble');
    });

    test('two consecutive calls produce different ids (collision in 2 '
        'draws of 122-bit space is astronomical)', () {
      final a = newPhotoId();
      final b = newPhotoId();
      expect(a, isNot(b));
    });

    test('accepts an injected Random for deterministic tests — same seed '
        'produces same id', () {
      final id1 = newPhotoId(random: Random(42));
      final id2 = newPhotoId(random: Random(42));
      expect(id1, id2);
    });
  });
}

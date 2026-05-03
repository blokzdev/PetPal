import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 7 task H.2.b — Pass E. Source-presence assertion that the
/// `appSnackBar` helper still wires `SemanticsService.announce` so
/// every snackbar dispatched through the central helper is also
/// announced to TalkBack.
///
/// The behavioural test for `announce: false` opt-out lives in
/// `test/app/widgets/app_scaffold_test.dart` alongside the existing
/// `appSnackBar` helper tests; this file pins the wire itself so a
/// future "while I'm here" cleanup that drops the announce can't
/// land silently.
void main() {
  group('Pass E — appSnackBar wires SemanticsService.announce', () {
    test('app_scaffold.dart imports flutter/semantics.dart', () {
      final src = File('lib/app/widgets/app_scaffold.dart').readAsStringSync();
      expect(
        src.contains("import 'package:flutter/semantics.dart';"),
        isTrue,
        reason:
            'app_scaffold.dart must import flutter/semantics.dart for '
            'SemanticsService — Phase 7 H.2.b regression',
      );
    });

    test('appSnackBar calls SemanticsService.announce by default', () {
      final src = File('lib/app/widgets/app_scaffold.dart').readAsStringSync();
      // The wire — must announce the message in the active reading
      // direction (Directionality.of(context)) so TalkBack reads it
      // aloud as it appears on screen.
      expect(
        src.contains(
          'SemanticsService.announce(message, Directionality.of(context))',
        ),
        isTrue,
        reason:
            'appSnackBar dropped its SemanticsService.announce wire — '
            'Phase 7 H.2.b regression. TalkBack would not read the '
            'snackbar text without this.',
      );
    });

    test('appSnackBar exposes an announce: false opt-out', () {
      final src = File('lib/app/widgets/app_scaffold.dart').readAsStringSync();
      expect(
        src.contains('bool announce = true'),
        isTrue,
        reason:
            'appSnackBar should keep an `announce: true` default + '
            'opt-out so callers can suppress the announcement when '
            'the message duplicates state already in the semantics '
            'tree (e.g. a banner that itself reads aloud).',
      );
    });
  });
}

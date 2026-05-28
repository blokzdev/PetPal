import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 7 task H.2.b — Pass E. Source-presence assertion that the
/// `appSnackBar` helper still wires `SemanticsService.sendAnnouncement`
/// so every snackbar dispatched through the central helper is also
/// announced to TalkBack. (`announce` was deprecated after Flutter
/// v3.35; `sendAnnouncement` is the multi-window-safe replacement.)
///
/// The behavioural test for `announce: false` opt-out lives in
/// `test/app/widgets/app_scaffold_test.dart` alongside the existing
/// `appSnackBar` helper tests; this file pins the wire itself so a
/// future "while I'm here" cleanup that drops the announce can't
/// land silently.
void main() {
  group('Pass E — appSnackBar wires SemanticsService.sendAnnouncement', () {
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

    test('appSnackBar calls SemanticsService.sendAnnouncement by default', () {
      final src = File('lib/app/widgets/app_scaffold.dart').readAsStringSync();
      // The wire — must announce the message in the active reading
      // direction so TalkBack reads it aloud as it appears on screen.
      // Audit fix (post-H.2.b) replaced `Directionality.of(context)`
      // with the defensive `Directionality.maybeOf(context) ??
      // TextDirection.ltr` form; the substring assertion below
      // matches both shapes by anchoring on the announce call only.
      expect(
        src.contains('SemanticsService.sendAnnouncement('),
        isTrue,
        reason:
            'appSnackBar dropped its SemanticsService.sendAnnouncement '
            'wire — Phase 7 H.2.b regression. TalkBack would not read '
            'the snackbar text without this.',
      );
      // And the Directionality lookup must be the defensive maybeOf
      // form per the audit fix — strict `Directionality.of(context)`
      // throws if any future caller dispatches from a context
      // without a Directionality ancestor.
      expect(
        src.contains('Directionality.maybeOf(context)'),
        isTrue,
        reason:
            'appSnackBar must use Directionality.maybeOf with an LTR '
            'fallback — strict .of(context) throws on missing ancestor',
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

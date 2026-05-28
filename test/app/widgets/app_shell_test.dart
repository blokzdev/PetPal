import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 7 audit fix — `AppShell` post-sign-in snackbar wire
/// regression-lock.
///
/// The behavioural test for `PostSignInUndoNotifier` lives in
/// `test/app/account/post_sign_in_undo_notifier_test.dart` and
/// exercises the state machine in isolation. The wire from notifier
/// state into the snackbar surface lives inside `AppShell`'s
/// `ref.listen` callback. Pumping AppShell directly requires
/// constructing a `StatefulNavigationShell` which is a private
/// go_router internal — not testable from outside the routing layer.
///
/// Source-presence assertion is the right shape here: it catches the
/// silent-failure case where a future "while I'm here" cleanup
/// removes the listener wiring or the acknowledge call. Same pattern
/// as `test/a11y/semantics_label_test.dart` (Pass A) and
/// `test/a11y/announce_test.dart` (Pass E).
void main() {
  group('AppShell — post-sign-in undo snackbar wire', () {
    test('imports PostSignInUndoNotifier + appSnackBar', () {
      final src = File('lib/app/widgets/app_shell.dart').readAsStringSync();
      expect(
        src.contains("import '../account/post_sign_in_undo_notifier.dart';"),
        isTrue,
        reason: 'AppShell must import the post-sign-in undo notifier '
            'to listen for cancellation events',
      );
      expect(
        src.contains("import 'app_scaffold.dart';"),
        isTrue,
        reason: 'AppShell must import app_scaffold for appSnackBar',
      );
    });

    test('subscribes to PostSignInUndoState via ref.listen', () {
      final src = File('lib/app/widgets/app_shell.dart').readAsStringSync();
      expect(
        src.contains('ref.listen<PostSignInUndoState>'),
        isTrue,
        reason: 'AppShell must `ref.listen` on the postSignInUndoProvider '
            'so the snackbar surfaces when the notifier emits Cancelled',
      );
      expect(
        src.contains('postSignInUndoProvider'),
        isTrue,
        reason: 'AppShell must reference postSignInUndoProvider',
      );
    });

    test('dispatches appSnackBar on PostSignInUndoCancelled', () {
      final src = File('lib/app/widgets/app_shell.dart').readAsStringSync();
      expect(
        src.contains('PostSignInUndoCancelled'),
        isTrue,
        reason: 'AppShell must check for the Cancelled state',
      );
      expect(
        src.contains('appSnackBar('),
        isTrue,
        reason: 'AppShell must call appSnackBar when Cancelled fires',
      );
    });

    test('uses the canonical VOICE.md-aligned snackbar copy', () {
      final src = File('lib/app/widgets/app_shell.dart').readAsStringSync();
      // Locked copy per DECISIONS row 90 — the friendly + direct
      // register that matches the soft-delete confirmation copy.
      // Exact-string regression-lock so a future edit doesn't
      // silently drift the user-facing message.
      expect(
        src.contains('Welcome back. Your account-deletion request was'),
        isTrue,
        reason: 'AppShell snackbar copy must match the locked VOICE.md '
            'register for post-sign-in cancellation',
      );
      expect(
        src.contains('cancelled — your data is safe'),
        isTrue,
        reason: 'AppShell snackbar must close with the "your data is '
            'safe" reassurance phrase',
      );
    });

    test('acknowledges the notifier state after surfacing', () {
      final src = File('lib/app/widgets/app_shell.dart').readAsStringSync();
      // Without acknowledge() the state stays Cancelled and would
      // re-fire the snackbar on every AppShell rebuild.
      expect(
        src.contains('.acknowledge()'),
        isTrue,
        reason: 'AppShell must call acknowledge() after dispatching the '
            'snackbar so the state resets to Idle and the snackbar '
            'doesn\'t re-fire on every rebuild',
      );
    });
  });
}

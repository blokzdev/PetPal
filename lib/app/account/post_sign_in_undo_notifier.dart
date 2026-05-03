import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_session_notifier.dart';
import 'account_deletion_client.dart';

/// Phase 7 task H.1.d.undo — proactive post-sign-in cancellation of
/// pending account deletions.
///
/// Per DECISIONS row 77: a user who taps "Delete account" but signs
/// in again within the 30-day retention window should have the
/// deletion cancelled automatically, with a transient toast
/// announcing the reversal.
///
/// **State machine.**
///   - [PostSignInUndoIdle] — no recent sign-in event, or last
///     sign-in produced no pending deletion.
///   - [PostSignInUndoCancelled] — last sign-in event cancelled a
///     pending deletion. UI surfaces a "deletion cancelled" snackbar
///     once and resets to idle via [acknowledge].
///   - [PostSignInUndoError] — the cancel network call failed. UI
///     can choose to surface or ignore; the cron-side defensive
///     check (`auth.users.last_sign_in_at > delete_requested_at`) is
///     the safety net so a cancel call failure does NOT mean the
///     account stays scheduled for deletion.
///
/// **Why a separate notifier (not folded into [AuthSessionNotifier]).**
/// The auth notifier's only job is the session value; folding cancel
/// logic in would couple the auth state machine to the deletion
/// surface. The notifier here observes auth state via `ref.listen`
/// and isolates the side effect.
sealed class PostSignInUndoState {
  const PostSignInUndoState();
}

class PostSignInUndoIdle extends PostSignInUndoState {
  const PostSignInUndoIdle();
}

class PostSignInUndoCancelled extends PostSignInUndoState {
  const PostSignInUndoCancelled({required this.eventId});

  /// Monotonic identifier per cancellation event so UI listeners
  /// can detect a fresh event (snackbar fires once per ID even if
  /// the listener rebuilds).
  final int eventId;
}

class PostSignInUndoError extends PostSignInUndoState {
  const PostSignInUndoError(this.message);
  final String message;
}

class PostSignInUndoNotifier extends Notifier<PostSignInUndoState> {
  int _eventCounter = 0;
  String? _lastSignedInUserId;

  @override
  PostSignInUndoState build() {
    ref.listen(
      authSessionProvider,
      (_, next) {
        final nextUserId = next.value?.userId;
        // Fire on a transition into a non-null user that's NEW —
        // either previously signed-out, or signed-in as a different
        // user. Same-user re-emission (e.g. token refresh) doesn't
        // refire because `_lastSignedInUserId` matches.
        if (nextUserId != null && nextUserId != _lastSignedInUserId) {
          _lastSignedInUserId = nextUserId;
          _checkPendingDeletion();
        }
        if (nextUserId == null) {
          _lastSignedInUserId = null;
        }
      },
      fireImmediately: false,
    );
    return const PostSignInUndoIdle();
  }

  Future<void> _checkPendingDeletion() async {
    final client = ref.read(accountDeletionClientProvider);
    if (client == null) {
      // Supabase unconfigured — nothing to cancel against.
      return;
    }
    try {
      final wasPending = await client.cancelDeletion();
      if (wasPending) {
        _eventCounter++;
        state = PostSignInUndoCancelled(eventId: _eventCounter);
      }
      // No pending deletion → state stays idle. Quiet success — the
      // user wouldn't expect a toast for "you didn't actually have
      // a pending deletion."
    } catch (e) {
      state = PostSignInUndoError(e.toString());
    }
  }

  /// Reset the cancelled state to idle once the UI has surfaced the
  /// event (snackbar shown). Idempotent.
  void acknowledge() {
    if (state is PostSignInUndoCancelled || state is PostSignInUndoError) {
      state = const PostSignInUndoIdle();
    }
  }
}

final postSignInUndoProvider =
    NotifierProvider<PostSignInUndoNotifier, PostSignInUndoState>(
  PostSignInUndoNotifier.new,
);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account/post_sign_in_undo_notifier.dart';
import 'app_scaffold.dart';
import 'pet_bottom_nav.dart';

/// Phase 6.6 task 6.6.A.1/A.2 — `StatefulShellRoute` shell wrapper.
///
/// The 4-tab bottom-nav structure (Home / Journal / Profile / Hub —
/// DECISIONS row 59) lives at this scaffold. A.1 landed the routing
/// skeleton with a transparent shell; **A.2 plugs `PetBottomNav` into
/// the `bottomNavigationBar` slot below**.
///
/// The shell preserves per-branch state via `StatefulShellRoute`'s
/// indexed-stack model (DECISIONS row 65) — switching branches
/// doesn't dispose the inactive branches' Navigators. Chat scroll
/// position (today's canonical state-preservation case) survives a
/// tab switch.
///
/// Phase 7 task H.1.d.undo — also hosts the post-sign-in undo
/// listener. When the user signs in during a 30-day account-deletion
/// retention window, [PostSignInUndoNotifier] cancels the deletion
/// server-side; the listener below surfaces a transient snackbar
/// announcing the reversal.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  /// The active branch's Navigator. Built by go_router's
  /// `StatefulShellRoute.indexedStack` and handed to the shell at
  /// route resolution time.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<PostSignInUndoState>(
      postSignInUndoProvider,
      (previous, next) {
        if (next is PostSignInUndoCancelled) {
          // VOICE.md — warm + direct, mirrors the registers from
          // sign-in success and the soft-delete confirmation copy.
          appSnackBar(
            context,
            'Welcome back. Your account-deletion request was '
            'cancelled — your data is safe.',
            duration: const Duration(seconds: 6),
          );
          ref.read(postSignInUndoProvider.notifier).acknowledge();
        }
        // PostSignInUndoError stays silent — the cron-side defensive
        // check (auth.users.last_sign_in_at > delete_requested_at)
        // is the safety net so a cancel-call failure does NOT mean
        // the account stays scheduled for deletion. Logging only.
      },
    );

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: PetBottomNav(navigationShell: navigationShell),
    );
  }
}

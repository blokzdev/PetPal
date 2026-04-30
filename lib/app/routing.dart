import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import 'screens/add_pet_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/dev_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/photo_capture_screen.dart';
import 'screens/photo_timeline_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/skill_browser_screen.dart';
import 'screens/soul_editor_screen.dart';
import 'screens/wiki_browser_screen.dart';
import 'screens/wiki_entry_screen.dart';

/// Provides the singleton [GoRouter]. Reads [isOnboardedProvider] so an
/// onboarding-status change (saving an API key, or clearing it) reroutes
/// automatically through `refreshListenable`.
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _OnboardedNotifier(ref);
  ref.onDispose(notifier.dispose);
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final onboarded = ref.read(isOnboardedProvider);
      final goingToOnboarding = state.matchedLocation == '/onboarding';
      if (!onboarded && !goingToOnboarding) return '/onboarding';
      if (onboarded && goingToOnboarding) return '/';
      return null;
    },
    refreshListenable: notifier,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/pets/add',
        builder: (context, state) => const AddPetScreen(),
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) => const ChatScreen(),
      ),
      GoRoute(
        path: '/wiki',
        builder: (context, state) => const WikiBrowserScreen(),
      ),
      // Phase 6 task 6.3 — dedicated photo timeline at `/photos`.
      // Reachable from the wiki browser's Photos type-header
      // "View all in timeline" link in 6.3; from the home grid
      // camera CTA's post-save flow in 6.6.
      GoRoute(
        path: '/photos',
        builder: (context, state) => const PhotoTimelineScreen(),
      ),
      // Phase 6 task 6.6 — camera-as-memory capture flow. Reached
      // from the home grid's "Add photo" tile (top-left); launches
      // the camera-vs-gallery chooser on entry, displays the
      // form-preview on pick.
      // Phase 6 task 6.9 — `state.extra` may carry a
      // `PhotoCapturePrefill` from the chat bubble's "Save as memory"
      // affordance. When present, the screen skips the picker and
      // seeds the form with the chat photo + AI's description.
      GoRoute(
        path: '/photos/capture',
        builder: (context, state) {
          final extra = state.extra;
          return PhotoCaptureScreen(
            prefill: extra is PhotoCapturePrefill ? extra : null,
          );
        },
      ),
      GoRoute(
        path: '/soul',
        builder: (context, state) => const SoulEditorScreen(),
      ),
      GoRoute(
        path: '/skills',
        builder: (context, state) => const SkillBrowserScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/reminders',
        builder: (context, state) => const RemindersScreen(),
      ),
      // Phase 5.6 Commit C — `/wiki/entry` adopts a Material
      // SharedAxisTransition (X axis) via `pageBuilder:` so tapping
      // a journal entry from the wiki browser conveys "drilling
      // deeper into the same content" rather than the default
      // bottom-up slide. Other routes stay on
      // PredictiveBackPageTransitionsBuilder (set in app_theme.dart's
      // pageTransitionsTheme) for system back-gesture support.
      GoRoute(
        path: '/wiki/entry',
        pageBuilder: (context, state) {
          final path = state.extra as String?;
          final child = path == null
              ? const Scaffold(
                  body: Center(child: Text('Missing entry path.')),
                )
              : WikiEntryScreen(path: path);
          return CustomTransitionPage<void>(
            key: state.pageKey,
            child: child,
            // CustomTransitionPage's default transitionDuration +
            // reverseTransitionDuration are both 300 ms, equal to
            // Motion.medium — leaving them at the default keeps the
            // intent design-token-aligned without re-stating.
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SharedAxisTransition(
                animation: animation,
                secondaryAnimation: secondaryAnimation,
                transitionType: SharedAxisTransitionType.horizontal,
                child: child,
              );
            },
          );
        },
      ),
      // Phase 1 verification screen — exercises the full harness. Linked
      // from Home only in debug builds (see HomeScreen).
      GoRoute(
        path: '/dev',
        builder: (context, state) => const DevScreen(),
      ),
    ],
  );
});

/// Bridges [isOnboardedProvider] to a [ChangeNotifier] so go_router's
/// `refreshListenable` can subscribe.
class _OnboardedNotifier extends ChangeNotifier {
  _OnboardedNotifier(Ref ref) {
    ref.listen<bool>(isOnboardedProvider, (_, _) => notifyListeners());
  }
}

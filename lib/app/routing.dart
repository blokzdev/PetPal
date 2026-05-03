import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import 'screens/about_screen.dart';
import 'screens/add_pet_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/dev_screen.dart';
import 'screens/home_screen.dart';
import 'screens/hub_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/photo_capture_screen.dart';
import 'screens/photo_credit_pack_screen.dart';
import 'screens/photo_timeline_screen.dart';
import 'screens/profile_view_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/skill_browser_screen.dart';
import 'screens/soul_editor_screen.dart';
import 'screens/vet_visit_form_screen.dart';
import 'screens/wiki_browser_screen.dart';
import 'screens/wiki_entry_screen.dart';
import 'widgets/app_shell.dart';

/// Provides the singleton [GoRouter]. Reads [isOnboardedProvider] so an
/// onboarding-status change (saving an API key, or clearing it) reroutes
/// automatically through `refreshListenable`.
///
/// Phase 6.6 task 6.6.A.1 — adopts `StatefulShellRoute.indexedStack`
/// for the 4-tab bottom-nav IA (DECISIONS rows 59 + 65). Four
/// branches: Home, Journal, Profile, Hub. Each branch preserves its
/// own `Navigator` stack so tab switches don't lose scroll position
/// or in-flight form state. Detail routes (`/wiki/entry`,
/// `/photos/capture`, `/vet/new`) are nested under the appropriate
/// branch so deep-links resolve into the correct tab. Full-screen
/// flows (`/onboarding`, `/pets/add`, `/dev`) sit outside the shell
/// — no bottom nav, no branch state.
///
/// Legacy routes preserved as deep-link targets via redirect (per
/// DECISIONS rows 61 + 62): `/reminders` → `/home/reminders`,
/// `/skills` → `/soul/guides`.
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
      // Phase 6.6 — legacy-route redirects per DECISIONS rows 61 + 62.
      // External triggers (system notification taps, share-target
      // intents) keep working without refactoring callers; new code
      // uses the canonical paths.
      if (state.matchedLocation == '/reminders') return '/home/reminders';
      if (state.matchedLocation == '/skills') return '/soul/guides';
      return null;
    },
    refreshListenable: notifier,
    routes: [
      // Full-screen flows (no bottom nav).
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/pets/add',
        builder: (context, state) => const AddPetScreen(),
      ),
      // Phase 7 task H.1.c — magic-link sign-in. Lives outside the
      // StatefulShellRoute so the user gets a focused full-screen
      // flow (no bottom nav distraction during a security-flavoured
      // moment). Auto-pops on signedIn event from the deep-link
      // return — see SignInScreen for the listener.
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      // Phase 7 task E.1 — paywall surfaces. Live OUTSIDE the
      // StatefulShellRoute (full-screen takeover; no bottom nav
      // while purchasing). Reached via `dispatchPaywall(...)` from
      // quota-hit dispatchers + Settings "Upgrade to Pro" link.
      GoRoute(
        path: '/paywall',
        builder: (context, state) => const PaywallScreen(),
        routes: [
          GoRoute(
            path: 'credits',
            builder: (context, state) => const PhotoCreditPackScreen(),
          ),
        ],
      ),
      // Phase 1 verification screen — exercises the full harness. Linked
      // from Home only in debug builds (see HomeScreen).
      GoRoute(
        path: '/dev',
        builder: (context, state) => const DevScreen(),
      ),

      // Bottom-nav shell — Home / Journal / Profile / Hub.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          // ─── Branch 0: Home ───────────────────────────────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
                routes: [
                  // Phase 6 task 6.6 — camera-as-memory capture flow.
                  // Reached from the home grid's "Add photo" tile
                  // (Phase 6.6.A.3 moves this to Quick Capture);
                  // launches camera-vs-gallery chooser on entry,
                  // displays the form-preview on pick.
                  // Phase 6 task 6.9 — `state.extra` may carry a
                  // `PhotoCapturePrefill` from the chat bubble's
                  // "Save as memory" affordance.
                  GoRoute(
                    path: 'photos/capture',
                    builder: (context, state) {
                      final extra = state.extra;
                      return PhotoCaptureScreen(
                        prefill: extra is PhotoCapturePrefill ? extra : null,
                      );
                    },
                  ),
                  // Phase 6.6 task 6.6.A.3 — Reminders moves under
                  // Home branch as a sub-page (DECISIONS row 61).
                  // Legacy `/reminders` redirects here.
                  GoRoute(
                    path: 'home/reminders',
                    builder: (context, state) => const RemindersScreen(),
                  ),
                ],
              ),
            ],
          ),

          // ─── Branch 1: Journal ────────────────────────────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/wiki',
                builder: (context, state) => const WikiBrowserScreen(),
                routes: [
                  // Phase 5.6 Commit C — `/wiki/entry` adopts a Material
                  // SharedAxisTransition (X axis) via `pageBuilder:`
                  // so tapping a journal entry from the wiki browser
                  // conveys "drilling deeper into the same content"
                  // rather than the default bottom-up slide. Other
                  // routes stay on PredictiveBackPageTransitionsBuilder
                  // (set in app_theme.dart's pageTransitionsTheme) for
                  // system back-gesture support.
                  GoRoute(
                    path: 'entry',
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
                        // CustomTransitionPage's default
                        // transitionDuration + reverseTransitionDuration
                        // are both 300 ms, equal to Motion.medium —
                        // leaving them at the default keeps the intent
                        // design-token-aligned without re-stating.
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
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
                ],
              ),
              // Phase 6 task 6.3 — dedicated photo timeline at
              // `/photos`. Reachable from the wiki browser's Photos
              // type-header "View all in timeline" link; from the home
              // grid camera CTA's post-save flow.
              // Phase 6.6 — lives under Journal branch (the timeline
              // is a journal-discovery surface, not a capture surface).
              GoRoute(
                path: '/photos',
                builder: (context, state) => const PhotoTimelineScreen(),
              ),
              // Phase 6 task 6.10 — vet-visit structured entry creator.
              // Form-driven; writes a structured-frontmatter entry to
              // wiki/<petId>/vet/<YYYY-MM-DD>-<reason>.md. Reachable
              // from the journal browser AppBar.
              GoRoute(
                path: '/vet/new',
                builder: (context, state) => const VetVisitFormScreen(),
              ),
            ],
          ),

          // ─── Branch 2: Profile ────────────────────────────────────
          // Phase 6.6 task 6.6.C.4 — `/soul` now renders the read-
          // only sectioned `ProfileViewScreen`; the existing form-
          // driven `SoulEditorScreen` lives at `/soul/edit` and is
          // reached via the AppBar pencil. Care guides at
          // `/soul/guides` (DECISIONS row 62).
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/soul',
                builder: (context, state) => const ProfileViewScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => const SoulEditorScreen(),
                  ),
                  GoRoute(
                    path: 'guides',
                    builder: (context, state) => const SkillBrowserScreen(),
                  ),
                ],
              ),
            ],
          ),

          // ─── Branch 3: Hub ────────────────────────────────────────
          // Hub uses sibling routes (not nested) for `/settings` and
          // `/about` so the deep-link paths stay top-level (DECISIONS
          // row 60 — `/settings` continuity for system deep-links and
          // share-target). go_router resolves `/settings` to this
          // branch, switching the active tab to Hub when reached.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/hub',
                builder: (context, state) => const HubScreen(),
              ),
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
              GoRoute(
                path: '/about',
                builder: (context, state) => const AboutScreen(),
              ),
            ],
          ),
        ],
      ),

      // Phase 6.6 — `/chat` lives outside the shell. Chat is per-pet,
      // full-screen, and the user reaches it from the Home greeting
      // CTA (`Chat with {pet}`). Putting it inside the shell would
      // either claim a tab slot it doesn't earn (DECISIONS row 59
      // rejected Chat-as-tab) or buried it as a Home sub-page that
      // erases the home CTA's primacy. Shell-less push preserves
      // today's UX while the bottom nav lands.
      GoRoute(
        path: '/chat',
        builder: (context, state) => const ChatScreen(),
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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import 'screens/dev_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';

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

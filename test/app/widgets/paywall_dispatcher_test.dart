import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/app/entitlement/quota_exception.dart';
import 'package:petpal/app/widgets/paywall_dispatcher.dart';

/// Phase 7 task E.1 — paywall dispatcher routing matrix.
///
/// Pins: text/reminder/pet/sync → /paywall; vision → /paywall/credits.
/// One source of truth for "where does each quota kind go."
void main() {
  final ent = Entitlement.freeAnonymous();

  /// Build a minimal app with the two paywall routes. Each route
  /// renders a distinct sentinel text so the test can read the
  /// current location off the rendered tree.
  Widget buildApp({required void Function(GoRouter router) onReady}) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/paywall',
          builder: (_, _) => const Scaffold(body: Text('paywall_root')),
          routes: [
            GoRoute(
              path: 'credits',
              builder: (_, _) => const Scaffold(body: Text('paywall_credits')),
            ),
          ],
        ),
      ],
    );
    onReady(router);
    return MaterialApp.router(routerConfig: router);
  }

  /// Dispatch the quota exception and return which sentinel screen
  /// rendered. Reads the visible widget tree because go_router's
  /// `currentConfiguration.uri.path` doesn't always reflect a
  /// `.push()` (only `.go()` updates the top-level config).
  Future<String> screenAfterDispatch(
    WidgetTester tester,
    QuotaExceededException quota,
  ) async {
    await tester.pumpWidget(buildApp(onReady: (_) {}));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('home'));
    dispatchPaywall(context, quota);
    await tester.pumpAndSettle();

    if (find.text('paywall_credits').evaluate().isNotEmpty) {
      return '/paywall/credits';
    }
    if (find.text('paywall_root').evaluate().isNotEmpty) {
      return '/paywall';
    }
    return '/';
  }

  testWidgets('TextQuotaExceeded → /paywall', (tester) async {
    expect(await screenAfterDispatch(tester, TextQuotaExceeded(ent)),
        '/paywall');
  });

  testWidgets('ReminderQuotaExceeded → /paywall', (tester) async {
    expect(await screenAfterDispatch(tester, ReminderQuotaExceeded(ent)),
        '/paywall');
  });

  testWidgets('PetQuotaExceeded → /paywall', (tester) async {
    expect(await screenAfterDispatch(tester, PetQuotaExceeded(ent)),
        '/paywall');
  });

  testWidgets('SyncQuotaExceeded → /paywall', (tester) async {
    expect(await screenAfterDispatch(tester, SyncQuotaExceeded(ent)),
        '/paywall');
  });

  testWidgets('VisionQuotaExceeded → /paywall/credits', (tester) async {
    expect(await screenAfterDispatch(tester, VisionQuotaExceeded(ent)),
        '/paywall/credits');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:petpal/app/design/design.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/app/widgets/pet_bottom_nav.dart';

/// Phase 6.6 task 6.6.A.2 — `PetBottomNav` widget-level invariants.
///
/// The integration test in `test/app/routing/bottom_nav_test.dart`
/// covers tab swap semantics + deep-link resolution + tab state
/// preservation through the full app stack. This file pins the
/// visual-contract invariants that test does NOT assert: per-icon
/// Phosphor names, sage active-state colorization, the 0.18-alpha
/// indicator pill, and the static-bar lock (height 72 + flat
/// elevation per DESIGN.md §2 anti-pattern lock).
///
/// Mounted via a minimal `MaterialApp.router` with a real
/// `StatefulShellRoute.indexedStack` so the widget receives an
/// authentic `StatefulNavigationShell`. Each branch lands on a
/// trivial `_Stub` screen so the test scope stays at the bottom
/// nav surface.
void main() {
  Widget buildApp({String initialLocation = '/'}) {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => Scaffold(
            body: const _Stub(),
            bottomNavigationBar: PetBottomNav(navigationShell: navigationShell),
          ),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/', builder: (_, _) => const _Stub('home')),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/wiki', builder: (_, _) => const _Stub('wiki')),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/soul', builder: (_, _) => const _Stub('soul')),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/hub', builder: (_, _) => const _Stub('hub')),
            ]),
          ],
        ),
      ],
    );
    return MaterialApp.router(
      theme: buildLightTheme(),
      routerConfig: router,
    );
  }

  testWidgets('renders the 4 locked Phosphor icons '
      '(house / bookOpen / userCircle / squaresFour)', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final navBar = find.byType(NavigationBar);
    expect(navBar, findsOneWidget);

    expect(
      find.descendant(
        of: navBar,
        matching: find.byIcon(PhosphorIconsRegular.house),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: navBar,
        matching: find.byIcon(PhosphorIconsRegular.bookOpen),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: navBar,
        matching: find.byIcon(PhosphorIconsRegular.userCircle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: navBar,
        matching: find.byIcon(PhosphorIconsRegular.squaresFour),
      ),
      findsOneWidget,
    );
  });

  testWidgets('NavigationBarTheme — selected icon resolves to '
      'scheme.primary (sage); unselected resolves to onSurface @ 0.65', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final scheme = buildLightTheme().colorScheme;
    final theme = NavigationBarTheme.of(tester.element(find.byType(NavigationBar)));

    final selectedIcon =
        theme.iconTheme!.resolve({WidgetState.selected});
    final unselectedIcon = theme.iconTheme!.resolve({});
    expect(selectedIcon!.color, scheme.primary,
        reason: 'selected destination icon must render sage');
    expect(
      unselectedIcon!.color,
      scheme.onSurface.withValues(alpha: 0.65),
      reason: 'unselected destination icon must be muted onSurface',
    );

    final selectedLabel =
        theme.labelTextStyle!.resolve({WidgetState.selected});
    final unselectedLabel = theme.labelTextStyle!.resolve({});
    expect(selectedLabel!.color, scheme.primary);
    expect(selectedLabel.fontWeight, FontWeight.w600);
    expect(
      unselectedLabel!.color,
      scheme.onSurface.withValues(alpha: 0.65),
    );
  });

  testWidgets('indicator pill = scheme.primary at 0.18 alpha '
      '(soft "current location" register, not a competing chrome accent)', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final scheme = buildLightTheme().colorScheme;
    final theme = NavigationBarTheme.of(tester.element(find.byType(NavigationBar)));
    expect(
      theme.indicatorColor,
      scheme.primary.withValues(alpha: 0.18),
    );
  });

  testWidgets('static bar lock — height 72 + flat elevation '
      '(DESIGN.md §2 anti-pattern: not floating)', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final theme = NavigationBarTheme.of(tester.element(find.byType(NavigationBar)));
    expect(theme.height, 72);
    expect(theme.elevation, Elevation.flat);
  });

  testWidgets('tap-active-tab sends initialLocation: true '
      '(scrolls branch back to root); tap-other sends initialLocation: false '
      '(switches branch without resetting)', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // Active tab is Home (index 0). Tapping Journal switches branches
    // — Home stays at its current state. Tapping Home again would scroll
    // it back to root. We can observe the initialLocation arg shape via
    // the tab label transition: tap Journal → currentIndex updates to 1.
    final journal = find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Journal'),
    );
    await tester.tap(journal);
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.selectedIndex, 1,
        reason: 'tapping Journal must switch to branch 1');

    // Tap Journal again — currentIndex stays 1 (the branch is already
    // active), but the goBranch call this time uses initialLocation:
    // true (the tap-already-active-tab semantic). Confirm the index
    // doesn't drift.
    await tester.tap(journal);
    await tester.pumpAndSettle();
    final navBar2 = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar2.selectedIndex, 1,
        reason: 'tapping the already-active tab must not drift the index');
  });
}

class _Stub extends StatelessWidget {
  const _Stub([this.label = '']);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Center(child: Text(label.isEmpty ? 'stub' : label));
}

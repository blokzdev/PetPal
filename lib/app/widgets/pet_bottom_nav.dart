import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design.dart';

/// Phase 6.6 task 6.6.A.2 — bottom navigation bar.
///
/// 4-tab structure per DECISIONS row 59: Home / Journal / Profile /
/// Hub. Phosphor regular-weight icons (`house` / `bookOpen` /
/// `userCircle` / `squaresFour`) per the locked icon mapping. Inter
/// labels (the global `TextTheme` applies; no special font slot).
/// Sage active state — selected destination's icon + label render in
/// `scheme.primary`; inactive in `onSurface@0.65`. Subtle sage pill
/// indicator behind the active icon (M3 `NavigationBar` default
/// shape, sage-tinted at 0.18 alpha — soft enough to read as
/// "current location" without competing with the rest of the chrome).
///
/// Static bar — not floating pill. DESIGN.md §2 anti-pattern lock
/// (floating skews Material You). The bar fills the full bottom
/// width, sits flush at the bottom edge, surface-tinted to match
/// the scaffold so it reads as a continuous chrome surface, not a
/// detached island.
///
/// Tap behaviour: `navigationShell.goBranch(index, initialLocation:
/// index == currentIndex)`. Tapping the already-active tab scrolls
/// the branch back to its root (`initialLocation: true`) — the
/// canonical "tap home tab again" pattern. Tapping a different tab
/// switches branches without disposing the inactive branches'
/// Navigators (state preservation per DECISIONS row 65).
class PetBottomNav extends StatelessWidget {
  const PetBottomNav({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        elevation: Elevation.flat,
        height: 72,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        // Selected = sage labelMedium; unselected = muted onSurface
        // labelMedium. Inter via the global `TextTheme`.
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            );
          }
          return textTheme.labelMedium?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.65),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
              color: scheme.primary,
              size: 24,
            );
          }
          return IconThemeData(
            color: scheme.onSurface.withValues(alpha: 0.65),
            size: 24,
          );
        }),
      ),
      child: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.house),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.bookOpen),
            label: 'Journal',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.userCircle),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.squaresFour),
            label: 'Hub',
          ),
        ],
      ),
    );
  }
}

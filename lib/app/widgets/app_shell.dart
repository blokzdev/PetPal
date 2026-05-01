import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
/// Verification of state preservation, deep-link semantics, and
/// back-stack behaviour lands at task 6.6.A.4.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  /// The active branch's Navigator. Built by go_router's
  /// `StatefulShellRoute.indexedStack` and handed to the shell at
  /// route resolution time.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: PetBottomNav(navigationShell: navigationShell),
    );
  }
}

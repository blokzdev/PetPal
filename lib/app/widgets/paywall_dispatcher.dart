import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../entitlement/quota_exception.dart';

/// Phase 7 task E.1 — paywall router.
///
/// Given a [QuotaExceededException], navigate to the right paywall
/// surface. Centralises the routing so callers (chat error bar,
/// add-pet "Compare plans" link, vision-blocked dispatch in E.1.b,
/// reminder-quota dispatch in E.1.b) all hit the same dispatcher.
///
/// Routing per Stage 1 decision #5 (hard wall + BYOK escape valve):
///   - Text quota → `/paywall` (full Pro upsell with VOICE.md §6
///     example 14 register)
///   - Vision quota → `/paywall/credits` (focused credit-pack
///     surface with VOICE.md §6 example 13 register)
///   - Reminder quota → `/paywall` (Pro unlocks unlimited
///     reminders; row 36 — BYOK does NOT lift this cap)
///   - Pet quota → `/paywall` (multi-pet is Pro UX gate; row 36)
///   - Sync quota → `/paywall` (sync is Pro-only feature gate)
///
/// All routes live OUTSIDE the StatefulShellRoute (full-screen
/// takeover; no bottom nav while purchasing). See `routing.dart`.
void dispatchPaywall(BuildContext context, QuotaExceededException e) {
  final route = switch (e) {
    VisionQuotaExceeded() => '/paywall/credits',
    TextQuotaExceeded() ||
    ReminderQuotaExceeded() ||
    PetQuotaExceeded() ||
    SyncQuotaExceeded() =>
      '/paywall',
  };
  GoRouter.of(context).push(route);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design.dart';
import '../entitlement/entitlement.dart';
import '../entitlement/quota_exception.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/paywall_dispatcher.dart';
import '../widgets/pet_card.dart';
import '../widgets/pet_section_header.dart';

/// App-wide settings. Phase 3.8 ships the weekly-summary toggle plus a
/// "Generate now" button so on-device verification can exercise the
/// synthesis runner without waiting a week. WorkManager-backed
/// scheduling lands in Phase 4.
///
/// Settings is a global screen → no pet-name interpolation in titles or
/// section labels (VOICE.md §5). Synthesis/digest is internal vocabulary;
/// the user sees "Weekly summary".
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _running = false;
  String? _runMessage;
  // Phase 6 task 6.14 — separate state for the monthly run so the
  // two surfaces don't share a spinner / outcome line.
  bool _monthlyRunning = false;
  String? _monthlyRunMessage;

  Future<void> _runDigest() async {
    setState(() {
      _running = true;
      _runMessage = null;
    });
    try {
      final pets = await ref.read(petsProvider.future);
      if (pets.isEmpty) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _runMessage = 'Add a pet first.';
        });
        return;
      }
      final runner = await ref.read(weeklyDigestRunnerProvider.future);
      final result = await runner.run(petId: pets.last.id);
      ref.invalidate(wikiEntriesProvider);
      if (!mounted) return;
      setState(() {
        _running = false;
        _runMessage = result.skipped
            ? 'Skipped: ${result.reason ?? 'no reason given'}'
            : "Saved this week's summary.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _runMessage = 'Failed: $e';
      });
    }
  }

  /// Phase 6 task 6.14 — manual trigger for the monthly health report.
  /// Mirrors `_runDigest` for now; Phase 7 wires it to a
  /// synthesisNotify-mode reminder firing once a month behind a Pro
  /// entitlement check.
  Future<void> _runMonthlyReport() async {
    setState(() {
      _monthlyRunning = true;
      _monthlyRunMessage = null;
    });
    try {
      final pets = await ref.read(petsProvider.future);
      if (pets.isEmpty) {
        if (!mounted) return;
        setState(() {
          _monthlyRunning = false;
          _monthlyRunMessage = 'Add a pet first.';
        });
        return;
      }
      final runner =
          await ref.read(monthlyReportRunnerProvider.future);
      final result = await runner.run(petId: pets.last.id);
      ref.invalidate(wikiEntriesProvider);
      if (!mounted) return;
      setState(() {
        _monthlyRunning = false;
        _monthlyRunMessage = result.skipped
            ? 'Skipped: ${result.reason ?? 'no reason given'}'
            : "Saved this month's report.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _monthlyRunning = false;
        _monthlyRunMessage = 'Failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final digestAsync = ref.watch(weeklyDigestEnabledProvider);
    final affectiveAsync =
        ref.watch(showAffectiveObservationsProvider);
    // Task 5.12 — section grouping. The screen has one functional
    // section today (Weekly summary). Promoting the section header
    // to PetSectionHeader (5.2 token) and grouping the rows in a
    // PetCard gives the screen a real "section" register that
    // future settings groups (BYOK, theme, sync — Phase 7) can
    // copy without re-deciding the visual treatment. The bespoke
    // surfaceContainerHigh band is gone — it competed with the
    // 5.1 dark warm-graphite surface and read flat.
    return AppScaffold(
      title: 'Settings',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.m,
          Spacing.s,
          Spacing.m,
          Spacing.l,
        ),
        children: [
          // Phase 7 task E.1.b — Plan section. Pro/free badge +
          // ambient text counter (free + BYOK only; Pro is
          // unmetered) + restore-purchases. VOICE.md §6 example 11
          // for the counter copy; §7 for the additive register.
          const PetSectionHeader(title: 'Plan'),
          const _PlanCard(),
          const SizedBox(height: Spacing.l),
          const PetSectionHeader(title: 'Weekly summary'),
          PetCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                digestAsync.when(
                  data: (enabled) => SwitchListTile(
                    title: const Text('Weekly summary'),
                    subtitle: const Text(
                      'Every Sunday, PetPal writes a recap of your '
                      "pet's week — what happened, what changed, "
                      'what to watch. Pro.',
                    ),
                    value: enabled,
                    onChanged: (next) async {
                      await ref
                          .read(weeklyDigestEnabledProvider.notifier)
                          .setEnabled(next);
                    },
                  ),
                  loading: () => const ListTile(
                    title: Text('Weekly summary'),
                    subtitle: Text('Loading…'),
                  ),
                  error: (e, _) => ListTile(
                    title: const Text('Weekly summary'),
                    subtitle: Text('Could not read setting: $e'),
                  ),
                ),
                const Divider(height: 1, thickness: 1, indent: 16),
                ListTile(
                  title: const Text("Generate this week's summary now"),
                  subtitle: Text(
                    _runMessage ??
                        "Generate your pet's summary right now, "
                            'instead of waiting for Sunday.',
                  ),
                  trailing: _running
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsRegular.play),
                  onTap: _running ? null : _runDigest,
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.l),
          // Phase 6 task 6.14 — monthly health report. Same surface
          // shape as the weekly digest but longer-arc. Manual-trigger
          // only in Phase 6; Phase 7 task 7.10 wires the
          // synthesisNotify-mode reminder behind the Pro paywall.
          const PetSectionHeader(title: 'Monthly health report'),
          PetCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              title: const Text('Generate this month\'s report now'),
              subtitle: Text(
                _monthlyRunMessage ??
                    'A longer-arc summary of the past 30 days — '
                        'weight curve, vet follow-ups, recurring '
                        'patterns, photo memory anchors. Pro.',
              ),
              trailing: _monthlyRunning
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(PhosphorIconsRegular.play),
              onTap: _monthlyRunning ? null : _runMonthlyReport,
            ),
          ),
          const SizedBox(height: Spacing.l),
          // Phase 6 task 6.8 — affective observations toggle. Default
          // ON per DECISIONS row 41 (e). Three compounding gates keep
          // the actual fire rate low (~1 per 20–30 saves) so default-
          // ON makes the warm moment surface for users who'd value
          // it without being intrusive.
          const PetSectionHeader(title: 'Photo observations'),
          PetCard(
            padding: EdgeInsets.zero,
            child: affectiveAsync.when(
              data: (enabled) => SwitchListTile(
                title: const Text('Show occasional observations'),
                subtitle: const Text(
                  'After you save a photo, PetPal might notice a '
                  'connection to a past memory — "looks more relaxed '
                  'than at the vet visit last month". Rare, never '
                  'medical. Off to mute.',
                ),
                value: enabled,
                onChanged: (next) async {
                  await ref
                      .read(showAffectiveObservationsProvider.notifier)
                      .set(next);
                },
              ),
              loading: () => const ListTile(
                title: Text('Show occasional observations'),
                subtitle: Text('Loading…'),
              ),
              error: (e, _) => ListTile(
                title: const Text('Show occasional observations'),
                subtitle: Text('Could not read setting: $e'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Phase 7 task E.1.b — Plan / billing card.
///
/// Surfaces the active entitlement state (Pro / Free / BYOK), the
/// VOICE.md §6 example 11 ambient text counter (free + BYOK only;
/// Pro is unmetered), and the Restore purchases trigger. The
/// "Upgrade to Pro" CTA dispatches to the paywall via
/// dispatchPaywall(TextQuotaExceeded(...)) — same routing as the
/// chat error CTA so future paywall layout changes land in one
/// place.
class _PlanCard extends ConsumerStatefulWidget {
  const _PlanCard();

  @override
  ConsumerState<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends ConsumerState<_PlanCard> {
  bool _restoring = false;

  Future<void> _restore() async {
    setState(() => _restoring = true);
    try {
      final service = await ref.read(billingServiceProvider.future);
      await service.restorePurchases();
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entitlement = ref.watch(entitlementProvider).maybeWhen(
          data: (e) => e,
          orElse: Entitlement.freeAnonymous,
        );
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PetCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // ── Plan badge row ───────────────────────────────────────
          ListTile(
            leading: Icon(
              entitlement.isPro
                  ? PhosphorIconsRegular.sparkle
                  : PhosphorIconsRegular.user,
              color: entitlement.isPro
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.6),
            ),
            title: Text(_planTitle(entitlement)),
            subtitle: Text(
              _planSubtitle(entitlement),
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            trailing: entitlement.isPro
                ? null
                : TextButton(
                    onPressed: () => dispatchPaywall(
                      context,
                      TextQuotaExceeded(entitlement),
                    ),
                    child: const Text('Upgrade'),
                  ),
          ),
          // ── Ambient text counter (free + BYOK; Pro is unmetered) ─
          // VOICE.md §6 example 11 + §7 principle #2: ambient
          // information, NOT a meter ticking down.
          if (entitlement.isTextMetered) ...[
            const Divider(height: 1, thickness: 1, indent: 16),
            ListTile(
              leading: Icon(
                PhosphorIconsRegular.chatCircle,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
              title: const Text('Monthly chat allowance'),
              subtitle: Text(
                _counterCopy(entitlement),
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ),
          ],
          // ── Restore purchases ────────────────────────────────────
          const Divider(height: 1, thickness: 1, indent: 16),
          ListTile(
            leading: Icon(
              PhosphorIconsRegular.arrowCounterClockwise,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
            title: const Text('Restore purchases'),
            subtitle: Text(
              'Recover your Pro subscription or care packs from a '
              'previous install.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            trailing: _restoring
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(PhosphorIconsRegular.caretRight),
            onTap: _restoring ? null : _restore,
          ),
        ],
      ),
    );
  }

  String _planTitle(Entitlement e) {
    switch (e.state) {
      case EntitlementState.proMonthly:
        return 'PetPal Pro · Monthly';
      case EntitlementState.proAnnual:
        return 'PetPal Pro · Annual';
      case EntitlementState.byok:
        return 'Free plan + BYOK';
      case EntitlementState.free:
      case EntitlementState.freeAnonymous:
        return 'Free plan';
    }
  }

  String _planSubtitle(Entitlement e) {
    switch (e.state) {
      case EntitlementState.proMonthly:
      case EntitlementState.proAnnual:
        final renewal = e.renewalDate;
        if (renewal == null) return 'Active.';
        return 'Renews ${_formatDate(renewal)}.';
      case EntitlementState.byok:
        return 'Your own Anthropic key handles chat — '
            "PetPal's monthly cap doesn't apply.";
      case EntitlementState.free:
      case EntitlementState.freeAnonymous:
        return 'Pro lifts every limit — chat, sync, photos, more.';
    }
  }

  /// VOICE.md §6 example 11 lock — ambient register.
  /// "PetPal handles 200 chats a month on the free plan. You've
  /// had 127 so far this month — plenty of room. Pro lifts the
  /// limit if you'd rather not think about it."
  String _counterCopy(Entitlement e) {
    final cap = e.textCap;
    if (cap == null) return 'Unmetered.';
    final count = e.monthlyTextCount;
    final remaining = cap - count;
    if (remaining > cap ~/ 4) {
      return 'PetPal handles $cap chats a month on the free plan. '
          "You've had $count so far this month — plenty of room. "
          "Pro lifts the limit if you'd rather not think about it.";
    }
    if (remaining > 0) {
      return 'PetPal handles $cap chats a month on the free plan. '
          "You've had $count so far this month, so $remaining left. "
          "Pro lifts the limit if you'd rather not think about it.";
    }
    return "You've used all $cap of this month's free chats. "
        'Pro lifts the limit, or switch to BYOK in Settings to '
        'keep chatting now.';
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

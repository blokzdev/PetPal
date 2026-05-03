import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../byok/byok_key_entry_sheet.dart';
import '../design/design.dart';
import '../entitlement/entitlement.dart';
import '../entitlement/entitlement_notifier.dart';
import '../entitlement/quota_exception.dart';
import '../providers.dart';
import '../sync/passphrase_setup_screen.dart';
import '../sync/sync_providers.dart';
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
          // Phase 7 task G.2 — sync section. Pro-gated; surfaces
          // the passphrase setup CTA pre-setup, the unlock CTA on
          // a fresh device, and a "sync now" button + last-sync
          // timestamp once unlocked. Live-status string keeps the
          // user grounded ("synced 3 minutes ago" / "passphrase
          // needed" / "Pro lifts sync").
          const PetSectionHeader(title: 'Sync'),
          const _SyncCard(),
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

    final petsAsync = ref.watch(petsProvider);
    final petCount = petsAsync.maybeWhen(
      data: (p) => p.length,
      orElse: () => 0,
    );

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
          // ── Pets row (Phase 7 task E.2) ──────────────────────────
          // Free / BYOK: "1 of 1 pet" register matches §7 principle
          // #1 (additive framing) without claiming the cap is
          // mean-spirited. Pro: just the count, no cap framing.
          if (petCount > 0) ...[
            const Divider(height: 1, thickness: 1, indent: 16),
            ListTile(
              leading: Icon(
                PhosphorIconsRegular.pawPrint,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
              title: Text(_petsRowTitle(entitlement, petCount)),
              subtitle: Text(
                _petsRowSubtitle(entitlement),
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ),
          ],
          // ── BYOK toggle (Phase 7 task F.1) ───────────────────────
          // VOICE.md §6 example 12 + DECISIONS row 74. Hidden for
          // Pro (Pro is already unmetered + adds sync; BYOK as a
          // cost-driven escape valve has no add-value for Pro).
          if (!entitlement.isPro) ...[
            const Divider(height: 1, thickness: 1, indent: 16),
            _ByokToggleTile(active: entitlement.state == EntitlementState.byok),
          ],
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

  /// Phase 7 task E.2 — pet-count row title.
  ///
  /// Free / BYOK ("$count of $cap pet[s]"): cap framing matches
  /// VOICE.md §6 example 11's ambient register — stating the cap
  /// without surveilling the user. Pro has no cap, so just count.
  String _petsRowTitle(Entitlement e, int count) {
    final cap = e.petCap;
    if (cap == null) {
      return count == 1 ? '1 pet' : '$count pets';
    }
    final petWord = cap == 1 ? 'pet' : 'pets';
    return '$count of $cap $petWord';
  }

  /// Phase 7 task E.2 — pet-count row subtitle. Pro keeps it
  /// ambient ("Add as many as you like"); free/BYOK names the
  /// limit + the additive Pro lift, never extractive (§7 #1).
  String _petsRowSubtitle(Entitlement e) {
    if (e.petCap == null) {
      return 'Add as many as you like.';
    }
    return 'Pro adds room for the rest of the household.';
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

/// Phase 7 task F.1 — Bring-your-own-key toggle row.
///
/// Lives inside the Plan card for free / BYOK users (Pro hides
/// it — Pro is unmetered without a key). Toggle ON opens
/// [showByokKeyEntrySheet] (format check + live ping per
/// DECISIONS row 74); toggle OFF prompts a confirmation dialog
/// before clearing the stored key + reverting entitlement state
/// to anonymous-free.
///
/// The switch's visible state mirrors `entitlement.state ==
/// byok` rather than the local Switch widget's own value — that
/// way an external state change (re-pump after migration,
/// settings sync) keeps the UI in sync.
class _ByokToggleTile extends ConsumerStatefulWidget {
  const _ByokToggleTile({required this.active});

  final bool active;

  @override
  ConsumerState<_ByokToggleTile> createState() => _ByokToggleTileState();
}

class _ByokToggleTileState extends ConsumerState<_ByokToggleTile> {
  bool _busy = false;

  Future<void> _handleChange(bool target) async {
    if (_busy) return;
    if (target) {
      setState(() => _busy = true);
      final ok = await showByokKeyEntrySheet(context);
      if (mounted) setState(() => _busy = false);
      // No state mutation here — the sheet calls
      // `setByokActive(active: true)` itself on success.
      // VOICE-rule: don't snackbar on cancel; users tap the
      // switch by mistake all the time.
      if (ok != true) return;
    } else {
      final confirm = await _confirmDisable(context);
      if (confirm != true) return;
      setState(() => _busy = true);
      try {
        await ref
            .read(entitlementProvider.notifier)
            .setByokActive(active: false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "BYOK off. Chat goes back to PetPal's monthly "
              'allowance.',
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't turn BYOK off: $e")),
        );
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<bool?> _confirmDisable(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn BYOK off?'),
        content: const Text(
          'Your stored API key will be removed from this phone. Chat '
          "will route through PetPal's monthly allowance again.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep BYOK on'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SwitchListTile(
      value: widget.active,
      onChanged: _busy ? null : _handleChange,
      secondary: Icon(
        widget.active
            ? Icons.key
            : Icons.key_off_outlined,
        color: scheme.onSurface.withValues(alpha: 0.6),
      ),
      title: const Text('Bring your own Anthropic key'),
      subtitle: Text(
        // VOICE.md §6 example 12 lock — additive register, honest
        // about what changes.
        widget.active
            ? "Your key handles chat — PetPal's monthly cap doesn't "
                'apply.'
            : "By default, PetPal handles the connection to Claude "
                "and includes a monthly chat allowance. Switch this "
                "on if you'd rather use your own Anthropic API key "
                "— your messages then go directly to Anthropic "
                "without passing through PetPal's servers, and the "
                "monthly limits don't apply.",
        style: textTheme.bodySmall?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.65),
        ),
      ),
      isThreeLine: true,
    );
  }
}

/// Phase 7 task G.2 — sync surface in Settings.
///
/// State machine driven by `syncUiStateProvider` +
/// `syncChallengeExistsProvider`. Five visible states match the
/// `SyncUiState` enum:
///
///   - `proLocked` — show the Pro-required nudge with a Compare
///     plans link routing through `dispatchPaywall`.
///   - `signedOut` — Pro user but no auth session yet (Group
///     H.1 ships sign-in). Shows a helpful "sign-in coming in a
///     later update" line so the user knows it's not their fault.
///   - `setupNeeded` — first device. CTA opens
///     `PassphraseSetupScreen`.
///   - `locked` — second device, challenge exists. CTA opens the
///     unlock sheet.
///   - `unlocked` — ready. Shows "Sync now" button + last-sync
///     timestamp (once a sync has run).
class _SyncCard extends ConsumerWidget {
  const _SyncCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncUiStateProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PetCard(
      padding: EdgeInsets.zero,
      child: switch (state) {
        SyncUiState.proLocked => ListTile(
            leading: Icon(
              PhosphorIconsRegular.cloudArrowUp,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
            title: const Text('Sync across devices'),
            subtitle: Text(
              'Pro mirrors your journal end-to-end encrypted across '
              "every device you sign in on.",
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            trailing: TextButton(
              onPressed: () => dispatchPaywall(
                context,
                SyncQuotaExceeded(
                  ref.read(entitlementProvider).valueOrNull ??
                      Entitlement.freeAnonymous(),
                ),
              ),
              child: const Text('Compare plans'),
            ),
          ),
        SyncUiState.signedOut => ListTile(
            leading: Icon(
              PhosphorIconsRegular.signIn,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
            title: const Text('Sign in to enable sync'),
            subtitle: Text(
              "Magic-link sign-in ships in a later update. Sync "
              "needs an account so your devices can find each other.",
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
        SyncUiState.setupNeeded => ListTile(
            leading: Icon(
              PhosphorIconsRegular.lock,
              color: scheme.primary,
            ),
            title: const Text('Set up sync'),
            subtitle: Text(
              "Pick a passphrase to encrypt your journal across "
              "devices. Only you can read it — PetPal can't.",
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            trailing: const Icon(PhosphorIconsRegular.caretRight),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PassphraseSetupScreen(),
                fullscreenDialog: true,
              ),
            ),
          ),
        SyncUiState.locked => ListTile(
            leading: Icon(
              PhosphorIconsRegular.lockKey,
              color: scheme.primary,
            ),
            title: const Text('Unlock sync'),
            subtitle: Text(
              "Enter the passphrase you set up on your other device.",
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            trailing: const Icon(PhosphorIconsRegular.caretRight),
            onTap: () => showPassphraseUnlockSheet(context),
          ),
        SyncUiState.unlocked => ListTile(
            leading: Icon(
              PhosphorIconsRegular.cloudCheck,
              color: scheme.primary,
            ),
            title: const Text('Sync is on'),
            subtitle: Text(
              "Your journal mirrors across your devices, end-to-end "
              "encrypted. PetPal can't read it.",
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
      },
    );
  }
}

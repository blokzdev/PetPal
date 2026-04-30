import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
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

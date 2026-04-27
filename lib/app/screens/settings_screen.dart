import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../widgets/app_scaffold.dart';

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

  @override
  Widget build(BuildContext context) {
    final digestAsync = ref.watch(weeklyDigestEnabledProvider);
    return AppScaffold(
      title: 'Settings',
      body: ListView(
        children: [
          const _SectionHeader(label: 'Weekly summary'),
          digestAsync.when(
            data: (enabled) => SwitchListTile(
              title: const Text('Weekly summary'),
              subtitle: const Text(
                "Every Sunday, PetPal writes a recap of your pet's "
                'week — what happened, what changed, what to watch. '
                'Pro.',
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
          ListTile(
            title: const Text("Generate this week's summary now"),
            subtitle: Text(
              _runMessage ??
                  "Generate your pet's summary right now, instead of "
                      'waiting for Sunday.',
            ),
            trailing: _running
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            onTap: _running ? null : _runDigest,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

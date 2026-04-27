import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/db/database.dart';
import '../../data/wiki_export.dart';
import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_button.dart';
import '../widgets/pet_empty_state.dart';

class WikiBrowserScreen extends ConsumerStatefulWidget {
  const WikiBrowserScreen({super.key});

  @override
  ConsumerState<WikiBrowserScreen> createState() =>
      _WikiBrowserScreenState();
}

class _WikiBrowserScreenState extends ConsumerState<WikiBrowserScreen> {
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final wiki = await ref.read(wikiIoProvider.future);
      final activePetId = ref.read(activePetIdProvider);
      final tempDir = await getTemporaryDirectory();
      final zip = await exportPetWikiAsZip(
        wiki: wiki,
        petId: activePetId(),
        outputDir: tempDir,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zip.path, mimeType: 'application/zip')],
          subject: 'PetPal journal export',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      appSnackBar(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(wikiEntriesProvider);
    // Per-pet destination → interpolate the active pet's name into the
    // app bar title (VOICE.md §5).
    final petsAsync = ref.watch(petsProvider);
    final petName = petsAsync.maybeWhen(
      data: (pets) => pets.isEmpty ? null : pets.last.name,
      orElse: () => null,
    );
    final title = petName == null ? 'Journal' : "$petName's journal";
    return AppScaffold.async<List<Entry>>(
      title: title,
      actions: [
        IconButton(
          tooltip: 'Export journal',
          onPressed: _exporting ? null : _export,
          icon: _exporting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.ios_share),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => ref.invalidate(wikiEntriesProvider),
          icon: const Icon(Icons.refresh),
        ),
      ],
      value: entriesAsync,
      onRetry: () => ref.invalidate(wikiEntriesProvider),
      data: (context, entries) => entries.isEmpty
          ? JournalEmptyForTesting(petName: petName)
          : _Tree(entries: entries, petName: petName),
    );
  }
}

/// Journal empty state — task 5.7 (locked option: narrative invitation).
/// Frames the journal as the moat-product, where Loki's life
/// accumulates over time. Concrete sensory examples sit inside the
/// prose rather than as a separate list, so the surface reads as
/// warm-companion, not marketing-bullets. Per VOICE.md §5 the body
/// interpolates the pet's name on a per-pet destination.
class JournalEmptyForTesting extends StatelessWidget {
  const JournalEmptyForTesting({super.key, required this.petName});
  final String? petName;

  @override
  Widget build(BuildContext context) {
    final heading = petName == null
        ? 'No memories yet.'
        : 'No memories about $petName yet.';
    final body = petName == null
        ? "This is where your pet's life will accumulate — vet "
            "visits, weight changes, the things you'd otherwise "
            "forget. Tell PetPal what's been happening, and "
            "they'll show up here."
        : "This is where $petName's life will accumulate — vet "
            "visits, weight changes, the things you'd otherwise "
            "forget. Tell PetPal what's been happening, and "
            "they'll show up here.";
    return PetEmptyState(
      icon: Icons.menu_book_outlined,
      heading: heading,
      body: body,
      action: PetButton(
        label: 'Open chat',
        onPressed: () => GoRouter.of(context).go('/chat'),
        icon: Icons.chat_bubble_outline,
      ),
    );
  }
}

class _Tree extends StatelessWidget {
  const _Tree({required this.entries, required this.petName});
  final List<Entry> entries;
  final String? petName;

  @override
  Widget build(BuildContext context) {
    final byType = <String, List<Entry>>{};
    for (final e in entries) {
      byType.putIfAbsent(e.type, () => []).add(e);
    }
    final sortedTypes = byType.keys.toList()..sort();
    return ListView(
      children: [
        for (final type in sortedTypes) ...[
          _TypeHeader(type: type, count: byType[type]!.length),
          for (final entry in byType[type]!)
            if (entry.type == 'digest')
              _DigestCard(entry: entry, petName: petName)
            else
              _EntryTile(entry: entry),
        ],
      ],
    );
  }
}

class _TypeHeader extends StatelessWidget {
  const _TypeHeader({required this.type, required this.count});
  final String type;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '$type · $count',
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final iso = '${entry.ts.year.toString().padLeft(4, '0')}-'
        '${entry.ts.month.toString().padLeft(2, '0')}-'
        '${entry.ts.day.toString().padLeft(2, '0')}';
    return ListTile(
      title: Text(entry.title),
      subtitle: Text(
        iso,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => GoRouter.of(context).push(
        '/wiki/entry',
        extra: entry.path,
      ),
    );
  }
}

/// Editorial card treatment for `type == 'digest'` entries — task 5.11
/// (user-locked: editorial register + "{pet}'s week" copy). The third
/// hero moment after 5.9 (memory-saved bloom) and 5.10 (per-pet home
/// greeting). Coheres with the family by leaning on the Source Serif 4
/// accent — 5.7's narrative empty state and 5.10's display-class name
/// also signal "this is journal, not utility."
///
/// Layout:
///   - Outer Material card in surfaceContainer (one tint above the list
///     surface) so the digest cluster reads as elevated copy without a
///     hard border. Margins match the surrounding ListTile rhythm.
///   - Top: small uppercase letter-spaced kicker ("WEEKLY DIGEST") in
///     onSurfaceVariant — magazine convention.
///   - Middle: title in Source Serif 4 via JournalText.weeklySummaryTitle
///     (the dedicated 5.1 token, sized one notch larger than per-entry
///     titles), name-interpolated. Reads as warm but not saccharine.
///   - Bottom: the date range derived from `entry.ts` (end-of-week per
///     WeeklyDigestRunner) minus six days for the window start, rendered
///     in bodyMedium onSurfaceVariant.
///
/// No body preview. The journal browser stays cheap (no per-row
/// wiki_io.read calls) and tapping the card opens the entry viewer
/// where the full markdown renders.
class _DigestCard extends StatelessWidget {
  const _DigestCard({required this.entry, required this.petName});
  final Entry entry;
  final String? petName;

  static const _monthAbbrev = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatRange(DateTime end) {
    final start = end.subtract(const Duration(days: 6));
    final startMonth = _monthAbbrev[start.month - 1];
    final endMonth = _monthAbbrev[end.month - 1];
    if (start.month == end.month) {
      return '$startMonth ${start.day}–${end.day}';
    }
    return '$startMonth ${start.day} – $endMonth ${end.day}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final subject = (petName == null || petName!.isEmpty)
        ? 'This'
        : "$petName's";
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.m,
        vertical: Spacing.s,
      ),
      child: Material(
        type: MaterialType.card,
        color: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.m),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => GoRouter.of(context).push(
            '/wiki/entry',
            extra: entry.path,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.l,
              vertical: Spacing.l,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WEEKLY DIGEST',
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  '$subject week',
                  style: JournalText.weeklySummaryTitle(
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  _formatRange(entry.ts),
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/db/database.dart';
import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/editorial_card.dart';
import '../widgets/pet_button.dart';
import '../widgets/pet_empty_state.dart';

/// Phase 6.6 task 6.6.A.3 — Export AppBar action removed (DECISIONS
/// row 60: Export relocated to Hub for IA-single-rooting). The
/// journal browser keeps the vet-visit creator action + the refresh
/// action; the refresh action's responsibility is local to the
/// browser, so it stays.
class WikiBrowserScreen extends ConsumerWidget {
  const WikiBrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(wikiEntriesProvider);
    // Per-pet destination → interpolate the active pet's name into the
    // app bar title (VOICE.md §5).
    final petsAsync = ref.watch(petsProvider);
    // Bug-2 defense: treat null AND empty/whitespace as the
    // "no-named-pet" case so we don't render "'s journal" with an
    // orphan apostrophe. The downstream `_Tree`, `_DigestCard`, and
    // empty-state widgets already check for null but were
    // partially missing the empty case.
    final petName = petsAsync.maybeWhen(
      data: (pets) {
        if (pets.isEmpty) return null;
        final name = pets.last.name.trim();
        return name.isEmpty ? null : name;
      },
      orElse: () => null,
    );
    final title = petName == null ? 'Journal' : "$petName's journal";
    return AppScaffold.async<List<Entry>>(
      title: title,
      actions: [
        // Phase 6 task 6.10 — log a structured vet-visit entry. The
        // form lives at /vet/new; saves a structured-frontmatter
        // markdown file under wiki/<petId>/vet/.
        IconButton(
          tooltip: 'Log a vet visit',
          onPressed: () => GoRouter.of(context).push('/vet/new'),
          icon: const Icon(PhosphorIconsRegular.firstAidKit),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => ref.invalidate(wikiEntriesProvider),
          icon: const Icon(PhosphorIconsRegular.arrowClockwise),
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
      icon: PhosphorIconsRegular.bookOpen,
      heading: heading,
      body: body,
      action: PetButton(
        label: 'Open chat',
        onPressed: () => GoRouter.of(context).go('/chat'),
        icon: PhosphorIconsRegular.chatCircle,
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

/// Map internal entry types to user-facing labels (VOICE.md §3 + §4).
/// `digest`, `wiki`, etc. are forbidden tokens in user-facing strings;
/// the journal browser's group headers go through this table.
String _humanTypeLabel(String type) {
  switch (type) {
    case 'digest':
      return 'Weekly summary';
    case 'vet':
      return 'Vet visits';
    case 'food':
      return 'Food';
    case 'weight':
      return 'Weight';
    case 'behavior':
      return 'Behavior';
    case 'photos':
      return 'Photos';
    default:
      // Unknown type → title-case the raw key as a graceful fallback
      // rather than showing a forbidden lowercase token.
      return type.isEmpty
          ? type
          : '${type[0].toUpperCase()}${type.substring(1)}';
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
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_humanTypeLabel(type)} · $count',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
          // Phase 6 task 6.3 — Photos type-header carries a link to
          // the dedicated grid timeline at `/photos`. Other type
          // headers stay header-only. Single touch-target; the
          // section header itself stays read-only / glance-only.
          if (type == 'photos')
            TextButton(
              onPressed: () => GoRouter.of(context).push('/photos'),
              child: const Text('View all'),
            ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final Entry entry;

  static const _monthAbbrev = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  String _kickerFor(Entry e) {
    final type = _humanTypeLabel(e.type).toUpperCase();
    final month = _monthAbbrev[e.ts.month - 1];
    return '$type · $month ${e.ts.day}';
  }

  @override
  Widget build(BuildContext context) {
    // Phase 6.6 task 6.6.B.2 — entry tile uses EditorialCard.
    // Kicker = "{TYPE} · {MON DAY}" (e.g. "FOOD · APR 25"); title =
    // entry.title; onTap routes to /wiki/entry. Body preview is not
    // wired for v1 (Entry rows don't carry body content; per-tile
    // disk reads would be expensive for the list). Coral left-
    // border on flagged entries lands in task 6.6.D.1 (the system-
    // wide coral wiring task), since the flagged signal lives in
    // the on-disk frontmatter (`red_flag_match`) and surfacing it
    // requires either a Drift index extension or a batched
    // sidecar read — both are scoped to D.1.
    return EditorialCard(
      kicker: _kickerFor(entry),
      title: entry.title,
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
/// Phase 6.6 task 6.6.B.4 — rebuilt to consume `EditorialCard`. The
/// digest card was the original ad-hoc editorial pattern (5.11);
/// productizing into `EditorialCard` lets the journal browser, home
/// recent memories, and weekly summary HIGHLIGHTS share one
/// primitive.
///
/// Locks preserved across the rebuild:
///   - Kicker = "WEEKLY SUMMARY" (small caps + letter-spacing).
///   - Title = "{pet}'s week" (or "This week" if no name) in
///     `JournalText.weeklySummaryTitle` register (~28pt serif).
///   - Body slot carries the date range "Apr 20–26" (mixed-case
///     month abbrev preserved — readable inside flowing prose; the
///     uppercased kicker carries the small-caps register above).
///   - InkWell tap routes to `/wiki/entry` with the digest path.
///
/// No body preview of the synthesised digest copy itself — the
/// journal browser stays cheap (no per-row wiki_io.read calls) and
/// tapping the card opens the entry viewer where the full markdown
/// renders.
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
    final subject = (petName == null || petName!.isEmpty)
        ? 'This'
        : "$petName's";
    return EditorialCard(
      kicker: 'WEEKLY SUMMARY',
      title: '$subject week',
      titleStyle: JournalText.weeklySummaryTitle(color: scheme.onSurface),
      body: _formatRange(entry.ts),
      onTap: () => GoRouter.of(context).push(
        '/wiki/entry',
        extra: entry.path,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/db/database.dart';
import '../active_pet/active_pet_notifier.dart';
import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/editorial_card.dart';
import '../widgets/pet_button.dart';
import '../widgets/pet_empty_state.dart';
import '../widgets/pet_switcher.dart';

/// Phase 6.6 task 6.6.A.3 — Export AppBar action removed (DECISIONS
/// row 60: Export relocated to Hub for IA-single-rooting). The
/// journal browser keeps the vet-visit creator action + the refresh
/// action; the refresh action's responsibility is local to the
/// browser, so it stays.
///
/// Phase 7 task E.2 — Stateful so the screen can hold a journal-
/// local view selection (`null` = cross-pet "All pets" timeline; a
/// pet ID = single-pet view). The switcher in the AppBar opens
/// the cross-pet sheet variant; selecting a real pet ALSO updates
/// the global active pet selection (so Home / Profile track the
/// user's intent across tabs). Selecting "All pets" stays
/// journal-local.
class WikiBrowserScreen extends ConsumerStatefulWidget {
  const WikiBrowserScreen({super.key});

  @override
  ConsumerState<WikiBrowserScreen> createState() => _WikiBrowserScreenState();
}

class _WikiBrowserScreenState extends ConsumerState<WikiBrowserScreen> {
  /// `null` = "All pets" cross-pet timeline; otherwise the pet ID
  /// being browsed. Initialized lazily from [activePetProvider] on
  /// the first build so navigating into Journal honours the user's
  /// global active pet, but staying inside Journal preserves their
  /// view choice (including "All pets").
  int? _selectedPetId;
  bool _initialized = false;

  Future<void> _openSwitcher(BuildContext context) async {
    final current = _selectedPetId == null
        ? const PickedAllPets()
        : PickedPet(_selectedPetId!);
    final choice = await showPetSwitcherSheet(
      context,
      currentSelection: current,
      includeAllPets: true,
    );
    if (choice == null) return;
    if (choice is PickedAllPets) {
      setState(() => _selectedPetId = null);
    } else if (choice is PickedPet) {
      setState(() => _selectedPetId = choice.petId);
      // Sync the global active pet so Home / Profile follow.
      await ref
          .read(activePetSelectionProvider.notifier)
          .select(choice.petId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePet = ref.watch(activePetProvider);
    if (!_initialized && activePet != null) {
      _selectedPetId = activePet.id;
      _initialized = true;
    }
    final petsAsync = ref.watch(petsProvider);

    final entriesAsync = ref.watch(journalEntriesProvider(_selectedPetId));
    final selectedPetName = petsAsync.maybeWhen(
      data: (pets) {
        if (_selectedPetId == null) return null;
        for (final p in pets) {
          if (p.id == _selectedPetId) {
            final n = p.name.trim();
            return n.isEmpty ? null : n;
          }
        }
        return null;
      },
      orElse: () => null,
    );
    final title = _selectedPetId == null
        ? 'All pets · journal'
        : (selectedPetName == null
            ? 'Journal'
            : "$selectedPetName's journal");

    return AppScaffold.async<List<Entry>>(
      title: title,
      titleWidget: _JournalSwitcherTitle(
        title: title,
        onTap: () => _openSwitcher(context),
      ),
      actions: [
        IconButton(
          tooltip: 'Log a vet visit',
          onPressed: () => GoRouter.of(context).push('/vet/new'),
          icon: const Icon(PhosphorIconsRegular.firstAidKit),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () =>
              ref.invalidate(journalEntriesProvider(_selectedPetId)),
          icon: const Icon(PhosphorIconsRegular.arrowClockwise),
        ),
      ],
      value: entriesAsync,
      onRetry: () =>
          ref.invalidate(journalEntriesProvider(_selectedPetId)),
      data: (context, entries) => entries.isEmpty
          ? JournalEmptyForTesting(petName: selectedPetName)
          : _Tree(
              entries: entries,
              petName: selectedPetName,
              isAllPets: _selectedPetId == null,
              petsById: petsAsync.maybeWhen(
                data: (list) => {for (final p in list) p.id: p},
                orElse: () => const <int, Pet>{},
              ),
            ),
    );
  }
}

/// Phase 7 task E.2 — Journal AppBar title.
///
/// Hidden chevron + tappable title. Always shows the chevron because
/// the Journal is the one surface where "All pets" mode is reachable
/// — even single-pet households need a way to flip back from the
/// cross-pet view, which means the affordance must be visible.
class _JournalSwitcherTitle extends ConsumerWidget {
  const _JournalSwitcherTitle({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final petsAsync = ref.watch(petsProvider);
    final petCount = petsAsync.maybeWhen(
      data: (pets) => pets.length,
      orElse: () => 0,
    );
    if (petCount <= 1) {
      // Solo-pet user — no other pet to switch to and "All pets"
      // would just mirror the single pet's view. Hide the
      // affordance to keep the AppBar clean.
      return Text(title);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: Corners.s,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: Spacing.xs),
            const Icon(PhosphorIconsRegular.caretDown, size: 16),
          ],
        ),
      ),
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
    // Phase 6.6 task 6.6.C.5 — Stitch register: pet-name-first
    // present-fact + warm reframe ("the journal begins"). Per-pet
    // destination, so VOICE.md §5 interpolation applies.
    final heading = petName == null
        ? "Your pet's journal hasn't begun yet."
        : "$petName's journal hasn't begun yet.";
    final body = petName == null
        ? "Tell PetPal what's been happening — vet visits, weight "
            'changes, small wins — and the journal builds itself '
            'here.'
        : "Tell PetPal what's been happening — vet visits, weight "
            'changes, small wins — and the journal builds itself '
            'here.';
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
  const _Tree({
    required this.entries,
    required this.petName,
    this.isAllPets = false,
    this.petsById = const <int, Pet>{},
  });
  final List<Entry> entries;
  final String? petName;
  // Phase 7 task E.2 — when true, the tree renders flat (no
  // by-type grouping) and prefixes each card's kicker with the
  // pet's name. The "All pets" timeline is interleaved by `ts`
  // desc so the user reads a household-wide chronological feed.
  final bool isAllPets;
  final Map<int, Pet> petsById;

  @override
  Widget build(BuildContext context) {
    if (isAllPets) {
      return ListView(
        children: [
          for (final entry in entries)
            if (entry.type == 'digest')
              _DigestCard(
                entry: entry,
                petName: petsById[entry.petId]?.name,
                petPrefix: petsById[entry.petId]?.name,
              )
            else
              _EntryTile(
                entry: entry,
                petPrefix: petsById[entry.petId]?.name,
              ),
        ],
      );
    }
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
  const _EntryTile({required this.entry, this.petPrefix});
  final Entry entry;
  /// Phase 7 task E.2 — non-null in "All pets" mode; prepended to
  /// the kicker so the cross-pet timeline stays scannable
  /// ("LOKI · VET · APR 22" instead of just "VET · APR 22").
  final String? petPrefix;

  static const _monthAbbrev = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  String _kickerFor(Entry e) {
    final type = _humanTypeLabel(e.type).toUpperCase();
    final month = _monthAbbrev[e.ts.month - 1];
    final prefix = petPrefix?.trim();
    if (prefix != null && prefix.isNotEmpty) {
      return '${prefix.toUpperCase()} · $type · $month ${e.ts.day}';
    }
    return '$type · $month ${e.ts.day}';
  }

  @override
  Widget build(BuildContext context) {
    // Phase 6.6 task 6.6.B.2 — entry tile uses EditorialCard.
    // Kicker = "{TYPE} · {MON DAY}" (e.g. "FOOD · APR 25"); title =
    // entry.title; onTap routes to /wiki/entry.
    //
    // Phase 6.6 task 6.6.D.1 — vet entries carry the coral
    // medical-attention register at the card level (DECISIONS row
    // 64). Surfacing the per-frontmatter `red_flag_match` signal on
    // every tile would require a Drift schema extension or a
    // batched sidecar read; the type-based heuristic is the
    // pragmatic v1 — vet entries are inherently medical context, so
    // 'all vet entries get coral' lines up with the system register
    // without a migration. Photo entries with `red_flag_match`
    // surface the marker via RedFlagBadge inside the entry view
    // (also coral via D.1).
    return EditorialCard(
      kicker: _kickerFor(entry),
      title: entry.title,
      flagged: entry.type == 'vet',
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
  const _DigestCard({
    required this.entry,
    required this.petName,
    this.petPrefix,
  });
  final Entry entry;
  final String? petName;
  /// Phase 7 task E.2 — non-null in "All pets" mode; prepended to
  /// the digest kicker so a cross-pet weekly summary card carries
  /// its pet's name even though the title body still reads
  /// "{pet}'s week".
  final String? petPrefix;

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
    final kickerPrefix = petPrefix?.trim();
    final kicker = (kickerPrefix != null && kickerPrefix.isNotEmpty)
        ? '${kickerPrefix.toUpperCase()} · WEEKLY SUMMARY'
        : 'WEEKLY SUMMARY';
    return EditorialCard(
      kicker: kicker,
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

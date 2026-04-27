import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/db/database.dart';
import '../../data/wiki_export.dart';
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
          : _Tree(entries: entries),
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
  const _Tree({required this.entries});
  final List<Entry> entries;

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

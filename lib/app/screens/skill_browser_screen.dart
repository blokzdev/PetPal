import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// Skill browser. Shows every bundled skill applicable to the active
/// pet's species, with an enable/disable toggle per row. Species filter
/// is enforced here so a cat owner doesn't see a "Senior Dog Care"
/// skill they can never use (CLAUDE.md §3 — only species-aware path).
class SkillBrowserScreen extends ConsumerWidget {
  const SkillBrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(skillCatalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Skills')),
      body: catalogAsync.when(
        data: (entries) =>
            entries.isEmpty ? const _Empty() : _SkillList(entries: entries),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load skills: $e')),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No skills available for this pet. Skills are filtered to '
          "your pet's species.",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _SkillList extends ConsumerWidget {
  const _SkillList({required this.entries});
  final List<SkillCatalogEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = entries[i];
        return SwitchListTile(
          title: Text(e.manifest.name),
          subtitle: Text(
            'Triggers: ${e.manifest.triggers.take(3).join(", ")}'
            '${e.manifest.triggers.length > 3 ? "…" : ""}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          value: e.enabled,
          onChanged: (next) async {
            final repo = await ref.read(skillRepoProvider.future);
            await repo.setEnabled(
              skillId: e.manifest.id,
              version: e.manifest.version,
              enabled: next,
            );
            ref.invalidate(skillCatalogProvider);
            ref.invalidate(filteredSkillSourceProvider);
            ref.invalidate(skillLoaderProvider);
          },
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_empty_state.dart';

/// Care guides browser. Shows every bundled guide applicable to the
/// active pet's category, with an enable/disable toggle per row.
/// Category filter is enforced here so a cat owner doesn't see a "Senior
/// Dog Care" guide they could never use (CLAUDE.md §3 — only
/// category-aware path). Global screen → no pet name in the app bar
/// (VOICE.md §5).
class SkillBrowserScreen extends ConsumerWidget {
  const SkillBrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(skillCatalogProvider);
    return AppScaffold.async<List<SkillCatalogEntry>>(
      title: 'Care guides',
      value: catalogAsync,
      onRetry: () => ref.invalidate(skillCatalogProvider),
      data: (context, entries) =>
          entries.isEmpty ? const CareGuidesEmptyForTesting() : _SkillList(entries: entries),
    );
  }
}

/// Care guides empty state — global screen, no pet-name interpolation
/// (VOICE.md §5). Static copy, no CTA: the user can't author a guide
/// from inside PetPal in v1, and waiting for more bundled packs is
/// the only legitimate path forward.
class CareGuidesEmptyForTesting extends StatelessWidget {
  const CareGuidesEmptyForTesting({super.key});

  @override
  Widget build(BuildContext context) {
    // Phase 6.6 task 6.6.C.5 — Stitch register, global variant
    // (no name interpolation per VOICE.md §5 — this is a
    // cross-pet screen). Present-fact + how-it-works reframe.
    return const PetEmptyState(
      icon: PhosphorIconsRegular.bookOpen,
      heading: 'Care guides are quiet for now.',
      body: "They activate during chat — mention 'puppy' or "
          "'senior cat' and the right one shows up. More guides "
          'land in updates.',
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
            'Activates when you mention '
            '${e.manifest.triggers.take(3).join(", ")}'
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

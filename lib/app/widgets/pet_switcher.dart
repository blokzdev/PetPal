import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/db/database.dart';
import '../../data/pet_name.dart';
import '../active_pet/active_pet_notifier.dart';
import '../design/design.dart';
import '../providers.dart';

/// Phase 7 task E.2 — pet switcher.
///
/// One affordance, three usages:
///
///   1. **Home / Profile / Journal AppBars** drop in [PetSwitcherTitle]
///      as their `titleWidget`. The pet name renders inline with a
///      tiny chevron; tapping opens the bottom sheet. Single-pet
///      surfaces hide the chevron and the tap target — there's
///      nowhere to switch to.
///
///   2. **Journal** opts in to the cross-pet "All pets" entry by
///      passing `includeAllPets: true`. Selecting "All pets" returns
///      [PickedAllPets] from [showPetSwitcherSheet]; selecting a
///      single pet returns [PickedPet]. The screen interprets these
///      and updates its local view (real-pet selections also push
///      the global active-pet selection so the rest of the app
///      tracks the user's intent across tabs).
///
///   3. **Reminders' "Add reminder" FAB** uses the sheet directly
///      (not the AppBar title) when the user has multiple pets, to
///      ask which pet the reminder is for.
///
/// Sheet always offers an "Add pet" tile that opens `/pets/add`
/// (existing route — D.1's pet-cap gate handles the paywall
/// dispatch on free tier). The sheet closes itself before
/// navigating; callers don't need to handle "Add pet" specially
/// — they just see a dismissed sheet.

sealed class PetSwitcherChoice {
  const PetSwitcherChoice();
}

final class PickedPet extends PetSwitcherChoice {
  const PickedPet(this.petId);
  final int petId;
}

final class PickedAllPets extends PetSwitcherChoice {
  const PickedAllPets();
}

/// Open the pet switcher bottom sheet. Returns `null` if the sheet
/// was dismissed without a selection. Returns [PickedAllPets] when
/// the user selected the cross-pet entry (only available when the
/// caller passed `includeAllPets: true`). Returns [PickedPet]
/// otherwise.
///
/// The sheet handles its own "Add pet" routing — the caller just
/// sees `null` if the user tapped that tile.
Future<PetSwitcherChoice?> showPetSwitcherSheet(
  BuildContext context, {
  required PetSwitcherChoice currentSelection,
  bool includeAllPets = false,
}) {
  return showModalBottomSheet<PetSwitcherChoice>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => _PetSwitcherSheet(
      currentSelection: currentSelection,
      includeAllPets: includeAllPets,
    ),
  );
}

/// AppBar title widget that surfaces the active pet's name plus a
/// switch chevron. Tap opens the bottom sheet; selecting a pet
/// updates the global [activePetSelectionProvider]. Selecting "All
/// pets" is rejected here (the title's identity is a single pet) —
/// callers wanting that entry should use [showPetSwitcherSheet]
/// directly.
///
/// `titleBuilder` lets each tab render its own per-pet copy
/// ("Loki" on Home; "Loki's journal" on Journal; "Loki's profile"
/// on Profile). The fallback (no pet, or whitespace name) renders
/// `fallbackTitle` and hides the chevron.
class PetSwitcherTitle extends ConsumerWidget {
  const PetSwitcherTitle({
    super.key,
    required this.titleBuilder,
    required this.fallbackTitle,
  });

  final String Function(Pet pet) titleBuilder;
  final String fallbackTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pet = ref.watch(activePetProvider);
    final petsAsync = ref.watch(petsProvider);
    final petCount = petsAsync.maybeWhen(
      data: (pets) => pets.length,
      orElse: () => 0,
    );

    if (pet == null) {
      return Text(fallbackTitle);
    }
    final title = titleBuilder(pet);
    final canSwitch = petCount > 1;

    if (!canSwitch) {
      return Text(title);
    }

    // Phase 7 task H.2.b — the InkWell wraps a Text title with a
    // decorative chevron icon. TalkBack would otherwise read this as
    // "title text, button" with no hint that the action switches pets.
    // `MergeSemantics` collapses the row's two children into a single
    // semantics node; the wrapping `Semantics(button: true, ...)` makes
    // it announce as a button with a clear "Switch pet" hint.
    return Semantics(
      button: true,
      label: title,
      hint: 'Switch pet',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _openSheet(context, ref, pet.id),
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
      ),
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    WidgetRef ref,
    int currentPetId,
  ) async {
    final choice = await showPetSwitcherSheet(
      context,
      currentSelection: PickedPet(currentPetId),
    );
    if (choice is PickedPet && choice.petId != currentPetId) {
      await ref.read(activePetSelectionProvider.notifier).select(choice.petId);
    }
  }
}

class _PetSwitcherSheet extends ConsumerWidget {
  const _PetSwitcherSheet({
    required this.currentSelection,
    required this.includeAllPets,
  });

  final PetSwitcherChoice currentSelection;
  final bool includeAllPets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final petsAsync = ref.watch(petsProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: petsAsync.when(
        data: (pets) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.l,
                Spacing.s,
                Spacing.l,
                Spacing.s,
              ),
              child: Text(
                'Switch pet',
                style: textTheme.titleMedium,
              ),
            ),
            if (includeAllPets) ...[
              _AllPetsTile(
                selected: currentSelection is PickedAllPets,
              ),
              const Divider(height: 1, indent: Spacing.l),
            ],
            for (final p in pets)
              _PetTile(
                pet: p,
                selected: currentSelection is PickedPet &&
                    (currentSelection as PickedPet).petId == p.id,
              ),
            const Divider(height: 1, indent: Spacing.l),
            ListTile(
              leading: Icon(
                PhosphorIconsRegular.plus,
                color: scheme.primary,
              ),
              title: Text(
                'Add pet',
                style: textTheme.bodyLarge?.copyWith(color: scheme.primary),
              ),
              onTap: () {
                Navigator.of(context).pop();
                GoRouter.of(context).push('/pets/add');
              },
            ),
            const SizedBox(height: Spacing.s),
          ],
        ),
        loading: () => const Padding(
          padding: EdgeInsets.all(Spacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(Spacing.l),
          child: Text("Couldn't load your pets: $e"),
        ),
      ),
    );
  }
}

class _PetTile extends StatelessWidget {
  const _PetTile({required this.pet, required this.selected});

  final Pet pet;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.surfaceContainerHigh,
        child: Icon(
          PhosphorIconsRegular.pawPrint,
          size: 18,
          color: scheme.primary.withValues(alpha: 0.7),
        ),
      ),
      title: Text(displayPetName(pet.name)),
      trailing: selected
          ? Icon(PhosphorIconsRegular.check, color: scheme.primary)
          : null,
      onTap: () => Navigator.of(context).pop(PickedPet(pet.id)),
    );
  }
}

class _AllPetsTile extends StatelessWidget {
  const _AllPetsTile({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.surfaceContainerHigh,
        child: Icon(
          PhosphorIconsRegular.pawPrint,
          size: 18,
          color: scheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      title: const Text('All pets'),
      subtitle: const Text('Cross-pet timeline'),
      trailing: selected
          ? Icon(PhosphorIconsRegular.check, color: scheme.primary)
          : null,
      onTap: () => Navigator.of(context).pop(const PickedAllPets()),
    );
  }
}

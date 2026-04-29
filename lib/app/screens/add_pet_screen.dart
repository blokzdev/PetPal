import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/onboarding_templates.dart';
import '../../data/relationship.dart';
import '../../data/species_catalog.dart';
import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_card.dart';
import '../widgets/pet_section_header.dart';
import '../widgets/species_picker_sheet.dart';

/// Add-pet flow. Phase 5.5.3 lands the curated species picker on top of
/// the existing category dropdown — user picks Category first, then taps
/// Species to open the bottom-sheet picker (DECISIONS rows 42, 46, 48 +
/// 5.5.3 design lock). Tier 1 species (Dog / Cat / Rabbit / Guinea Pig
/// / Chicken) reveal a secondary breed picker; non-Tier-1 species fall
/// through to a freeform breed text field.
///
/// Add-pet is a global action (not a per-pet destination) so the limit
/// copy stays static — no name interpolation (VOICE.md §5).
class AddPetScreen extends ConsumerStatefulWidget {
  const AddPetScreen({super.key});

  @override
  ConsumerState<AddPetScreen> createState() => _AddPetScreenState();
}

class _AddPetScreenState extends ConsumerState<AddPetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _breed = TextEditingController();
  final _otherSpecies = TextEditingController();
  Category _category = Category.dog;

  /// The picked species — null means user hasn't picked yet, special
  /// "Other" sentinel handled via [_isOtherSpecies].
  SpeciesEntry? _species;

  /// True when the user picked "Other (type your own)" and entered a
  /// freeform species name in [_otherSpecies]. Mutually exclusive with
  /// [_species].
  bool _isOtherSpecies = false;

  /// The picked breed for Tier 1 species — null if not picked or not
  /// applicable. Special "Other" handling stores freeform text in
  /// [_breed].
  BreedEntry? _breedEntry;

  /// Relationship picker state — DECISIONS row 44. Always shown to
  /// every user with `pet` pre-selected.
  Relationship _relationship = Relationship.pet;

  /// Sub-classification per DECISIONS row 47. Defaults to `none`,
  /// omitted from disk by renderTemplate's strip-empty pass.
  WorkingRole _workingRole = WorkingRole.none;
  RehabContext _rehabContext = RehabContext.none;
  CareContext _careContext = CareContext.none;

  DateTime? _dob;
  bool _saving = false;
  String? _saveError;

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _otherSpecies.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 2, now.month, now.day),
      firstDate: DateTime(now.year - 30),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _pickSpecies() async {
    final catalog = ref.read(speciesCatalogProvider);
    final result = await showSpeciesPickerSheet(
      context,
      catalog: catalog,
      category: _category.id,
    );
    if (result == null) return;
    setState(() {
      if (result.isOther) {
        _species = null;
        _isOtherSpecies = true;
        _breedEntry = null;
      } else {
        _species = result.entry;
        _isOtherSpecies = false;
        _breedEntry = null; // re-pick required when species changes
      }
    });
  }

  Future<void> _pickBreed() async {
    final breeds = _species?.breeds;
    if (breeds == null) return;
    final result = await showBreedPickerSheet(context, breeds: breeds);
    if (result == null) return;
    setState(() {
      if (result.isOther) {
        _breedEntry = null;
        _breed.clear();
      } else {
        _breedEntry = result.breed;
        _breed.text = result.breed!.name;
      }
    });
  }

  String? _resolvedSpeciesValue() {
    if (_isOtherSpecies) {
      final txt = _otherSpecies.text.trim();
      return txt.isEmpty ? null : txt;
    }
    return _species?.displayName;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final repo = await ref.read(petRepoProvider.future);
      final templates = ref.read(onboardingTemplatesProvider);
      final breed = _breed.text.trim().isEmpty ? null : _breed.text.trim();
      final speciesValue = _resolvedSpeciesValue();
      final seedSoul = await templates.seedSoulFor(
        category: _category,
        name: _name.text.trim(),
        species: speciesValue,
        breed: breed,
        relationship: _relationship,
        workingRole: _workingRole,
        rehabContext: _rehabContext,
        careContext: _careContext,
        dob: _dob,
      );
      await repo.createPet(
        name: _name.text.trim(),
        category: _category.id,
        species: speciesValue,
        breed: breed,
        dob: _dob,
        seedSoul: seedSoul,
      );
      ref.invalidate(petsProvider);
      if (mounted) context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dobLabel = _dob == null
        ? 'Date of birth (optional)'
        : 'Date of birth: ${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}';
    final petsAsync = ref.watch(petsProvider);
    final atLimit = petsAsync.maybeWhen(
      data: (pets) => pets.isNotEmpty,
      orElse: () => false,
    );
    if (atLimit) {
      return const AppScaffold(
        title: 'Add a pet',
        body: _FreeTierLimit(),
      );
    }
    return AppScaffold(
      title: 'Add a pet',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Category>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in Category.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (c) {
                  if (c != null) {
                    setState(() {
                      _category = c;
                      _species = null; // species pick is category-scoped
                      _isOtherSpecies = false;
                      _breedEntry = null;
                      _breed.clear();
                      _otherSpecies.clear();
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              _SpeciesField(
                species: _species,
                isOtherSpecies: _isOtherSpecies,
                onTap: _pickSpecies,
              ),
              if (_isOtherSpecies) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _otherSpecies,
                  decoration: const InputDecoration(
                    labelText: 'Type the species',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
              ],
              const SizedBox(height: 16),
              if (_species?.hasBreeds ?? false) ...[
                _BreedField(
                  breed: _breedEntry,
                  onTap: _pickBreed,
                ),
                if (_breed.text.isEmpty || _breedEntry == null) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _breed,
                    decoration: const InputDecoration(
                      labelText: 'Or type the breed',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ] else ...[
                TextFormField(
                  controller: _breed,
                  decoration: const InputDecoration(
                    labelText: 'Variety (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: Spacing.l),
              _RelationshipCard(
                value: _relationship,
                onChanged: (r) {
                  setState(() {
                    _relationship = r;
                    // Reset sub-classification on relationship change so
                    // a stale picker value doesn't sneak through to disk.
                    _workingRole = WorkingRole.none;
                    _rehabContext = RehabContext.none;
                    _careContext = CareContext.none;
                  });
                },
              ),
              const SizedBox(height: Spacing.s),
              AnimatedSwitcher(
                duration: Motion.short,
                child: _SubClassificationField(
                  key: ValueKey(_relationship),
                  relationship: _relationship,
                  workingRole: _workingRole,
                  rehabContext: _rehabContext,
                  careContext: _careContext,
                  onWorkingRoleChanged: (r) =>
                      setState(() => _workingRole = r),
                  onRehabContextChanged: (r) =>
                      setState(() => _rehabContext = r),
                  onCareContextChanged: (r) =>
                      setState(() => _careContext = r),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _pickDob,
                icon: const Icon(Icons.calendar_today),
                label: Text(dobLabel),
              ),
              const SizedBox(height: 24),
              if (_saveError != null) ...[
                Text(
                  _saveError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeciesField extends StatelessWidget {
  const _SpeciesField({
    required this.species,
    required this.isOtherSpecies,
    required this.onTap,
  });

  final SpeciesEntry? species;
  final bool isOtherSpecies;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = species?.displayName ??
        (isOtherSpecies ? 'Other (type below)' : 'Tap to pick a species');
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Species',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.search),
        ),
        child: Text(
          label,
          style: species == null && !isOtherSpecies
              ? theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _BreedField extends StatelessWidget {
  const _BreedField({required this.breed, required this.onTap});

  final BreedEntry? breed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = breed?.name ?? 'Tap to pick a breed';
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Breed',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.search),
        ),
        child: Text(
          label,
          style: breed == null
              ? theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// Relationship card — DECISIONS row 44 + 5.5.4 design D5=C lock. Renders
/// the "Relationship" section header inside a [PetCard] with four
/// inline radio rows. Always visible; `pet` is pre-selected by the
/// parent state. The four values are surfaced verbatim from the
/// [Relationship] enum so the picker stays in sync with the lock.
class _RelationshipCard extends StatelessWidget {
  const _RelationshipCard({
    required this.value,
    required this.onChanged,
  });

  final Relationship value;
  final ValueChanged<Relationship> onChanged;

  @override
  Widget build(BuildContext context) {
    return PetCard(
      padding: EdgeInsets.zero,
      child: RadioGroup<Relationship>(
        groupValue: value,
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PetSectionHeader(title: 'Relationship'),
            for (final r in Relationship.values)
              RadioListTile<Relationship>(
                title: Text(r.label),
                value: r,
                dense: true,
              ),
          ],
        ),
      ),
    );
  }
}

/// Sub-classification picker shown beneath [_RelationshipCard]. Renders
/// the role/context picker that pairs with the active relationship per
/// DECISIONS row 47 (working_role 7 / rehab_context 9 / care_context 5).
/// Returns an empty box for `wildlifeObservation` — observation entries
/// have no analog sub-classification.
class _SubClassificationField extends StatelessWidget {
  const _SubClassificationField({
    super.key,
    required this.relationship,
    required this.workingRole,
    required this.rehabContext,
    required this.careContext,
    required this.onWorkingRoleChanged,
    required this.onRehabContextChanged,
    required this.onCareContextChanged,
  });

  final Relationship relationship;
  final WorkingRole workingRole;
  final RehabContext rehabContext;
  final CareContext careContext;
  final ValueChanged<WorkingRole> onWorkingRoleChanged;
  final ValueChanged<RehabContext> onRehabContextChanged;
  final ValueChanged<CareContext> onCareContextChanged;

  @override
  Widget build(BuildContext context) {
    switch (relationship) {
      case Relationship.pet:
        return _SubPicker<WorkingRole>(
          label: 'Working role',
          value: workingRole,
          values: WorkingRole.values,
          labelOf: (r) => r.label,
          onChanged: onWorkingRoleChanged,
        );
      case Relationship.rescueRehab:
        return _SubPicker<RehabContext>(
          label: 'Rehab context',
          value: rehabContext,
          values: RehabContext.values,
          labelOf: (r) => r.label,
          onChanged: onRehabContextChanged,
        );
      case Relationship.permanentWildlife:
        return _SubPicker<CareContext>(
          label: 'Care context',
          value: careContext,
          values: CareContext.values,
          labelOf: (r) => r.label,
          onChanged: onCareContextChanged,
        );
      case Relationship.wildlifeObservation:
        return const SizedBox.shrink();
    }
  }
}

/// Generic dropdown sub-picker — flat dropdown rather than another stack
/// of radio rows because the values can run to 9 (rehab_context). Keeps
/// the relationship card visually dominant (it's the answer to "who is
/// this animal to you"); the sub-picker is a smaller follow-up.
class _SubPicker<T> extends StatelessWidget {
  const _SubPicker({
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final v in values)
          DropdownMenuItem<T>(value: v, child: Text(labelOf(v))),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _FreeTierLimit extends StatelessWidget {
  const _FreeTierLimit();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.pets, size: 56, color: scheme.primary),
          const SizedBox(height: 16),
          Text(
            'You already have a pet on the free plan.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Adding a second pet is part of Pro, coming in a future '
            'update.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }
}

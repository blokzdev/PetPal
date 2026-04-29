import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/onboarding_templates.dart';
import '../../data/species_catalog.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
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
                    labelText: 'Breed (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/onboarding_templates.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';

/// Add-pet flow. Phase 2.2 collected name/species/breed/DOB; Phase 3.4
/// upgraded the species pick to a dropdown of 8 (per DECISIONS row 25),
/// each loading a category-specific `SOUL.md` template from
/// `assets/onboarding/`. Phase 5.5 renamed the field to `category:` (the
/// 8-bucket axis) so a future precise `species:` field can layer on top
/// per DECISIONS rows 42/43. The harness stays category-agnostic — the
/// pick only changes the markdown the agent sees.
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
  Category _category = Category.dog;
  DateTime? _dob;
  bool _saving = false;
  String? _saveError;

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
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
      final seedSoul = await templates.seedSoulFor(
        category: _category,
        name: _name.text.trim(),
        breed: breed,
        dob: _dob,
      );
      await repo.createPet(
        name: _name.text.trim(),
        category: _category.id,
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
    // Free-tier rule (DECISIONS row 8): one pet maximum. Multi-pet
    // unlocks alongside the paywall in Phase 4. Schema already supports
    // many; this is a UI gate.
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  if (c != null) setState(() => _category = c);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _breed,
                decoration: const InputDecoration(
                  labelText: 'Breed (optional)',
                  border: OutlineInputBorder(),
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

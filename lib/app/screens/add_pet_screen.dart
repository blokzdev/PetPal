import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/onboarding_templates.dart';
import '../providers.dart';

/// Add-pet flow. Phase 2.2 collected name/species/breed/DOB; Phase 3.4
/// upgrades species to a dropdown of 8 (per DECISIONS row 25), each
/// loading a species-specific `SOUL.md` template from
/// `assets/onboarding/`. The harness stays species-agnostic — the pick
/// only changes the markdown the agent sees.
class AddPetScreen extends ConsumerStatefulWidget {
  const AddPetScreen({super.key});

  @override
  ConsumerState<AddPetScreen> createState() => _AddPetScreenState();
}

class _AddPetScreenState extends ConsumerState<AddPetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _breed = TextEditingController();
  Species _species = Species.dog;
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
        species: _species,
        name: _name.text.trim(),
        breed: breed,
        dob: _dob,
      );
      await repo.createPet(
        name: _name.text.trim(),
        species: _species.id,
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
      return Scaffold(
        appBar: AppBar(title: const Text('Add a pet')),
        body: const _FreeTierLimit(),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Add a pet')),
      body: SafeArea(
        child: Padding(
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
                DropdownButtonFormField<Species>(
                  initialValue: _species,
                  decoration: const InputDecoration(
                    labelText: 'Species',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in Species.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (s) {
                    if (s != null) setState(() => _species = s);
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
      ),
    );
  }
}

class _FreeTierLimit extends StatelessWidget {
  const _FreeTierLimit();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.pets, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'You already have a pet on PetPal.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'The free tier supports one pet. Multi-pet support arrives '
              'with the paid tier in a future update.',
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
      ),
    );
  }
}

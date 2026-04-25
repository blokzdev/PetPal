import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';

/// First add-pet flow (Phase 2 task 2.2). Collects the four fields the MVP
/// onboarding promises — name, species, breed, DOB — then calls
/// `PetRepo.createPet`, which seeds the `SOUL.md` skeleton on disk.
class AddPetScreen extends ConsumerStatefulWidget {
  const AddPetScreen({super.key});

  @override
  ConsumerState<AddPetScreen> createState() => _AddPetScreenState();
}

class _AddPetScreenState extends ConsumerState<AddPetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _species = TextEditingController(text: 'dog');
  final _breed = TextEditingController();
  DateTime? _dob;
  bool _saving = false;
  String? _saveError;

  @override
  void dispose() {
    _name.dispose();
    _species.dispose();
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
      await repo.createPet(
        name: _name.text.trim(),
        species: _species.text.trim().isEmpty ? null : _species.text.trim(),
        breed: _breed.text.trim().isEmpty ? null : _breed.text.trim(),
        dob: _dob,
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
                TextFormField(
                  controller: _species,
                  decoration: const InputDecoration(
                    labelText: 'Species',
                    hintText: 'dog, cat, …',
                    border: OutlineInputBorder(),
                  ),
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

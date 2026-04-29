import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/soul_file.dart';
import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_card.dart';
import '../widgets/pet_section_header.dart';

/// Editor for the active pet's SOUL.md. The frontmatter shape is fixed
/// (CLAUDE.md §5): category, breed, dob, weight_kg, allergies, meds,
/// vet_contact, temperament. The body is free-text.
///
/// Save round-trips through `parseSoul` → merge → `serializeSoul` →
/// `WikiIo.writeAtomic`, so an existing file's unknown frontmatter keys
/// survive the edit.
class SoulEditorScreen extends ConsumerStatefulWidget {
  const SoulEditorScreen({super.key});

  @override
  ConsumerState<SoulEditorScreen> createState() => _SoulEditorScreenState();
}

class _SoulEditorScreenState extends ConsumerState<SoulEditorScreen> {
  final _category = TextEditingController();
  final _breed = TextEditingController();
  final _dob = TextEditingController();
  final _weight = TextEditingController();
  final _allergies = TextEditingController();
  final _meds = TextEditingController();
  final _vetContact = TextEditingController();
  final _temperament = TextEditingController();
  final _body = TextEditingController();

  Map<String, Object?> _existingFrontmatter = const {};
  bool _loaded = false;
  bool _saving = false;
  String? _saveError;
  String? _path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _category.dispose();
    _breed.dispose();
    _dob.dispose();
    _weight.dispose();
    _allergies.dispose();
    _meds.dispose();
    _vetContact.dispose();
    _temperament.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final wiki = await ref.read(wikiIoProvider.future);
      final activePetId = ref.read(activePetIdProvider);
      _path = wiki.soulPath(activePetId());
      String raw;
      try {
        raw = await wiki.read(_path!);
      } catch (_) {
        raw = '';
      }
      final parsed = parseSoul(raw);
      _existingFrontmatter = parsed.frontmatter;

      _category.text = _readScalar(parsed.frontmatter, 'category');
      _breed.text = _readScalar(parsed.frontmatter, 'breed');
      _dob.text = _readScalar(parsed.frontmatter, 'dob');
      _weight.text = _readScalar(parsed.frontmatter, 'weight_kg');
      _vetContact.text = _readScalar(parsed.frontmatter, 'vet_contact');
      _allergies.text = _readList(parsed.frontmatter, 'allergies');
      _meds.text = _readList(parsed.frontmatter, 'meds');
      _temperament.text = _readList(parsed.frontmatter, 'temperament');
      _body.text = parsed.body.trimLeft();

      if (mounted) setState(() => _loaded = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _saveError = 'Could not load SOUL.md: $e';
      });
    }
  }

  Future<void> _save() async {
    if (_path == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final wiki = await ref.read(wikiIoProvider.future);
      final patch = <String, Object?>{
        'category': _category.text.trim(),
        'breed': _breed.text.trim(),
        'dob': _dob.text.trim(),
        'weight_kg': _parseNum(_weight.text),
        'allergies': _splitList(_allergies.text),
        'meds': _splitList(_meds.text),
        'vet_contact': _vetContact.text.trim(),
        'temperament': _splitList(_temperament.text),
      };
      final merged = mergeFrontmatter(_existingFrontmatter, patch);
      final next = serializeSoul(
        frontmatter: merged,
        body: '\n${_body.text.trimRight()}\n',
      );
      await wiki.writeAtomic(_path!, next);
      if (mounted) GoRouter.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Per-pet destination → interpolate name into the app bar
    // (VOICE.md §5). Falls back to "Profile" if no pet is loaded yet.
    final petsAsync = ref.watch(petsProvider);
    // Bug-2 defense: treat empty/whitespace name same as null so
    // downstream branches don't render "'s profile" with an orphan
    // apostrophe.
    final petName = petsAsync.maybeWhen(
      data: (pets) {
        if (pets.isEmpty) return null;
        final name = pets.last.name.trim();
        return name.isEmpty ? null : name;
      },
      orElse: () => null,
    );
    final title = petName == null ? 'Profile' : "$petName's profile";
    if (!_loaded) {
      return AppScaffold(
        title: title,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final aboutLabel = petName == null ? 'About this pet' : 'About $petName';
    return AppScaffold(
      title: title,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Single card surface with a SectionHeader divider between
            // Profile (frontmatter) and About (prose) — task 5.12
            // user-locked: 'Single card with section divider'. Lower
            // visual weight than two stacked cards while still calling
            // out the register split.
            PetCard(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.s,
                vertical: Spacing.s,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PetSectionHeader(title: 'Profile'),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.s,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Field(controller: _category, label: 'Category'),
                        const SizedBox(height: Spacing.s),
                        _Field(controller: _breed, label: 'Breed'),
                        const SizedBox(height: Spacing.s),
                        _Field(
                          controller: _dob,
                          label: 'Date of birth (YYYY-MM-DD)',
                        ),
                        const SizedBox(height: Spacing.s),
                        _Field(
                          controller: _weight,
                          label: 'Weight (kg)',
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: Spacing.s),
                        _Field(
                          controller: _allergies,
                          label: 'Allergies (comma-separated)',
                        ),
                        const SizedBox(height: Spacing.s),
                        _Field(
                          controller: _meds,
                          label: 'Medications (comma-separated)',
                        ),
                        const SizedBox(height: Spacing.s),
                        _Field(
                          controller: _vetContact,
                          label: 'Vet contact',
                        ),
                        const SizedBox(height: Spacing.s),
                        _Field(
                          controller: _temperament,
                          label: 'Temperament tags (comma-separated)',
                        ),
                      ],
                    ),
                  ),
                  PetSectionHeader(title: aboutLabel),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.s,
                      0,
                      Spacing.s,
                      Spacing.s,
                    ),
                    child: TextField(
                      controller: _body,
                      minLines: 6,
                      maxLines: 20,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: petName == null
                            ? 'What do you want PetPal to remember?'
                            : 'What do you want PetPal to remember '
                                'about $petName?',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.l),
            if (_saveError != null) ...[
              Text(
                _saveError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: Spacing.s),
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
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

String _readScalar(Map<String, Object?> fm, String key) {
  final v = fm[key];
  if (v == null) return '';
  return v.toString();
}

String _readList(Map<String, Object?> fm, String key) {
  final v = fm[key];
  if (v is List) return v.map((e) => e.toString()).join(', ');
  return '';
}

List<String> _splitList(String input) {
  return input
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Try numeric, fall back to original string. Empty string → null so
/// the YAML emits `weight_kg:` rather than `weight_kg: ` for an unset
/// field.
Object? _parseNum(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final n = num.tryParse(trimmed);
  return n ?? trimmed;
}

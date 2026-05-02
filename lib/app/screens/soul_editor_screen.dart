import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/soul_file.dart';
import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/charts/symptom_chart.dart';
import '../widgets/charts/weight_chart.dart';
import '../widgets/pet_button.dart';
import '../widgets/pet_card.dart';
import '../widgets/pet_empty_state.dart';
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
  // P0 fix — stash the resolved pet id at load time so build() doesn't
  // re-deref `activePetIdProvider` (which throws StateError when pets is
  // empty / loading / errored). Pre-fix, the body Column re-called
  // `ref.read(activePetIdProvider)()` for `_ProfilePhotoCard` and
  // `_TrendsSection` AFTER `_load()` had already caught the same throw —
  // crashing the whole build into a release-mode gray ErrorWidget.
  int? _petId;

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
      // `activePetIdProvider` throws StateError when no pet exists.
      // Catching it here keeps the screen from crashing on the no-pet
      // path; the build branches to a graceful empty-state below.
      final petId = ref.read(activePetIdProvider)();
      _petId = petId;
      _path = wiki.soulPath(petId);
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
    // P0 fix — graceful empty-state when load failed (most commonly
    // because no pet exists yet, which makes `activePetIdProvider`
    // throw StateError). Pre-fix the body Column re-derefed the
    // provider and crashed the build into a release-mode gray
    // ErrorWidget. Render a clear "add a pet" affordance instead.
    if (_petId == null || _path == null) {
      return AppScaffold(
        title: title,
        body: PetEmptyState(
          icon: PhosphorIconsRegular.warningCircle,
          heading: "Couldn't open this profile",
          body: 'Add a pet to start their profile.',
          action: PetButton(
            label: 'Add a pet',
            onPressed: () => GoRouter.of(context).push('/pets/add'),
            icon: PhosphorIconsRegular.plus,
          ),
        ),
      );
    }
    final petId = _petId!;
    final aboutLabel = petName == null ? 'About this pet' : 'About $petName';
    return AppScaffold(
      title: title,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Phase 6 task 6.2 — profile photo card. Lives above the
            // Profile/About card so the visual identity (the photo)
            // sits at the top of the editor, matching the home
            // greeting backdrop's prominence. Watches
            // profilePhotoBytesProvider for the active pet; renders a
            // CircleAvatar thumbnail or a placeholder, with Change /
            // Remove buttons that route through PetRepo.
            //
            // Uses the stashed `_petId` (resolved during `_load()`)
            // rather than re-deref'ing `activePetIdProvider` here.
            // The provider throws StateError on empty pets; the
            // empty-state guard above handles that path.
            _ProfilePhotoCard(petId: petId),
            const SizedBox(height: Spacing.s),
            // Phase 6 task 6.12 — weight + symptom trend charts.
            // Sit between the profile-photo card and the
            // Profile/About card so the user lands on visual identity
            // first, then trends, then editing the structured fields.
            _TrendsSection(petId: petId),
            const SizedBox(height: Spacing.s),
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

/// Phase 6 task 6.2 — profile photo card. Watches
/// `profilePhotoBytesProvider(petId)`. When bytes are present, shows
/// a 96dp circular thumbnail with a Change button + Remove button.
/// When absent, shows a placeholder with an Add button. Picker uses
/// `image_picker.pickImage(source: ImageSource.gallery)` — gallery-
/// only in v1; camera mode lands at task 6.6 with the manifest
/// CAMERA permission.
class _ProfilePhotoCard extends ConsumerStatefulWidget {
  const _ProfilePhotoCard({required this.petId});
  final int petId;

  @override
  ConsumerState<_ProfilePhotoCard> createState() =>
      _ProfilePhotoCardState();
}

class _ProfilePhotoCardState extends ConsumerState<_ProfilePhotoCard> {
  bool _busy = false;

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        // image_picker's max-side resize keeps the on-disk profile
        // photo modest. The 6.6 pre-write resize is the canonical
        // normaliser for memory-photos; for profile photos the
        // picker-side cap is enough.
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final repo = await ref.read(petRepoProvider.future);
      await repo.setProfilePhoto(
        petId: widget.petId,
        imageBytes: bytes,
        mimeType: picked.mimeType ?? 'image/jpeg',
      );
      ref.invalidate(profilePhotoBytesProvider(widget.petId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(petRepoProvider.future);
      await repo.clearProfilePhoto(petId: widget.petId);
      ref.invalidate(profilePhotoBytesProvider(widget.petId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photoAsync = ref.watch(profilePhotoBytesProvider(widget.petId));
    final bytes = photoAsync.maybeWhen(
      data: (b) => b,
      orElse: () => null,
    );
    return PetCard(
      child: Row(
        children: [
          _Avatar(bytes: bytes, scheme: scheme),
          const SizedBox(width: Spacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile photo',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  bytes == null
                      ? 'A photo to recognise this pet across the app.'
                      : 'Shown on Home and in Chat.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                ),
                const SizedBox(height: Spacing.s),
                Row(
                  children: [
                    PetButton(
                      label: bytes == null ? 'Add photo' : 'Change',
                      onPressed: _busy ? null : _pickFromGallery,
                      isLoading: _busy,
                      icon: PhosphorIconsRegular.plus,
                    ),
                    if (bytes != null) ...[
                      const SizedBox(width: Spacing.s),
                      PetButton(
                        label: 'Remove',
                        variant: PetButtonVariant.text,
                        onPressed: _busy ? null : _remove,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.bytes, required this.scheme});
  final Uint8List? bytes;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    if (bytes == null) {
      return Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          PhosphorIconsRegular.pawPrint,
          size: 32,
          color: scheme.onSurface.withValues(alpha: 0.5),
        ),
      );
    }
    return ClipOval(
      child: Image.memory(
        bytes!,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}

/// Phase 6 task 6.12 — trend charts section. Two stacked PetCards:
/// the weight time-series and the symptom-frequency bar chart. Each
/// loads its own provider; while loading, a tiny loading state shows
/// (the providers settle quickly — both are FTS5/index queries).
class _TrendsSection extends ConsumerWidget {
  const _TrendsSection({required this.petId});
  final int petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weightAsync = ref.watch(weightHistoryProvider(petId));
    final symptomsAsync = ref.watch(symptomFrequenciesProvider(petId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        weightAsync.when(
          data: (obs) => WeightChart(observations: obs),
          loading: () => const _ChartLoading(label: 'Weight over time'),
          error: (_, _) => const _ChartLoading(label: 'Weight over time'),
        ),
        const SizedBox(height: Spacing.s),
        symptomsAsync.when(
          data: (freq) => SymptomChart(frequencies: freq),
          loading: () => const _ChartLoading(label: 'What’s come up'),
          error: (_, _) =>
              const _ChartLoading(label: 'What’s come up'),
        ),
      ],
    );
  }
}

class _ChartLoading extends StatelessWidget {
  const _ChartLoading({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return PetCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.s),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: Spacing.s),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

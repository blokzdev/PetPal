import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/onboarding_templates.dart';
import '../../data/relationship.dart';
import '../../data/species_catalog.dart';
import '../design/design.dart';
import '../entitlement/entitlement.dart';
import '../entitlement/quota_exception.dart';
import '../providers.dart';
import '../widgets/paywall_dispatcher.dart';
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

  /// Which lifecycle date the user is providing — DOB (the default),
  /// an approximate age, or the adoption date. Mutually exclusive: only
  /// the picked kind's input is shown and threaded into the SOUL.
  LifecycleDateKind _dateKind = LifecycleDateKind.dob;
  DateTime? _dob;
  final _dobApprox = TextEditingController();
  DateTime? _adoptionDate;

  /// Conditional rescue-rehab dates — surfaced only when relationship
  /// is `rescueRehab` (DECISIONS row 47).
  DateTime? _intakeDate;
  DateTime? _expectedReleaseDate;

  /// Weight + unit toggle. `_useImperial` flips the input label and
  /// converts the typed value to kg before persisting (kg is the
  /// canonical SOUL frontmatter unit; the toggle is UI sugar only).
  final _weight = TextEditingController();
  bool _useImperial = false;

  /// Sex / neutered ternaries default to `unknown` and strip on disk
  /// per the row-45 default-omitted rule.
  PetSex _sex = PetSex.unknown;
  NeuteredStatus _neutered = NeuteredStatus.unknown;

  /// "In your words" — freeform multiline prose substituted into the
  /// `{about_petpal_should_know}` placeholder in the category template.
  /// Empty input renders to nothing (orphan blank line collapsed by
  /// renderTemplate's `\n\n\n+` cleanup).
  final _aboutPetPalShouldKnow = TextEditingController();

  bool _saving = false;
  String? _saveError;
  // Phase 7 task E.1 — non-null when the saveError is a pet-quota
  // block. Renders the "Compare plans" link below the error.
  PetQuotaExceeded? _petQuotaBlocked;

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _otherSpecies.dispose();
    _dobApprox.dispose();
    _weight.dispose();
    _aboutPetPalShouldKnow.dispose();
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

  Future<void> _pickAdoptionDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _adoptionDate ?? DateTime(now.year - 1, now.month, now.day),
      firstDate: DateTime(now.year - 30),
      lastDate: now,
    );
    if (picked != null) setState(() => _adoptionDate = picked);
  }

  Future<void> _pickIntakeDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _intakeDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _intakeDate = picked);
  }

  Future<void> _pickExpectedReleaseDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _expectedReleaseDate ?? DateTime(now.year, now.month + 1, now.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _expectedReleaseDate = picked);
  }

  /// Parse the weight input box into kilograms. Returns null when the
  /// box is empty or unparseable; the caller then leaves `weight_kg:`
  /// off-disk via the strip-empty pass.
  double? _resolvedWeightKg() {
    final raw = _weight.text.trim();
    if (raw.isEmpty) return null;
    final parsed = double.tryParse(raw);
    if (parsed == null) return null;
    return _useImperial ? parsed * 0.45359237 : parsed;
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
    // Defense-in-depth: even if Form.validate() somehow returns true on
    // an empty name (e.g. a future ListView refactor lazy-unmounts the
    // Name field at scroll time so it's not in the Form's _fields
    // registry — the bug Phase 5.5.4 shipped before Bug-1 fix), refuse
    // the write here. SOUL.md must never get an empty `# {name}`
    // header — it cascades into orphan-apostrophe taglines and empty
    // chat-CTA strings across the app surface.
    final trimmedName = _name.text.trim();
    if (trimmedName.isEmpty) {
      _formKey.currentState?.validate();
      setState(() => _saveError = 'Name is required.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _saveError = null;
      _petQuotaBlocked = null;
    });
    try {
      final repo = await ref.read(petRepoProvider.future);
      // Phase 7 task D.1 — pet count gate. Free + BYOK = 1 pet
      // cap (multi-pet is a Pro UX feature, not a cost-driven
      // gate). Per VOICE.md §6 example 9 ("You already have a
      // pet on the free plan. Adding a second pet is part of
      // Pro."). Pro users have `petCap == null` and skip the
      // gate.
      final entitlement = ref.read(entitlementProvider).value ??
          Entitlement.freeAnonymous();
      final cap = entitlement.petCap;
      if (cap != null) {
        final existing = await repo.listPets();
        if (existing.length >= cap) {
          if (!mounted) return;
          setState(() {
            _saving = false;
            // Phase 7 task E.1 — pet-cap UX is inline + Compare
            // plans link (Stage 1 product decision; user confirmed
            // hard wall + escape valve register).
            _saveError = 'You already have a pet on the free plan. '
                'Adding a second pet is part of Pro.';
            _petQuotaBlocked = PetQuotaExceeded(entitlement);
          });
          return;
        }
      }
      final templates = ref.read(onboardingTemplatesProvider);
      final breed = _breed.text.trim().isEmpty ? null : _breed.text.trim();
      final speciesValue = _resolvedSpeciesValue();
      // 5.5.6 — freeform species ("Other (type your own)") routes to
      // category=exotic regardless of the user's category pick. The
      // exotic template carries the catch-all frontmatter shape; the
      // skill loader treats `exotic` normally. The original picked
      // category is dropped on the floor: an animal we can't catalog
      // shouldn't pretend to be tracked under a category it didn't
      // match. Per ROADMAP 5.5.6.
      final effectiveCategory =
          _isOtherSpecies ? Category.exotic : _category;
      // Lifecycle date: only the picked kind's value is threaded into
      // the SOUL. The other two are nulled so renderTemplate's strip-
      // empty pass omits their lines.
      final dob = _dateKind == LifecycleDateKind.dob ? _dob : null;
      final dobApprox = _dateKind == LifecycleDateKind.approxAge
          ? (_dobApprox.text.trim().isEmpty ? null : _dobApprox.text.trim())
          : null;
      final adoptionDate =
          _dateKind == LifecycleDateKind.adoptionDate ? _adoptionDate : null;
      // Rescue-rehab dates only apply when the relationship is rehab.
      final isRehab = _relationship == Relationship.rescueRehab;
      final intakeDate = isRehab ? _intakeDate : null;
      final expectedReleaseDate = isRehab ? _expectedReleaseDate : null;
      final weightKg = _resolvedWeightKg();
      final aboutText = _aboutPetPalShouldKnow.text.trim();
      final seedSoul = await templates.seedSoulFor(
        category: effectiveCategory,
        name: trimmedName,
        species: speciesValue,
        breed: breed,
        sex: _sex,
        neutered: _neutered,
        relationship: _relationship,
        workingRole: _workingRole,
        rehabContext: _rehabContext,
        careContext: _careContext,
        dob: dob,
        dobApprox: dobApprox,
        adoptionDate: adoptionDate,
        intakeDate: intakeDate,
        expectedReleaseDate: expectedReleaseDate,
        weightKg: weightKg,
        aboutPetPalShouldKnow: aboutText.isEmpty ? null : aboutText,
      );
      await repo.createPet(
        name: trimmedName,
        category: effectiveCategory.id,
        species: speciesValue,
        breed: breed,
        dob: dob,
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
    final petsAsync = ref.watch(petsProvider);
    // Phase 7 task E.2 — Pro-aware early-exit. Pro users have
    // `entitlement.petCap == null` and skip the gate; free / BYOK
    // users see _FreeTierLimit when they've hit the 1-pet cap.
    // The deeper gate inside `_save` (D.1, line 246) stays as the
    // canonical defense — this early-exit just keeps the form
    // unrendered when the user clearly can't save.
    final entitlement = ref.watch(entitlementProvider).valueOrNull ??
        Entitlement.freeAnonymous();
    final cap = entitlement.petCap;
    final atLimit = petsAsync.maybeWhen(
      data: (pets) => cap != null && pets.length >= cap,
      orElse: () => false,
    );
    if (atLimit) {
      return AppScaffold(
        title: 'Add a pet',
        body: _FreeTierLimit(blocked: PetQuotaExceeded(entitlement)),
      );
    }
    return AppScaffold(
      title: 'Add a pet',
      // SingleChildScrollView + Column (NOT ListView). ListView lazy-
      // mounts children based on viewport, so when the user scrolls
      // down to tap Save the Name TextFormField at the top scrolls
      // past the cache extent and unmounts. Form.validate() then
      // doesn't see the empty Name field and the save proceeds with
      // an empty `# {name}` SOUL — see Bug-1 fix on the Phase 5.5
      // on-device verification round. Column keeps every FormField
      // mounted regardless of scroll position so validation always
      // covers the whole form.
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
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
                    labelText: 'Type the species — common names work.',
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
                duration: Motion.medium,
                switchInCurve: Motion.springCurve,
                switchOutCurve: Motion.standardCurve,
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
              const SizedBox(height: Spacing.l),
              _AboutPetCard(
                dateKind: _dateKind,
                dob: _dob,
                dobApprox: _dobApprox,
                adoptionDate: _adoptionDate,
                relationship: _relationship,
                intakeDate: _intakeDate,
                expectedReleaseDate: _expectedReleaseDate,
                weight: _weight,
                useImperial: _useImperial,
                sex: _sex,
                neutered: _neutered,
                onDateKindChanged: (k) => setState(() => _dateKind = k),
                onPickDob: _pickDob,
                onPickAdoptionDate: _pickAdoptionDate,
                onPickIntakeDate: _pickIntakeDate,
                onPickExpectedReleaseDate: _pickExpectedReleaseDate,
                onUseImperialChanged: (v) =>
                    setState(() => _useImperial = v),
                onSexChanged: (s) => setState(() => _sex = s),
                onNeuteredChanged: (n) => setState(() => _neutered = n),
              ),
              const SizedBox(height: Spacing.l),
              _InYourWordsCard(controller: _aboutPetPalShouldKnow),
              const SizedBox(height: Spacing.l),
              if (_saveError != null) ...[
                Text(
                  _saveError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                if (_petQuotaBlocked != null) ...[
                  // Phase 7 task H.2.b — restored default tap padding +
                  // dropped `Size.zero` so the Compare-plans link meets
                  // the 48dp touch-target floor. The inline pet-quota
                  // error already sits inside a Padding(.l), so the
                  // button's pill padding fits without crowding.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => dispatchPaywall(
                        context,
                        _petQuotaBlocked!,
                      ),
                      child: const Text('Compare plans'),
                    ),
                  ),
                ],
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
          suffixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
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
          suffixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
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

/// "About this pet" card — DECISIONS row 47 + 5.5.4 design D7=B lock.
/// Gathers the pet's lifecycle date (one of DOB / approximate age /
/// adoption date), conditional rescue-rehab intake + release dates,
/// weight (kg or lb), sex, and neutered status. Each input is optional;
/// defaults serialize as empty and strip on disk.
class _AboutPetCard extends StatelessWidget {
  const _AboutPetCard({
    required this.dateKind,
    required this.dob,
    required this.dobApprox,
    required this.adoptionDate,
    required this.relationship,
    required this.intakeDate,
    required this.expectedReleaseDate,
    required this.weight,
    required this.useImperial,
    required this.sex,
    required this.neutered,
    required this.onDateKindChanged,
    required this.onPickDob,
    required this.onPickAdoptionDate,
    required this.onPickIntakeDate,
    required this.onPickExpectedReleaseDate,
    required this.onUseImperialChanged,
    required this.onSexChanged,
    required this.onNeuteredChanged,
  });

  final LifecycleDateKind dateKind;
  final DateTime? dob;
  final TextEditingController dobApprox;
  final DateTime? adoptionDate;
  final Relationship relationship;
  final DateTime? intakeDate;
  final DateTime? expectedReleaseDate;
  final TextEditingController weight;
  final bool useImperial;
  final PetSex sex;
  final NeuteredStatus neutered;
  final ValueChanged<LifecycleDateKind> onDateKindChanged;
  final VoidCallback onPickDob;
  final VoidCallback onPickAdoptionDate;
  final VoidCallback onPickIntakeDate;
  final VoidCallback onPickExpectedReleaseDate;
  final ValueChanged<bool> onUseImperialChanged;
  final ValueChanged<PetSex> onSexChanged;
  final ValueChanged<NeuteredStatus> onNeuteredChanged;

  @override
  Widget build(BuildContext context) {
    return PetCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PetSectionHeader(title: 'About this pet'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.m,
              0,
              Spacing.m,
              Spacing.m,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LifecycleDateField(
                  kind: dateKind,
                  dob: dob,
                  dobApprox: dobApprox,
                  adoptionDate: adoptionDate,
                  onKindChanged: onDateKindChanged,
                  onPickDob: onPickDob,
                  onPickAdoptionDate: onPickAdoptionDate,
                ),
                AnimatedSwitcher(
                  duration: Motion.medium,
                  switchInCurve: Motion.springCurve,
                  switchOutCurve: Motion.standardCurve,
                  child: relationship == Relationship.rescueRehab
                      ? Padding(
                          key: const ValueKey('rescue-rehab-dates'),
                          padding: const EdgeInsets.only(top: Spacing.m),
                          child: _RescueRehabDates(
                            intakeDate: intakeDate,
                            expectedReleaseDate: expectedReleaseDate,
                            onPickIntakeDate: onPickIntakeDate,
                            onPickExpectedReleaseDate:
                                onPickExpectedReleaseDate,
                          ),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('no-rescue-rehab-dates'),
                        ),
                ),
                const SizedBox(height: Spacing.m),
                _WeightField(
                  controller: weight,
                  useImperial: useImperial,
                  onUseImperialChanged: onUseImperialChanged,
                ),
                const SizedBox(height: Spacing.m),
                _TernaryRow<PetSex>(
                  label: 'Sex',
                  value: sex,
                  values: PetSex.values,
                  labelOf: (s) => s.label,
                  onChanged: onSexChanged,
                ),
                const SizedBox(height: Spacing.s),
                _TernaryRow<NeuteredStatus>(
                  label: 'Neutered',
                  value: neutered,
                  values: NeuteredStatus.values,
                  labelOf: (n) => n.label,
                  onChanged: onNeuteredChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LifecycleDateField extends StatelessWidget {
  const _LifecycleDateField({
    required this.kind,
    required this.dob,
    required this.dobApprox,
    required this.adoptionDate,
    required this.onKindChanged,
    required this.onPickDob,
    required this.onPickAdoptionDate,
  });

  final LifecycleDateKind kind;
  final DateTime? dob;
  final TextEditingController dobApprox;
  final DateTime? adoptionDate;
  final ValueChanged<LifecycleDateKind> onKindChanged;
  final VoidCallback onPickDob;
  final VoidCallback onPickAdoptionDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<LifecycleDateKind>(
          segments: const [
            ButtonSegment(
              value: LifecycleDateKind.dob,
              label: Text('DOB'),
            ),
            ButtonSegment(
              value: LifecycleDateKind.approxAge,
              label: Text('Approx age'),
            ),
            ButtonSegment(
              value: LifecycleDateKind.adoptionDate,
              label: Text('Adoption'),
            ),
          ],
          selected: {kind},
          onSelectionChanged: (s) => onKindChanged(s.first),
        ),
        const SizedBox(height: Spacing.s),
        AnimatedSwitcher(
          duration: Motion.medium,
          switchInCurve: Motion.springCurve,
          switchOutCurve: Motion.standardCurve,
          child: switch (kind) {
            LifecycleDateKind.dob => OutlinedButton.icon(
                key: const ValueKey('dob-picker'),
                onPressed: onPickDob,
                icon: const Icon(PhosphorIconsRegular.calendar),
                label: Text(_dobLabel(dob)),
              ),
            LifecycleDateKind.approxAge => TextFormField(
                key: const ValueKey('dob-approx'),
                controller: dobApprox,
                decoration: const InputDecoration(
                  labelText: 'Approximate age (e.g. "about 3 years")',
                  border: OutlineInputBorder(),
                ),
              ),
            LifecycleDateKind.adoptionDate => OutlinedButton.icon(
                key: const ValueKey('adoption-picker'),
                onPressed: onPickAdoptionDate,
                icon: const Icon(PhosphorIconsRegular.calendar),
                label: Text(_adoptionLabel(adoptionDate)),
              ),
          },
        ),
      ],
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _dobLabel(DateTime? d) =>
      d == null ? 'Pick date of birth' : 'DOB: ${_fmt(d)}';
  static String _adoptionLabel(DateTime? d) =>
      d == null ? 'Pick adoption date' : 'Adopted: ${_fmt(d)}';
}

class _RescueRehabDates extends StatelessWidget {
  const _RescueRehabDates({
    required this.intakeDate,
    required this.expectedReleaseDate,
    required this.onPickIntakeDate,
    required this.onPickExpectedReleaseDate,
  });

  final DateTime? intakeDate;
  final DateTime? expectedReleaseDate;
  final VoidCallback onPickIntakeDate;
  final VoidCallback onPickExpectedReleaseDate;

  @override
  Widget build(BuildContext context) {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: onPickIntakeDate,
          icon: const Icon(PhosphorIconsRegular.calendar),
          label: Text(intakeDate == null
              ? 'Pick intake date'
              : 'Intake: ${fmt(intakeDate!)}'),
        ),
        const SizedBox(height: Spacing.s),
        OutlinedButton.icon(
          onPressed: onPickExpectedReleaseDate,
          icon: const Icon(PhosphorIconsRegular.calendar),
          label: Text(expectedReleaseDate == null
              ? 'Pick expected release date'
              : 'Release: ${fmt(expectedReleaseDate!)}'),
        ),
      ],
    );
  }
}

class _WeightField extends StatelessWidget {
  const _WeightField({
    required this.controller,
    required this.useImperial,
    required this.onUseImperialChanged,
  });

  final TextEditingController controller;
  final bool useImperial;
  final ValueChanged<bool> onUseImperialChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: useImperial ? 'Weight (lb)' : 'Weight (kg)',
              border: const OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              return double.tryParse(v.trim()) == null ? 'Number' : null;
            },
          ),
        ),
        const SizedBox(width: Spacing.s),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('kg')),
            ButtonSegment(value: true, label: Text('lb')),
          ],
          selected: {useImperial},
          onSelectionChanged: (s) => onUseImperialChanged(s.first),
        ),
      ],
    );
  }
}

class _TernaryRow<T> extends StatelessWidget {
  const _TernaryRow({
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
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        Expanded(
          child: SegmentedButton<T>(
            segments: [
              for (final v in values)
                ButtonSegment<T>(value: v, label: Text(labelOf(v))),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ),
      ],
    );
  }
}

/// "In your words" PetCard — DECISIONS row 47 + 5.5.4 design D7=B
/// lock. Multiline freeform prose that substitutes into the
/// `{about_petpal_should_know}` placeholder at the end of the
/// category-template body.
class _InYourWordsCard extends StatelessWidget {
  const _InYourWordsCard({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PetCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PetSectionHeader(title: 'In your words'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.m,
              0,
              Spacing.m,
              Spacing.m,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'What should PetPal know about your pet? Habits, '
                  'history, things to keep in mind. (Optional — you can '
                  'always add more later.)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.s),
                TextFormField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'e.g. Loki is a rescue mutt who came home in '
                        'October 2023. Afraid of skateboards, soft for '
                        'frozen carrots.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FreeTierLimit extends StatelessWidget {
  const _FreeTierLimit({required this.blocked});

  /// Phase 7 task E.2 — the synthesized [PetQuotaExceeded] is
  /// passed to [dispatchPaywall] when the user taps "Compare
  /// plans," matching the inline-error CTA that fires from inside
  /// `_save`. VOICE.md §6 example 9 governs the body copy.
  final PetQuotaExceeded blocked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(PhosphorIconsRegular.pawPrint, size: 56, color: scheme.primary),
          const SizedBox(height: 16),
          Text(
            'You already have a pet on the free plan.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Adding a second pet is part of Pro.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => dispatchPaywall(context, blocked),
            child: const Text('Compare plans'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }
}

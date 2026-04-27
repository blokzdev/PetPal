import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/onboarding_templates.dart';
import '../../data/repos/reminder_repo.dart';
import '../../data/soul_file.dart';
import '../../harness/scheduling/reminder_kinds.dart';
import '../design/design.dart';
import '../platform/haptics.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/battery_exemption_prompt.dart';
import '../widgets/pet_button.dart';
import '../widgets/pet_empty_state.dart';
import '../widgets/pet_skeleton.dart';

/// Reminders CRUD screen — per-pet destination, so the app bar
/// interpolates the active pet's name (VOICE.md §5).
///
/// The screen surfaces three calm banners when the relevant Android
/// permission is denied — battery optimisation, exact alarms, and
/// notifications — but never blocks the user from creating a
/// reminder. Per DECISIONS row 31 the fallback path is the load-
/// bearing one; the banners just point at system settings.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final petsAsync = ref.watch(petsProvider);
    final petName = petsAsync.maybeWhen(
      data: (pets) => pets.isEmpty ? null : pets.last.name,
      orElse: () => null,
    );
    final title = petName == null ? 'Reminders' : "$petName's reminders";

    return AppScaffold(
      title: title,
      body: petsAsync.when(
        data: (pets) => pets.isEmpty
            ? const _NoPet()
            : _Body(
                pet: pets.last,
                onAdd: () => _openAdd(context, ref, pets.last.id),
              ),
        loading: () => const _RemindersSkeleton(),
        error: (e, _) =>
            const Center(child: Text("Couldn't load reminders.")),
      ),
      floatingActionButton: petsAsync.maybeWhen(
        data: (pets) => pets.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _openAdd(context, ref, pets.last.id),
                icon: const Icon(Icons.add_alarm),
                label: const Text('Add reminder'),
              ),
        orElse: () => null,
      ),
    );
  }

  Future<void> _openAdd(BuildContext context, WidgetRef ref, int petId) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _AddReminderScreen(petId: petId),
      ),
    );
    if (created != true) return;
    // First-save battery-exemption prompt — VOICE.md global modal,
    // shown at most once per device (BatteryExemptionPrompt.maybeShow
    // persists the seen flag).
    if (!context.mounted) return;
    await BatteryExemptionPrompt.maybeShow(
      context: context,
      settings: ref.read(settingsStorageProvider),
      health: ref.read(scheduleHealthServiceProvider),
    );
    // Reset the list — the new row should appear.
    ref.invalidate(_remindersListProvider);
  }
}

class _NoPet extends StatelessWidget {
  const _NoPet();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Add a pet first, then reminders can hang off their profile.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

final _remindersListProvider =
    FutureProvider.family<List<ReminderRow>, int>((ref, petId) async {
  final service = await ref.watch(reminderServiceProvider.future);
  return service.listForPet(petId);
});

final _scheduleHealthProvider = FutureProvider.autoDispose((ref) async {
  return ref.watch(scheduleHealthServiceProvider).check();
});

class _Body extends ConsumerWidget {
  const _Body({required this.pet, required this.onAdd});
  final dynamic pet;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(_remindersListProvider(pet.id as int));
    final health = ref.watch(_scheduleHealthProvider);

    return Column(
      children: [
        health.when(
          data: (h) => _HealthBanners(health: h),
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
        Expanded(
          child: reminders.when(
            data: (rows) => rows.isEmpty
                ? RemindersEmptyForTesting(
                    petName: pet.name as String,
                    onAdd: onAdd,
                  )
                : _List(rows: rows, petId: pet.id as int),
            loading: () => const _RemindersSkeleton(),
            error: (e, _) =>
                const Center(child: Text("Couldn't load reminders.")),
          ),
        ),
      ],
    );
  }
}

/// Reminders loading skeleton — matches the actual reminder row
/// geometry: leading icon circle, two stacked lines (kind + when),
/// trailing "fires-in" chip. Authentic preview rather than the
/// generic AppScaffold.async default. Six rows mirrors the typical
/// free-tier cap (DECISIONS row 36).
class _RemindersSkeleton extends StatelessWidget {
  const _RemindersSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s),
      itemCount: 6,
      itemBuilder: (_, i) => PetSkeletonListRow(
        hasTrailing: true,
        titleWidth: 180 - (i.isEven ? 0 : 40).toDouble(),
        subtitleWidth: 120 - (i.isEven ? 30 : 0).toDouble(),
      ),
    );
  }
}

/// Reminders empty state — task 5.7 (locked option: action-first with
/// category examples). The body teaches what KINDS of reminders are
/// useful (heartworm, flea treatment, vaccines) so a user with no
/// mental model gets concrete starters. Per-pet destination → name
/// interpolation (VOICE.md §5). The CTA mirrors the FAB so the empty
/// state has its own large affordance — duplication is intentional;
/// the FAB anchors at the bottom-right and can be missed on first use.
class RemindersEmptyForTesting extends StatelessWidget {
  const RemindersEmptyForTesting({
    super.key,
    required this.petName,
    required this.onAdd,
  });
  final String petName;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return PetEmptyState(
      icon: Icons.alarm_outlined,
      heading: 'No reminders for $petName yet.',
      body: 'Heartworm. Flea treatment. Vaccines. Set a reminder '
          "and PetPal will nudge you when it's due.",
      action: PetButton(
        label: 'Add reminder',
        onPressed: onAdd,
        icon: Icons.add_alarm,
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.rows, required this.petId});
  final List<ReminderRow> rows;
  final int petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = rows[i];
        final kind = ReminderKind.fromId(r.kind);
        final label = kind?.label ?? r.kind;
        return Dismissible(
          key: ValueKey('reminder-${r.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Theme.of(context).colorScheme.errorContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          confirmDismiss: (_) async {
            final service = await ref.read(reminderServiceProvider.future);
            await service.cancel(r.id);
            ref.invalidate(_remindersListProvider);
            // Task 5.8 — light haptic on completing/cancelling a
            // reminder. Fires after the cancel succeeds, before the
            // animation plays out, so the buzz syncs with the row's
            // visual departure.
            ref.read(hapticsProvider).light();
            return true;
          },
          child: ListTile(
            leading: Icon(_iconFor(kind)),
            title: Text(label),
            subtitle: Text(_formatDate(r.whenTs)),
          ),
        );
      },
    );
  }

  IconData _iconFor(ReminderKind? kind) {
    switch (kind) {
      case ReminderKind.fleaTreatment:
        return Icons.bug_report_outlined;
      case ReminderKind.heartwormDose:
        return Icons.medication_outlined;
      case ReminderKind.vaccineDue:
        return Icons.vaccines_outlined;
      case ReminderKind.weightCheck:
        return Icons.monitor_weight_outlined;
      case null:
        return Icons.alarm_outlined;
    }
  }

  String _formatDate(DateTime ts) {
    final iso = '${ts.year.toString().padLeft(4, '0')}-'
        '${ts.month.toString().padLeft(2, '0')}-'
        '${ts.day.toString().padLeft(2, '0')}';
    final time =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    return '$iso · $time';
  }
}

class _HealthBanners extends StatelessWidget {
  const _HealthBanners({required this.health});
  final dynamic health;

  @override
  Widget build(BuildContext context) {
    final messages = <String>[];
    if (health.batteryOptimizationDisabled == false) {
      messages.add(
        'Android may delay reminders to save battery — to fix, allow PetPal to '
        'run in the background in system settings.',
      );
    }
    if (health.exactAlarmsAllowed == false) {
      messages.add(
        'Reminders may fire up to ~10 minutes late — to fix, allow exact '
        'alarms in system settings.',
      );
    }
    if (health.notificationsAllowed == false) {
      messages.add(
        'Notifications are off — to receive reminders, turn them on in '
        'system settings.',
      );
    }
    if (messages.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHigh,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in messages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m,
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
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

/// Add-reminder form. Per-pet destination → name interpolates in
/// the title and body copy. Kind picker → date+time picker → save.
class _AddReminderScreen extends ConsumerStatefulWidget {
  const _AddReminderScreen({required this.petId});
  final int petId;

  @override
  ConsumerState<_AddReminderScreen> createState() =>
      _AddReminderScreenState();
}

class _AddReminderScreenState extends ConsumerState<_AddReminderScreen> {
  ReminderKind _kind = ReminderKind.fleaTreatment;
  DateTime? _when;
  bool _saving = false;
  String? _error;

  Species? _activeSpecies;

  @override
  void initState() {
    super.initState();
    _loadSpecies();
  }

  Future<void> _loadSpecies() async {
    final wiki = await ref.read(wikiIoProvider.future);
    String soul;
    try {
      soul = await wiki.read(wiki.soulPath(widget.petId));
    } catch (_) {
      soul = '';
    }
    final speciesId =
        parseSoul(soul).frontmatter['species']?.toString().trim() ?? '';
    if (!mounted) return;
    setState(() {
      _activeSpecies = Species.fromId(speciesId);
      _applyDefaultCadence();
    });
  }

  void _applyDefaultCadence() {
    final species = _activeSpecies;
    if (species == null) {
      _when = null;
      return;
    }
    final cadence = defaultCadenceFor(kind: _kind, species: species);
    if (cadence == null) {
      _when = null; // bird/reptile/fish/exotic — require explicit pick
    } else {
      _when = DateTime.now().add(cadence);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _when ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (time == null) return;
    setState(() {
      _when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    final when = _when;
    if (when == null) {
      setState(() => _error = 'Pick a date and time first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final service = await ref.read(reminderServiceProvider.future);
      await service.create(
        petId: widget.petId,
        kind: _kind.id,
        when: when,
      );
      if (!mounted) return;
      // Task 5.8 — light haptic on schedule-reminder commit, before
      // the form pops back to the list.
      ref.read(hapticsProvider).light();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickedLabel = _when == null
        ? 'Pick a date and time'
        : 'Set for ${_when!.year}-${_when!.month.toString().padLeft(2, '0')}-${_when!.day.toString().padLeft(2, '0')} at '
            '${_when!.hour.toString().padLeft(2, '0')}:${_when!.minute.toString().padLeft(2, '0')}';

    final cadenceUnknown = _activeSpecies != null &&
        defaultCadenceFor(kind: _kind, species: _activeSpecies!) == null;

    return AppScaffold(
      title: 'Add reminder',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<ReminderKind>(
                initialValue: _kind,
                decoration: const InputDecoration(
                  labelText: 'Kind',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final k in ReminderKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (k) {
                  if (k == null) return;
                  setState(() {
                    _kind = k;
                    _applyDefaultCadence();
                  });
                },
              ),
              if (_kind == ReminderKind.vaccineDue) ...[
                const SizedBox(height: 8),
                Text(
                  vaccineUiNote,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 16),
              if (cadenceUnknown) ...[
                Text(
                  "We don't have a default cadence for this species — "
                  'please set a date and time.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(pickedLabel),
              ),
              const SizedBox(height: 24),
              if (_error != null) ...[
                Text(
                  _error!,
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
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/soul_file.dart';
import '../../harness/scheduling/reminder_kinds.dart';
import '../design/design.dart';
import '../platform/haptics.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_button.dart';
import '../widgets/pet_card.dart';
import '../widgets/pet_section_header.dart';

/// Phase 6 task 6.10 — vet-visit structured entry creator.
///
/// Form-driven UI for the canonical vet-visit entry shape. Writes to
/// `wiki/<petId>/vet/<YYYY-MM-DD>-<reason-slug>.md` with structured
/// frontmatter:
///
/// ```
/// ---
/// type: vet
/// date: 2026-04-30
/// vet_name: Dr. Patel
/// reason: Annual checkup
/// diagnosis: ...
/// prescriptions:
///   - Frontline Plus monthly
/// follow_up_date: 2027-04-30
/// ---
/// ```
///
/// The structured fields are read by:
///   - 6.11 reminder generation (auto-create a `notification` reminder
///     when `follow_up_date` is set),
///   - 6.13 weekly summary (vet visits surface as anchor moments),
///   - any v1.x feature that wants to mine vet history (timeline,
///     export, etc.).
///
/// Freeform notes go in the body — the user's voice. The form's
/// "Notes" textarea is the only field that lands in the body; every
/// structured field becomes frontmatter.
///
/// **Title source.** The `reason` field is the title (used for FTS5
/// indexing + the entry-tile label + the AppBar title on the entry
/// view). Empty `reason` falls back to "Vet visit" so the entry is
/// still navigable; the path-side slug uses the same title before
/// slugify.
///
/// **Slugify.** Reuses [WikiRepo.entryPath]'s slugify implicitly via
/// the standard `writeEntry` path — no custom slugger here.
class VetVisitFormScreen extends ConsumerStatefulWidget {
  const VetVisitFormScreen({super.key});

  @override
  ConsumerState<VetVisitFormScreen> createState() =>
      _VetVisitFormScreenState();
}

class _VetVisitFormScreenState extends ConsumerState<VetVisitFormScreen> {
  // Default visit_date = today; user can pick a different date.
  DateTime _visitDate = _today();
  DateTime? _followUpDate;

  final _vetName = TextEditingController();
  final _reason = TextEditingController();
  final _diagnosis = TextEditingController();
  final _prescriptions = TextEditingController();
  final _notes = TextEditingController();

  bool _saving = false;
  String? _saveError;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _vetName.dispose();
    _reason.dispose();
    _diagnosis.dispose();
    _prescriptions.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickVisitDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _visitDate,
      firstDate: DateTime(2000),
      lastDate: _today().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _visitDate = picked);
  }

  Future<void> _pickFollowUpDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUpDate ?? _visitDate.add(const Duration(days: 30)),
      firstDate: _today(),
      lastDate: _today().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _followUpDate = picked);
  }

  void _clearFollowUpDate() => setState(() => _followUpDate = null);

  /// Test hook — the date picker is awkward to drive from widget
  /// tests, so 6.11's reminder-creation tests set the follow-up
  /// date programmatically.
  @visibleForTesting
  void setFollowUpDateForTesting(DateTime? value) =>
      setState(() => _followUpDate = value);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final pets = await ref.read(petsProvider.future);
      if (pets.isEmpty) {
        setState(() {
          _saving = false;
          _saveError = "Add a pet first — vet visits hang off a pet's profile.";
        });
        return;
      }
      final petId = pets.last.id;

      // Title is the `reason` field, falling back to "Vet visit" so
      // empty-reason entries are still navigable. The path-side slug
      // is derived from the title in WikiRepo.entryPath.
      final reason = _reason.text.trim();
      final title = reason.isEmpty ? 'Vet visit' : reason;

      final prescriptions = _splitList(_prescriptions.text);

      // Compose the structured frontmatter. All optional fields are
      // omitted when empty so the on-disk entry stays minimal.
      final frontmatter = <String, Object?>{
        'type': 'vet',
        'date': _isoDate(_visitDate),
        if (_vetName.text.trim().isNotEmpty)
          'vet_name': _vetName.text.trim(),
        if (reason.isNotEmpty) 'reason': reason,
        if (_diagnosis.text.trim().isNotEmpty)
          'diagnosis': _diagnosis.text.trim(),
        if (prescriptions.isNotEmpty) 'prescriptions': prescriptions,
        if (_followUpDate != null)
          'follow_up_date': _isoDate(_followUpDate!),
      };

      final body = serializeSoul(
        frontmatter: frontmatter,
        body: '\n# $title\n\n${_notes.text.trim()}\n',
      );

      final repo = await ref.read(wikiRepoProvider.future);
      await repo.writeEntry(
        petId: petId,
        type: 'vet',
        title: title,
        body: body,
        ts: _visitDate,
      );

      // Phase 6 task 6.11 — auto-create a notification-mode reminder
      // when the user set a follow_up_date. Reuses the existing
      // scheduling stack (`ReminderService.create`) which writes the
      // reminder row + arms the platform alarm. The vet_followup
      // template (assets/reminders/vet_followup.yaml) renders the
      // body as "Time for {pet}'s vet follow-up — book an
      // appointment." Best-effort — a scheduling failure does NOT
      // roll back the entry write. The vet visit itself is more
      // valuable than the reminder; the user can re-create the
      // reminder via the chat agent if scheduling fails.
      final followUpAt = _followUpDate;
      if (followUpAt != null) {
        try {
          final reminders =
              await ref.read(reminderServiceProvider.future);
          await reminders.create(
            petId: petId,
            kind: ReminderKind.vetFollowUp.id,
            // Fire at 9 AM local on the follow-up date — the
            // existing scheduler treats `when` as the exact fire
            // time. Picker emitted midnight; bumping to morning so
            // the notification doesn't fire while the user sleeps.
            when: DateTime(
              followUpAt.year,
              followUpAt.month,
              followUpAt.day,
              9,
            ),
            // Default mode is notification — see ReminderService.create.
          );
        } catch (_) {
          // Reminder failure shouldn't block the vet entry save.
          // (The user still has the entry on disk; no data lost.)
        }
      }

      // Bust the journal browser's entry cache so the new vet entry
      // lands without a manual refresh.
      ref.invalidate(wikiEntriesProvider);
      ref.read(hapticsProvider).light();

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(const SnackBar(
        content: Text('Vet visit saved.'),
      ));
      GoRouter.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Save failed: $e';
      });
    }
  }

  static List<String> _splitList(String raw) => raw
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppScaffold(
      title: 'Log a vet visit',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PetCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PetSectionHeader(title: 'Visit'),
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
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Date of visit'),
                          subtitle: Text(_isoDate(_visitDate)),
                          trailing: const Icon(
                            PhosphorIconsRegular.calendar,
                          ),
                          onTap: _pickVisitDate,
                        ),
                        const SizedBox(height: Spacing.s),
                        TextField(
                          controller: _vetName,
                          decoration: const InputDecoration(
                            labelText: 'Vet name (optional)',
                            hintText: 'Dr. Patel',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: Spacing.s),
                        TextField(
                          controller: _reason,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Reason for visit',
                            hintText: 'Annual checkup, lethargy, …',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: Spacing.s),
                        TextField(
                          controller: _diagnosis,
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Diagnosis (what the vet said)',
                            hintText: 'No issues found, mild ear '
                                'infection, …',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: Spacing.s),
                        TextField(
                          controller: _prescriptions,
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 2,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'Prescriptions (one per line)',
                            hintText: 'Frontline Plus monthly\n'
                                'Apoquel 16mg, twice daily for 7 days',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: Spacing.s),
                        // Follow-up date — optional. Picker on tap;
                        // clear button when set. Phase 6.11 reads this
                        // field to auto-create a notification reminder.
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Follow-up (optional)'),
                          subtitle: Text(_followUpDate == null
                              ? 'Schedule a reminder for the next visit.'
                              : _isoDate(_followUpDate!)),
                          trailing: _followUpDate == null
                              ? const Icon(
                                  PhosphorIconsRegular.calendarPlus,
                                )
                              : IconButton(
                                  tooltip: 'Clear follow-up',
                                  onPressed: _clearFollowUpDate,
                                  icon: const Icon(
                                    PhosphorIconsRegular.x,
                                  ),
                                ),
                          onTap: _pickFollowUpDate,
                        ),
                      ],
                    ),
                  ),
                  const PetSectionHeader(title: 'Notes'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.m,
                      0,
                      Spacing.m,
                      Spacing.m,
                    ),
                    child: TextField(
                      controller: _notes,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 4,
                      maxLines: 12,
                      decoration: const InputDecoration(
                        hintText: 'Anything else worth remembering — '
                            "owner's notes go here, in your voice.",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: Spacing.m),
              Text(
                _saveError!,
                style: TextStyle(color: scheme.error),
              ),
            ],
            const SizedBox(height: Spacing.l),
            PetButton(
              label: 'Save vet visit',
              onPressed: _saving ? null : _save,
              isLoading: _saving,
              icon: PhosphorIconsRegular.bookOpen,
            ),
          ],
        ),
      ),
    );
  }
}

import '../../data/onboarding_templates.dart';

/// The four canonical reminder kinds Phase 4 ships with templates +
/// default cadences for. New kinds may land in a later release (custom
/// user-authored reminders) — this enum is *not* exhaustive of every
/// possible `reminders.kind` value the database holds; the agent's
/// `schedule_reminder` tool can write any string. The enum just
/// captures the four kinds the UI knows how to surface with rich
/// affordances.
enum ReminderKind {
  fleaTreatment('flea_treatment'),
  heartwormDose('heartworm_dose'),
  vaccineDue('vaccine_due'),
  weightCheck('weight_check'),

  /// Phase 6 task 6.11 — auto-created from a vet-visit entry's
  /// `follow_up_date` field. Not user-pickable from the create-
  /// reminder UI; arrives only via the form-driven 6.10 entry
  /// creator's save handler (or, in v1.x, agent-side `schedule_reminder`
  /// calls with the same kind id).
  vetFollowUp('vet_followup');

  const ReminderKind(this.id);
  final String id;

  /// Human-readable label for the kind picker.
  String get label {
    switch (this) {
      case ReminderKind.fleaTreatment:
        return 'Flea treatment';
      case ReminderKind.heartwormDose:
        return 'Heartworm dose';
      case ReminderKind.vaccineDue:
        return 'Vaccine';
      case ReminderKind.weightCheck:
        return 'Weight check';
      case ReminderKind.vetFollowUp:
        return 'Vet follow-up';
    }
  }

  static ReminderKind? fromId(String id) {
    for (final k in ReminderKind.values) {
      if (k.id == id) return k;
    }
    return null;
  }
}

/// Default cadence used to pre-fill the "when" picker when the user
/// adds a reminder. Calibrated for dog/cat/rabbit/small-mammal —
/// the most common cases.
///
/// **Returns null** for `bird`, `reptile`, `fish`, and `exotic`. Per
/// the locked design rule (DECISIONS row 31 / user lock-in), cadences
/// for non-mammal categories vary so wildly by species, age, and
/// individual that a wrong default is worse than no default. The UI
/// surfaces a "please set a date" state instead of pre-filling.
Duration? defaultCadenceFor({
  required ReminderKind kind,
  required Category category,
}) {
  const noDefault = {
    Category.bird,
    Category.reptile,
    Category.fish,
    Category.exotic,
  };
  if (noDefault.contains(category)) return null;
  switch (kind) {
    case ReminderKind.fleaTreatment:
      return const Duration(days: 30);
    case ReminderKind.heartwormDose:
      return const Duration(days: 30);
    case ReminderKind.vaccineDue:
      return const Duration(days: 365);
    case ReminderKind.weightCheck:
      return const Duration(days: 14);
    case ReminderKind.vetFollowUp:
      // Vet follow-ups are calendar-pinned by the vet at the visit;
      // no sensible default cadence. Returns null so any UI surface
      // that ever picks vetFollowUp from a kind-picker shows a
      // "please set a date" state. The 6.11 auto-create path always
      // supplies an explicit `when:` so this null is unreachable
      // there.
      return null;
  }
}

/// One-line note shown in the create-reminder UI when the user picks
/// a vaccine reminder. Per VOICE.md tone: direct, not alarmist —
/// treats the owner as an adult who can handle real information.
const String vaccineUiNote =
    'Confirm timing with your vet — vaccine schedules vary by region, '
    'age, and individual health.';

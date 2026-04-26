import '../../data/onboarding_templates.dart';

/// The four canonical reminder kinds Phase 4 ships with templates +
/// default cadences for. New kinds may land in Phase 5+ (custom user-
/// authored reminders) — this enum is *not* exhaustive of every
/// possible `reminders.kind` value the database holds; the agent's
/// `schedule_reminder` tool can write any string. The enum just
/// captures the four kinds the UI knows how to surface with rich
/// affordances.
enum ReminderKind {
  fleaTreatment('flea_treatment'),
  heartwormDose('heartworm_dose'),
  vaccineDue('vaccine_due'),
  weightCheck('weight_check');

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
/// for non-mammal species vary so wildly by species, age, and
/// individual that a wrong default is worse than no default. The UI
/// surfaces a "please set a date" state instead of pre-filling.
Duration? defaultCadenceFor({
  required ReminderKind kind,
  required Species species,
}) {
  const noDefault = {
    Species.bird,
    Species.reptile,
    Species.fish,
    Species.exotic,
  };
  if (noDefault.contains(species)) return null;
  switch (kind) {
    case ReminderKind.fleaTreatment:
      return const Duration(days: 30);
    case ReminderKind.heartwormDose:
      return const Duration(days: 30);
    case ReminderKind.vaccineDue:
      return const Duration(days: 365);
    case ReminderKind.weightCheck:
      return const Duration(days: 14);
  }
}

/// One-line note shown in the create-reminder UI when the user picks
/// a vaccine reminder. Per VOICE.md tone: direct, not alarmist —
/// treats the owner as an adult who can handle real information.
const String vaccineUiNote =
    'Confirm timing with your vet — vaccine schedules vary by region, '
    'age, and individual health.';

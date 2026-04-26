/// Four-mode scheduled-task taxonomy from SemaClaw §3.6 — locked in
/// CLAUDE.md §8 and DECISIONS row 28.
///
/// Stored as a string in the existing `reminders.mode` text column;
/// no schema migration needed. Use [parse] / [serialise] at the
/// repo boundary.
enum ScheduleMode {
  /// Zero-token; user-visible at fire time. AlarmManager fires at
  /// `whenTs`; flutter_local_notifications renders a notification from
  /// a stored template + payload variables. The common case — flea,
  /// heartworm, vaccine, weight-check reminders.
  notification,

  /// Zero-token; no notification. WorkManager runs a registered Dart
  /// task at fire time. Side effects only — write a journal entry,
  /// refresh embeddings, vacuum stale FTS rows. Battery-aware,
  /// condition-gated.
  script,

  /// LLM call; writes a markdown entry under `wiki/<id>/digest/`. No
  /// notification. The Phase 3.7 weekly-summary runner is the
  /// canonical instance.
  synthesis,

  /// LLM call + notification post-fire. Reserved for Phase 5+ Pro
  /// features (e.g. "Loki's weekly summary is ready"). The Phase 4
  /// dispatcher stubs this branch with `UnimplementedError` so the
  /// switch-on-mode is exhaustive without dragging Pro-tier code in.
  synthesisNotify,
}

extension ScheduleModeSerialise on ScheduleMode {
  /// Stable wire string for the `reminders.mode` column. Matches the
  /// enum-name literal so future Dart features that lean on the same
  /// (e.g. `enum.byName`) work without a translation layer.
  String serialise() => name;
}

/// Parses a wire string back into a [ScheduleMode]. Throws
/// [ArgumentError] on unknown input — the agent's `schedule_reminder`
/// tool depends on rejecting unknown modes rather than silently
/// downgrading (DECISIONS row 28).
ScheduleMode parseScheduleMode(String raw) {
  for (final m in ScheduleMode.values) {
    if (m.name == raw) return m;
  }
  throw ArgumentError.value(
    raw,
    'mode',
    'Unknown ScheduleMode. Expected one of '
        '${ScheduleMode.values.map((m) => m.name).join(', ')}.',
  );
}

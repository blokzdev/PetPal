import '../../data/repos/reminder_repo.dart';
import '../../platform/alarm_scheduler.dart';
import '../../platform/work_scheduler.dart';
import 'schedule_mode.dart';

/// Scheduling facade. Given a `ReminderRow`, picks the right
/// platform trigger:
///
/// * `notification` → `AlarmScheduler` (exact-time wakeup; falls
///   back to inexact when SCHEDULE_EXACT_ALARM denied — DECISIONS
///   row 31).
/// * `script` / `synthesis` / `synthesisNotify` → `WorkScheduler`
///   (battery- and condition-aware background work).
///
/// Sits at the harness level rather than `lib/platform/` because the
/// routing decision is mode-driven (a harness concept), not
/// platform-driven.
class ReminderScheduler {
  ReminderScheduler({
    required AlarmScheduler alarms,
    required WorkScheduler work,
  })  : _alarms = alarms,
        _work = work;

  final AlarmScheduler _alarms;
  final WorkScheduler _work;

  /// Arm the platform trigger for [row]. Returns the [AlarmArmResult]
  /// for `notification` mode (so the UI can decide whether to surface
  /// the inexact-fallback banner) and `null` for the WorkManager-
  /// backed modes where exact/inexact doesn't apply.
  Future<AlarmArmResult?> arm(ReminderRow row) async {
    switch (row.mode) {
      case ScheduleMode.notification:
        return _alarms.arm(reminderId: row.id, whenTs: row.whenTs);
      case ScheduleMode.script:
      case ScheduleMode.synthesis:
      case ScheduleMode.synthesisNotify:
        await _work.arm(reminderId: row.id, whenTs: row.whenTs);
        return null;
    }
  }

  /// Cancel the platform trigger for [row]. Routes to the same
  /// backend that [arm] would have used.
  Future<void> cancel(ReminderRow row) async {
    switch (row.mode) {
      case ScheduleMode.notification:
        await _alarms.cancel(row.id);
      case ScheduleMode.script:
      case ScheduleMode.synthesis:
      case ScheduleMode.synthesisNotify:
        await _work.cancel(row.id);
    }
  }
}

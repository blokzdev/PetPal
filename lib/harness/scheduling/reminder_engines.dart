/// Pluggable engines that [ReminderDispatcher] routes to based on
/// [ScheduleMode]. Phase 4 task 4.6 supplies the platform-coupled
/// implementations under `lib/platform/`; tests substitute fakes
/// without touching real notifications, alarms, or work managers.
library;

/// Renders a system notification at fire time. The
/// platform-coupled implementation wraps `flutter_local_notifications`.
abstract class NotificationsEngine {
  /// Show a notification now. [reminderId] is the row id from the
  /// `reminders` table — used as the system notification id so a
  /// follow-up reschedule replaces rather than duplicates.
  Future<void> show({
    required int reminderId,
    required String title,
    required String body,
  });
}

/// Runs a registered Dart task for `mode = script` reminders.
/// The platform-coupled implementation is keyed off WorkManager
/// callbacks; tests substitute a registry that records calls.
abstract class ScriptEngine {
  /// [taskId] indexes into the engine's task registry (e.g.
  /// `weight_chart_rollup`). [args] are deserialised from the
  /// reminder payload by [ReminderDispatcher].
  Future<void> run({
    required String taskId,
    required Map<String, Object?> args,
  });
}

/// Runs an LLM-backed background task for `mode = synthesis`
/// reminders. The Phase 3.7 weekly-digest runner is the canonical
/// instance — Phase 4 wraps it behind this interface.
abstract class SynthesisEngine {
  /// [petId] scopes the synthesis to one pet's journal. [args] are
  /// deserialised from the reminder payload (e.g. `{'window': '7d'}`).
  Future<void> run({
    required int petId,
    required Map<String, Object?> args,
  });
}

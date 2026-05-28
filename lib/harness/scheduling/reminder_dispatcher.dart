import '../../data/repos/reminder_repo.dart';
import 'reminder_engines.dart';
import 'schedule_mode.dart';

/// Switches a fired reminder to the right engine based on
/// [ScheduleMode]. The platform layer (alarm receiver, WorkManager
/// callback) calls [fire] with the reminder id at fire time; the
/// dispatcher does the database lookup, mode dispatch, and payload
/// destructuring. The engines themselves stay platform-coupled but
/// mode-agnostic.
///
/// `synthesisNotify` is intentionally not implemented in Phase 4 —
/// concrete consumer is reserved for the Phase 7+ Pro tier
/// (DECISIONS row 28). The branch is kept exhaustive so the switch
/// is type-checked, and throwing a clear `UnimplementedError` at
/// runtime is preferred over silently swallowing it.
class ReminderDispatcher {
  ReminderDispatcher({
    required ReminderRepo repo,
    required NotificationsEngine notifications,
    required ScriptEngine scripts,
    required SynthesisEngine synthesis,
  })  : _repo = repo,
        _notifications = notifications,
        _scripts = scripts,
        _synthesis = synthesis;

  final ReminderRepo _repo;
  final NotificationsEngine _notifications;
  final ScriptEngine _scripts;
  final SynthesisEngine _synthesis;

  /// Fire the reminder identified by [reminderId]. Returns silently
  /// if the row was deleted between scheduling and fire (the user
  /// rescheduled, deleted via the UI, or the pet was removed).
  Future<void> fire(int reminderId) async {
    final row = await _repo.getById(reminderId);
    if (row == null) return;

    switch (row.mode) {
      case ScheduleMode.notification:
        // Notification reminders carry their pre-rendered title/body in
        // the payload. Phase 4's notification-template renderer (task
        // 4.8) substitutes `{pet_name}` etc. at create time, not at
        // fire time — the tradeoff is that pet-name changes don't
        // propagate to existing reminders, which is acceptable for the
        // typical days-to-weeks reminder lifetime.
        final title = row.payload['title'] as String? ?? 'Reminder';
        final body = row.payload['body'] as String? ?? '';
        await _notifications.show(
          reminderId: row.id,
          title: title,
          body: body,
        );

      case ScheduleMode.script:
        // Script payload shape: `{ "taskId": "...", "args": {...} }`.
        // taskId falls back to the row's `kind` so callers can omit it
        // for the canonical 1:1 mapping (kind = task id).
        final taskId = row.payload['taskId'] as String? ?? row.kind;
        final rawArgs = row.payload['args'];
        final args = rawArgs is Map<String, Object?>
            ? rawArgs
            : const <String, Object?>{};
        await _scripts.run(taskId: taskId, args: args);

      case ScheduleMode.synthesis:
        // Synthesis payload shape: `{ "args": {...} }`. The engine
        // owns its journal-write semantics — the dispatcher does not
        // see LLM output.
        final rawArgs = row.payload['args'];
        final args = rawArgs is Map<String, Object?>
            ? rawArgs
            : const <String, Object?>{};
        await _synthesis.run(petId: row.petId, args: args);

      case ScheduleMode.synthesisNotify:
        throw UnimplementedError(
          'synthesisNotify dispatcher branch — Phase 7+ Pro-tier '
          'weekly-summary notifications. See DECISIONS row 28.',
        );
    }
  }
}

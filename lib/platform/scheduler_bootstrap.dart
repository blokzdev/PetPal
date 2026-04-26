import '../data/db/connection.dart';
import '../data/db/database.dart';
import '../data/repos/reminder_repo.dart';
import '../harness/scheduling/reminder_dispatcher.dart';
import '../harness/scheduling/reminder_engines.dart';
import 'notifications_service.dart';
import 'scheduler_log.dart';

/// Bootstrap a [ReminderDispatcher] from scratch, intended for the
/// alarm/work callback isolates. AlarmManager and WorkManager fire
/// callbacks in a fresh Dart isolate without the app's
/// `ProviderScope`, so we construct the minimum harness graph inline.
///
/// Phase 4 only wires `notification` mode through a real engine —
/// `script` and `synthesis` reminders aren't created by the user-
/// facing flows yet, so their callback paths route to no-op stubs
/// that just log. Phase 5+ replaces those with the real script
/// registry and an extracted synthesis engine.
Future<void> bootstrapAndFire(int reminderId) async {
  schedulerLog('dispatch_bootstrap_begin', fields: {
    'reminder_id': reminderId,
  });
  AppDatabase? database;
  try {
    database = await openAppDatabase();
    final notifications = NotificationsService();
    await notifications.initialize();

    final dispatcher = ReminderDispatcher(
      repo: ReminderRepo(db: database),
      notifications: notifications,
      scripts: _NoopScriptEngine(),
      synthesis: _NoopSynthesisEngine(),
    );

    schedulerLog('dispatch', fields: {'reminder_id': reminderId});
    await dispatcher.fire(reminderId);
    schedulerLog('dispatch_done', fields: {'reminder_id': reminderId});
  } catch (e, st) {
    schedulerLog(
      'dispatch_error',
      fields: {'reminder_id': reminderId},
      error: e,
      stackTrace: st,
    );
    rethrow;
  } finally {
    await database?.close();
  }
}

class _NoopScriptEngine implements ScriptEngine {
  @override
  Future<void> run({
    required String taskId,
    required Map<String, Object?> args,
  }) async {
    schedulerLog('script_noop', fields: {'task_id': taskId});
  }
}

class _NoopSynthesisEngine implements SynthesisEngine {
  @override
  Future<void> run({
    required int petId,
    required Map<String, Object?> args,
  }) async {
    schedulerLog('synthesis_noop', fields: {'pet_id': petId});
  }
}

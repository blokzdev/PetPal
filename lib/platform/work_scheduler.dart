import 'package:workmanager/workmanager.dart';

import 'scheduler_bootstrap_registry.dart';
import 'scheduler_log.dart';

/// WorkManager unique-task name prefix. WorkManager keys jobs by
/// string id; the convention is `petpal.reminder.<id>` so a
/// reschedule (re-register with `existingWorkPolicy: replace`)
/// targets the same row idempotently.
const _taskPrefix = 'petpal.reminder.';

/// WorkManager task type — single name; the dispatcher looks up the
/// reminder row and switches on mode internally.
const _taskType = 'fire_reminder';

/// Wraps `workmanager` for `mode ∈ {script, synthesis, synthesisNotify}`
/// reminders. WorkManager runs in the OS background-work scheduler:
/// battery-aware, network-condition-aware, doze-respecting. Drift is
/// up to ~10s in foreground, longer under doze.
class WorkScheduler {
  WorkScheduler({WorkmanagerBindings? bindings})
      : _bindings = bindings ?? const _DefaultWorkmanagerBindings();

  final WorkmanagerBindings _bindings;

  /// Initialise the workmanager + register the callback dispatcher.
  /// Idempotent (workmanager guards against double-init internally).
  /// Called once from `main.dart`.
  Future<void> initialize() async {
    await _bindings.initialize();
    schedulerLog('work_initialised', fields: {});
  }

  /// Schedule a one-shot fire of [reminderId] at [whenTs]. WorkManager
  /// computes the delay relative to now; if [whenTs] is in the past,
  /// the delay clamps to zero (job runs ASAP).
  Future<void> arm({
    required int reminderId,
    required DateTime whenTs,
  }) async {
    var delay = whenTs.difference(DateTime.now());
    if (delay.isNegative) delay = Duration.zero;
    await _bindings.registerOneOff(
      uniqueName: '$_taskPrefix$reminderId',
      taskName: _taskType,
      initialDelay: delay,
      inputData: <String, dynamic>{'reminder_id': reminderId},
    );
    schedulerLog('schedule', fields: {
      'reminder_id': reminderId,
      'when_ts': whenTs,
      'engine': 'workmanager',
      'delay_ms': delay.inMilliseconds,
    });
  }

  Future<void> cancel(int reminderId) async {
    await _bindings.cancelByUniqueName('$_taskPrefix$reminderId');
    schedulerLog('schedule_cancel', fields: {
      'reminder_id': reminderId,
      'engine': 'workmanager',
    });
  }
}

/// Test seam over the `Workmanager` global. Tests substitute a fake.
abstract class WorkmanagerBindings {
  Future<void> initialize();
  Future<void> registerOneOff({
    required String uniqueName,
    required String taskName,
    required Duration initialDelay,
    required Map<String, dynamic> inputData,
  });
  Future<void> cancelByUniqueName(String uniqueName);
}

class _DefaultWorkmanagerBindings implements WorkmanagerBindings {
  const _DefaultWorkmanagerBindings();

  @override
  Future<void> initialize() async {
    await Workmanager().initialize(workmanagerCallbackDispatcher);
  }

  @override
  Future<void> registerOneOff({
    required String uniqueName,
    required String taskName,
    required Duration initialDelay,
    required Map<String, dynamic> inputData,
  }) async {
    await Workmanager().registerOneOffTask(
      uniqueName,
      taskName,
      initialDelay: initialDelay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      inputData: inputData,
    );
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    await Workmanager().cancelByUniqueName(uniqueName);
  }
}

/// Top-level WorkManager callback dispatcher. Must be declared at
/// top level + annotated `@pragma('vm:entry-point')` so R8 doesn't
/// strip it. The Phase 6 ProGuard rules also keep this symbol —
/// DECISIONS row 30.
@pragma('vm:entry-point')
void workmanagerCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != _taskType) return false;
    final reminderId = inputData?['reminder_id'] as int?;
    if (reminderId == null) return false;

    schedulerLog('fire', fields: {
      'reminder_id': reminderId,
      'engine': 'workmanager',
      'task': task,
    });

    final fire = schedulerBootstrap;
    if (fire == null) {
      schedulerLog('fire_no_bootstrap', fields: {'reminder_id': reminderId});
      return false;
    }
    try {
      await fire(reminderId);
      return true;
    } catch (e, st) {
      schedulerLog(
        'fire_error',
        fields: {
          'reminder_id': reminderId,
          'engine': 'workmanager',
        },
        error: e,
        stackTrace: st,
      );
      return false;
    }
  });
}

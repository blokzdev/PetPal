import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

import 'scheduler_bootstrap_registry.dart';
import 'scheduler_log.dart';

/// Result of an arm() call — exposes the actual mode used so the UI
/// can surface the inexact-fallback note (DECISIONS row 31). Phase 4
/// task 4.10's reminders screen reads this to decide whether to show
/// the "may fire up to ~10 min late" banner.
enum AlarmArmResult {
  /// `SCHEDULE_EXACT_ALARM` granted — alarm will fire within seconds
  /// of `whenTs`.
  exact,

  /// Permission denied or revoked. Fell back to inexact (≤ ~10 min
  /// drift). Surface the calm-not-alarmist banner from VOICE.md.
  inexactFallback,

  /// Both attempts returned false from AlarmManager — no alarm armed.
  /// Caller must surface a hard error; this state is rare and
  /// generally indicates the platform plugin failed to register.
  failed,
}

/// Wraps `android_alarm_manager_plus` for `mode=notification`
/// reminders. AlarmManager wakes the device at exact wall-clock time
/// and fires a top-level Dart callback even while the app is killed.
///
/// Android 14 introduced runtime-revocable `SCHEDULE_EXACT_ALARM`. We
/// always try exact first; if denied, we fall back to inexact rather
/// than blocking the user (DECISIONS row 31). The fallback path
/// matters more than the permission prompt — never block the user
/// from using the app over a permission they may not want to grant.
class AlarmScheduler {
  AlarmScheduler({AlarmManagerBindings? bindings})
      : _bindings = bindings ?? const _DefaultAlarmManagerBindings();

  final AlarmManagerBindings _bindings;

  Future<AlarmArmResult> arm({
    required int reminderId,
    required DateTime whenTs,
  }) async {
    final exactOk = await _bindings.oneShotAt(
      whenTs: whenTs,
      id: reminderId,
      exact: true,
    );
    if (exactOk) {
      schedulerLog('schedule', fields: {
        'reminder_id': reminderId,
        'when_ts': whenTs,
        'engine': 'alarm_manager',
        'exact': true,
      });
      return AlarmArmResult.exact;
    }

    schedulerLog('schedule_exact_denied', fields: {
      'reminder_id': reminderId,
      'when_ts': whenTs,
    });

    final inexactOk = await _bindings.oneShotAt(
      whenTs: whenTs,
      id: reminderId,
      exact: false,
    );
    if (inexactOk) {
      schedulerLog('schedule', fields: {
        'reminder_id': reminderId,
        'when_ts': whenTs,
        'engine': 'alarm_manager',
        'exact': false,
      });
      return AlarmArmResult.inexactFallback;
    }

    schedulerLog('schedule_failed', fields: {
      'reminder_id': reminderId,
      'when_ts': whenTs,
      'engine': 'alarm_manager',
    });
    return AlarmArmResult.failed;
  }

  Future<void> cancel(int reminderId) async {
    await _bindings.cancel(reminderId);
    schedulerLog('schedule_cancel', fields: {
      'reminder_id': reminderId,
      'engine': 'alarm_manager',
    });
  }
}

/// Test seam over `AndroidAlarmManager`. The real implementation
/// forwards to the static plugin API; tests substitute a fake.
abstract class AlarmManagerBindings {
  Future<bool> oneShotAt({
    required DateTime whenTs,
    required int id,
    required bool exact,
  });
  Future<void> cancel(int id);
}

class _DefaultAlarmManagerBindings implements AlarmManagerBindings {
  const _DefaultAlarmManagerBindings();

  @override
  Future<bool> oneShotAt({
    required DateTime whenTs,
    required int id,
    required bool exact,
  }) =>
      AndroidAlarmManager.oneShotAt(
        whenTs,
        id,
        alarmCallback,
        exact: exact,
        wakeup: true,
        rescheduleOnReboot: true,
        params: <String, Object>{'reminder_id': id},
      );

  @override
  Future<void> cancel(int id) async {
    await AndroidAlarmManager.cancel(id);
  }
}

/// Top-level callback invoked by AlarmManager at fire time. Must be
/// declared at top level + annotated `@pragma('vm:entry-point')` so
/// R8 doesn't strip it (DECISIONS row 30 ProGuard keep rule).
@pragma('vm:entry-point')
void alarmCallback(int reminderId, [Map<String, dynamic>? params]) async {
  schedulerLog('fire', fields: {
    'reminder_id': reminderId,
    'engine': 'alarm_manager',
  });
  final fire = schedulerBootstrap;
  if (fire == null) {
    schedulerLog('fire_no_bootstrap', fields: {'reminder_id': reminderId});
    return;
  }
  await fire(reminderId);
}

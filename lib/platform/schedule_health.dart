import 'package:permission_handler/permission_handler.dart';

import 'scheduler_log.dart';

/// Snapshot of the three Android permissions that determine whether
/// reminders fire reliably. Read once at Reminders-screen open, plus
/// after each `request*` call so the UI updates inline.
class ScheduleHealth {
  const ScheduleHealth({
    required this.exactAlarmsAllowed,
    required this.batteryOptimizationDisabled,
    required this.notificationsAllowed,
  });

  /// `SCHEDULE_EXACT_ALARM` — when false, [AlarmScheduler] falls back
  /// to inexact (≤ ~10 min drift) per DECISIONS row 31. UI surfaces a
  /// calm banner offering to fix it in system settings.
  final bool exactAlarmsAllowed;

  /// Battery-optimisation exemption (a.k.a. ignore-battery-optimisations)
  /// — without it, Doze mode can delay our alarms indefinitely. UI
  /// shows the first-schedule prompt to walk the user through
  /// granting it; the prompt only appears once
  /// (`BatteryExemptionPromptStorage` persists the seen flag).
  final bool batteryOptimizationDisabled;

  /// `POST_NOTIFICATIONS` — Android 13+ runtime grant. When false,
  /// `mode=notification` reminders fire silently (the alarm runs but
  /// `flutter_local_notifications.show` is a no-op). UI surfaces a
  /// calm banner.
  final bool notificationsAllowed;

  bool get fullyHealthy =>
      exactAlarmsAllowed &&
      batteryOptimizationDisabled &&
      notificationsAllowed;
}

/// Test seam over `permission_handler`. The production implementation
/// forwards to the static plugin API; tests substitute a fake.
abstract class ScheduleHealthService {
  Future<ScheduleHealth> check();
  Future<void> requestExactAlarmPermission();
  Future<void> requestBatteryOptimizationExemption();
  Future<void> requestNotificationPermission();
}

class PlatformScheduleHealthService implements ScheduleHealthService {
  const PlatformScheduleHealthService();

  @override
  Future<ScheduleHealth> check() async {
    final results = await Future.wait([
      Permission.scheduleExactAlarm.status,
      Permission.ignoreBatteryOptimizations.status,
      Permission.notification.status,
    ]);
    final health = ScheduleHealth(
      exactAlarmsAllowed: results[0].isGranted,
      batteryOptimizationDisabled: results[1].isGranted,
      notificationsAllowed: results[2].isGranted,
    );
    schedulerLog('health_check', fields: {
      'exact': health.exactAlarmsAllowed,
      'battery_ok': health.batteryOptimizationDisabled,
      'notifications': health.notificationsAllowed,
    });
    return health;
  }

  @override
  Future<void> requestExactAlarmPermission() async {
    final status = await Permission.scheduleExactAlarm.request();
    schedulerLog('request_exact_alarm', fields: {
      'granted': status.isGranted,
    });
  }

  @override
  Future<void> requestBatteryOptimizationExemption() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    schedulerLog('request_battery_exemption', fields: {
      'granted': status.isGranted,
    });
  }

  @override
  Future<void> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    schedulerLog('request_notification', fields: {
      'granted': status.isGranted,
    });
  }
}

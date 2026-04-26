import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../harness/scheduling/reminder_engines.dart';
import 'scheduler_log.dart';

/// Single-channel notification renderer. One channel covers every
/// reminder kind because Android channels are user-controlled —
/// per-kind channels would let a user mute "weight checks" but keep
/// "vaccine due" on, which sounds nice in theory but in practice gets
/// confused with the four canonical kinds we ship in 4.8 and adds
/// settings noise. Phase 5+ may split this if there's evidence we
/// need it.
const _channelId = 'petpal.reminders';
const _channelName = 'Reminders';
const _channelDescription =
    'Pet care reminders — flea, heartworm, vaccine, weight checks, and '
    'anything else you ask PetPal to remind you about.';

/// Wraps `flutter_local_notifications` to satisfy
/// [NotificationsEngine]. Initialise once at app startup
/// (`NotificationsService.initialize()` from `main.dart`); after that
/// the same instance is reused for every dispatched reminder.
class NotificationsService implements NotificationsEngine {
  NotificationsService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialised = false;

  /// Initialise the plugin + create the Android channel. Idempotent.
  Future<void> initialize() async {
    if (_initialised) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );
    _initialised = true;
    schedulerLog('notifications_initialised', fields: {
      'channel': _channelId,
    });
  }

  @override
  Future<void> show({
    required int reminderId,
    required String title,
    required String body,
  }) async {
    if (!_initialised) await initialize();
    await _plugin.show(
      reminderId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
    schedulerLog('notification_post', fields: {
      'reminder_id': reminderId,
      'channel': _channelId,
    });
  }

  /// Cancel any pending notification for this reminder id. Used when
  /// the user reschedules or deletes a reminder.
  Future<void> cancel(int reminderId) async {
    await _plugin.cancel(reminderId);
    schedulerLog('notification_cancel', fields: {
      'reminder_id': reminderId,
    });
  }
}

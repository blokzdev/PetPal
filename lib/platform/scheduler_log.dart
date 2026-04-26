/// Structured log channel for the reminder lifecycle. Every platform
/// boundary crossing — schedule, fire, dispatch, notification post,
/// boot re-arm, doze resume — emits one line tagged
/// `petpal.scheduler` so an `adb logcat` (or Logcat Reader on the
/// phone) trace can pinpoint where a reminder failed in seconds.
///
/// Format: `event=<event> key=value key=value …`. Values are coerced
/// to a stable string form so grep / awk / jq don't have to handle
/// shape variation between calls.
///
/// This lives in `lib/platform/` because the boundary crossings are
/// platform-coupled, but the helper itself is pure Dart and works in
/// `flutter test` for assertion-friendly testing.
library;

import 'dart:developer' as developer;

/// Emit one structured log line. [event] is the boundary id (e.g.
/// `schedule`, `fire`, `dispatch`, `notification_post`, `boot_rearm`).
/// [fields] is the key/value payload — keys should be snake_case and
/// stable across releases.
void schedulerLog(
  String event, {
  Map<String, Object?> fields = const {},
  Object? error,
  StackTrace? stackTrace,
}) {
  final buf = StringBuffer('event=$event');
  fields.forEach((k, v) {
    buf.write(' $k=${_format(v)}');
  });
  developer.log(
    buf.toString(),
    name: 'petpal.scheduler',
    error: error,
    stackTrace: stackTrace,
  );
}

String _format(Object? v) {
  if (v == null) return 'null';
  if (v is DateTime) return v.toUtc().toIso8601String();
  if (v is bool) return v ? 'true' : 'false';
  // Quote anything containing whitespace so grep -E '… key=value …'
  // patterns stay tractable.
  final s = v.toString();
  if (s.contains(' ') || s.contains('=')) {
    return '"${s.replaceAll('"', r'\"')}"';
  }
  return s;
}

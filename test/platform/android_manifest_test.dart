import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Manifest-invariants regression test (DECISIONS row 33).
///
/// Native plugins (android_alarm_manager_plus, flutter_local_notifications,
/// workmanager) ship their code as AARs but rely on the consumer app to
/// declare receivers / services / permissions in the merged manifest.
/// Forgetting one of these declarations is invisible to `flutter analyze`
/// and `flutter test` — it only surfaces as a runtime PlatformException
/// when the user actually tries to schedule a reminder. The Phase 4
/// hotfix found this the hard way.
///
/// This test parses `android/app/src/main/AndroidManifest.xml` (literal
/// string match — XML namespace is consistent project-wide) and
/// asserts every component the scheduling stack depends on is present.
/// New plugin bumps that change manifest requirements MUST update this
/// test in the same commit (DECISIONS row 33 checklist item).
void main() {
  late String manifest;

  setUpAll(() {
    final file = File(
      '${Directory.current.path}/android/app/src/main/AndroidManifest.xml',
    );
    expect(file.existsSync(), isTrue,
        reason: 'AndroidManifest.xml must exist at the canonical path');
    manifest = file.readAsStringSync();
  });

  group('Phase 4 scheduling permissions', () {
    test('POST_NOTIFICATIONS — required for Android 13+ reminder fires', () {
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    });

    test('SCHEDULE_EXACT_ALARM — exact-time wakeups on Android 12+', () {
      expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    });

    test('USE_EXACT_ALARM — Android 13+ alternative without runtime grant',
        () {
      expect(manifest, contains('android.permission.USE_EXACT_ALARM'));
    });

    test('RECEIVE_BOOT_COMPLETED — reboot re-arm of pending reminders', () {
      expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    });

    test('WAKE_LOCK — required by android_alarm_manager_plus to wake the '
        'device for exact alarms', () {
      expect(manifest, contains('android.permission.WAKE_LOCK'));
    });
  });

  group('android_alarm_manager_plus components (DECISIONS row 33 hotfix)', () {
    test('AlarmService — JobIntentService that runs the Dart callback', () {
      expect(
        manifest,
        contains('dev.fluttercommunity.plus.androidalarmmanager.AlarmService'),
      );
      // Service must declare the BIND_JOB_SERVICE permission so
      // AlarmManager can dispatch into it.
      expect(
        manifest,
        contains('android.permission.BIND_JOB_SERVICE'),
      );
    });

    test('AlarmBroadcastReceiver — fires when an exact alarm comes due', () {
      expect(
        manifest,
        contains(
          'dev.fluttercommunity.plus.androidalarmmanager.AlarmBroadcastReceiver',
        ),
      );
    });

    test(
        'RebootBroadcastReceiver — re-arms pending alarms on BOOT_COMPLETED',
        () {
      // The receiver itself must be declared.
      expect(
        manifest,
        contains(
          'dev.fluttercommunity.plus.androidalarmmanager.RebootBroadcastReceiver',
        ),
      );
      // …with a BOOT_COMPLETED intent-filter so Android delivers the
      // boot intent to it.
      expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
    });
  });
}

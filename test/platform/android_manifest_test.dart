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

  group('in_app_purchase plugin-bump (Phase 7 task C.1, DECISIONS row 33)', () {
    test('NO new manifest components required — Play Billing handles '
        'permissions internally', () {
      // The in_app_purchase_android plugin's auto-merged manifest is
      // empty (just `<manifest>`); the example app declares no
      // billing-specific permissions or components beyond the standard
      // Flutter activity. Play Billing Library handles BILLING
      // internally as of Billing v3+ (the legacy
      // `com.android.vending.BILLING` permission is auto-granted and
      // doesn't need to be requested in our manifest).
      //
      // This test exists only to record that the bump's plugin-
      // checklist (DECISIONS row 33) was performed and yielded
      // zero manifest changes. If a future plugin upgrade adds new
      // components, the next bump's audit will see this test
      // unchanged → run the full checklist again.
      expect(
        manifest.contains('com.android.vending.BILLING'),
        isFalse,
        reason: 'BILLING permission should NOT appear — Play Billing '
            'Library handles it internally, and explicitly declaring '
            'it would re-trigger the legacy auto-grant warning.',
      );
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

  group('supabase_flutter plugin-bump (Phase 7 task H.1.a, DECISIONS row 33)',
      () {
    test('Supabase magic-link return — petpal:// URL scheme registered', () {
      // The custom URL scheme is the load-bearing piece of the deep-link
      // intent filter. supabase_flutter's bundled app_links integration
      // listens for VIEW intents matching this scheme/host pair and
      // surfaces them as `signedIn` events on the auth-state stream.
      // Without this declaration, the magic-link tap from email opens
      // the system browser instead of returning to PetPal — sign-in
      // appears to silently fail to the user.
      expect(manifest, contains('android:scheme="petpal"'));
      expect(manifest, contains('android:host="login-callback"'));
    });

    test('Deep-link intent filter has VIEW + BROWSABLE + DEFAULT categories',
        () {
      // The intent filter MUST carry all three signals so Android
      // routes the URI to MainActivity:
      //   - VIEW so the system asks "who handles this URI?"
      //   - BROWSABLE so links from email apps / browsers count as
      //     valid sources (without it, only in-app intents work)
      //   - DEFAULT so PetPal is offered as a candidate without an
      //     explicit component selection
      // Removing any one of these silently breaks the magic-link
      // return path — surfaced only on real-device tap of the
      // emailed link.
      expect(manifest, contains('android.intent.action.VIEW'));
      expect(manifest, contains('android.intent.category.BROWSABLE'));
      expect(manifest, contains('android.intent.category.DEFAULT'));
    });

    test(
        'No new permissions — supabase_flutter rides INTERNET '
        '(already declared)', () {
      // The plugin-bump checklist for supabase_flutter 2.12.4 found
      // zero new permission requirements beyond INTERNET (already
      // declared for the Anthropic API + future cloud sync). The
      // package's example AndroidManifest declares only the deep-link
      // intent filter and INTERNET. No services, no receivers, no
      // providers, no foreground-service permissions.
      //
      // This test exists to record that the H.1.a plugin-bump
      // checklist (DECISIONS row 33) was performed. If a future
      // supabase_flutter upgrade adds new components, the next bump's
      // audit will see this assertion unchanged → run the full
      // checklist again.
      expect(manifest, contains('android.permission.INTERNET'));
    });
  });
}

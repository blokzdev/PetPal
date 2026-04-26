import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/widgets/battery_exemption_prompt.dart';
import 'package:petpal/platform/schedule_health.dart';
import 'package:petpal/platform/settings_storage.dart';

class _FakeHealth implements ScheduleHealthService {
  _FakeHealth({this.batteryOk = true});
  bool batteryOk;
  int requestBatteryCount = 0;

  @override
  Future<ScheduleHealth> check() async => ScheduleHealth(
        exactAlarmsAllowed: true,
        batteryOptimizationDisabled: batteryOk,
        notificationsAllowed: true,
      );

  @override
  Future<void> requestBatteryOptimizationExemption() async {
    requestBatteryCount += 1;
    batteryOk = true;
  }

  @override
  Future<void> requestExactAlarmPermission() async {}
  @override
  Future<void> requestNotificationPermission() async {}
}

Widget _hostWith({
  required ScheduleHealthService health,
  required SettingsStorage settings,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            child: const Text('trigger'),
            onPressed: () => BatteryExemptionPrompt.maybeShow(
              context: context,
              settings: settings,
              health: health,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('first call with permission denied shows the prompt and persists '
      'the seen flag', (tester) async {
    final settings = InMemorySettingsStorage();
    final health = _FakeHealth(batteryOk: false);

    await tester.pumpWidget(_hostWith(health: health, settings: settings));
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('Let reminders fire on time'), findsOneWidget);
    // Static copy — no pet-name interpolation per VOICE.md §5.
    expect(
      find.textContaining('PetPal in the list and tap'),
      findsOneWidget,
    );

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(find.text('Let reminders fire on time'), findsNothing);
    expect(health.requestBatteryCount, 1);
    expect(
      await settings.getBool('battery_exemption_prompt_seen'),
      isTrue,
    );
  });

  testWidgets('second call after seen flag is set is a no-op', (tester) async {
    final settings = InMemorySettingsStorage(
      const {'battery_exemption_prompt_seen': true},
    );
    final health = _FakeHealth(batteryOk: false);

    await tester.pumpWidget(_hostWith(health: health, settings: settings));
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('Let reminders fire on time'), findsNothing);
    expect(health.requestBatteryCount, 0);
  });

  testWidgets('first call with permission already granted does not show but '
      'still records seen flag (so we never bother on this device)',
      (tester) async {
    final settings = InMemorySettingsStorage();
    final health = _FakeHealth();

    await tester.pumpWidget(_hostWith(health: health, settings: settings));
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('Let reminders fire on time'), findsNothing);
    expect(
      await settings.getBool('battery_exemption_prompt_seen'),
      isTrue,
    );
  });

  testWidgets('"Not now" dismisses without requesting and still records seen',
      (tester) async {
    final settings = InMemorySettingsStorage();
    final health = _FakeHealth(batteryOk: false);

    await tester.pumpWidget(_hostWith(health: health, settings: settings));
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(health.requestBatteryCount, 0);
    expect(
      await settings.getBool('battery_exemption_prompt_seen'),
      isTrue,
      reason:
          'recording the flag on dismiss prevents re-pestering the user '
          'the next time they save a reminder; they can always re-enable '
          'via the banner on the Reminders screen (task 4.10)',
    );
  });
}

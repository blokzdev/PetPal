import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/harness/scheduling/notification_template.dart';
import 'package:petpal/harness/scheduling/reminder_kinds.dart';
import 'package:petpal/main.dart';
import 'package:petpal/platform/alarm_scheduler.dart';
import 'package:petpal/platform/schedule_health.dart';
import 'package:petpal/platform/work_scheduler.dart';

import '../../_helpers/fake_api_key_storage.dart';
import '../../_helpers/scripted_llm_client.dart';
import '../../_helpers/test_provider_scope.dart';

/// In-memory bindings so AlarmScheduler / WorkScheduler don't try to
/// talk to native plugins under `flutter test`.
class _NoopAlarmBindings implements AlarmManagerBindings {
  @override
  Future<bool> oneShotAt(
          {required DateTime whenTs,
          required int id,
          required bool exact}) async =>
      true;
  @override
  Future<void> cancel(int id) async {}
}

class _NoopWorkBindings implements WorkmanagerBindings {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> registerOneOff({
    required String uniqueName,
    required String taskName,
    required Duration initialDelay,
    required Map<String, dynamic> inputData,
  }) async {}
  @override
  Future<void> cancelByUniqueName(String uniqueName) async {}
}

class _FakeHealth implements ScheduleHealthService {
  _FakeHealth({
    this.exact = true,
    this.battery = true,
    this.notifications = true,
  });
  bool exact;
  bool battery;
  bool notifications;

  @override
  Future<ScheduleHealth> check() async => ScheduleHealth(
        exactAlarmsAllowed: exact,
        batteryOptimizationDisabled: battery,
        notificationsAllowed: notifications,
      );

  @override
  Future<void> requestExactAlarmPermission() async {}
  @override
  Future<void> requestBatteryOptimizationExemption() async {}
  @override
  Future<void> requestNotificationPermission() async {}
}

void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  testWidgets('reminders screen — empty state interpolates the active pet name',
      (tester) async {
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          ...stack.overrides,
          alarmSchedulerProvider.overrideWithValue(
            AlarmScheduler(bindings: _NoopAlarmBindings()),
          ),
          workSchedulerProvider.overrideWithValue(
            WorkScheduler(bindings: _NoopWorkBindings()),
          ),
          notificationTemplatesProvider.overrideWithValue(
            InMemoryNotificationTemplates({
              for (final k in ReminderKind.values)
                k: NotificationTemplate(
                  title: k.label,
                  body: '${k.label} body for {pet_name}',
                ),
            }),
          ),
          scheduleHealthServiceProvider.overrideWithValue(_FakeHealth()),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Home → Reminders.
    await tester.tap(find.text('Reminders'));
    await tester.pumpAndSettle();

    // App-bar interpolates the active pet's name (VOICE.md §5).
    expect(find.text("Milo's reminders"), findsOneWidget);
    // Empty state.
    expect(
      find.textContaining('No reminders yet'),
      findsOneWidget,
    );
    // No banners — fully-healthy fake.
    expect(find.textContaining('may delay reminders'), findsNothing);
    expect(find.textContaining('may fire up to'), findsNothing);
  });

  testWidgets('reminders screen — surfaces all three banners when permissions '
      'are denied', (tester) async {
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );
    final health =
        _FakeHealth(exact: false, battery: false, notifications: false);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          ...stack.overrides,
          alarmSchedulerProvider.overrideWithValue(
            AlarmScheduler(bindings: _NoopAlarmBindings()),
          ),
          workSchedulerProvider.overrideWithValue(
            WorkScheduler(bindings: _NoopWorkBindings()),
          ),
          notificationTemplatesProvider.overrideWithValue(
            InMemoryNotificationTemplates({
              for (final k in ReminderKind.values)
                k: NotificationTemplate(
                  title: k.label,
                  body: '${k.label} body for {pet_name}',
                ),
            }),
          ),
          scheduleHealthServiceProvider.overrideWithValue(health),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reminders'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Android may delay reminders'),
      findsOneWidget,
    );
    expect(
      find.textContaining('may fire up to ~10 minutes late'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Notifications are off'),
      findsOneWidget,
    );
  });

  testWidgets('vaccine kind shows the canonical vaccineUiNote', (tester) async {
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          ...stack.overrides,
          alarmSchedulerProvider.overrideWithValue(
            AlarmScheduler(bindings: _NoopAlarmBindings()),
          ),
          workSchedulerProvider.overrideWithValue(
            WorkScheduler(bindings: _NoopWorkBindings()),
          ),
          notificationTemplatesProvider.overrideWithValue(
            InMemoryNotificationTemplates({
              for (final k in ReminderKind.values)
                k: NotificationTemplate(
                  title: k.label,
                  body: '${k.label} body for {pet_name}',
                ),
            }),
          ),
          scheduleHealthServiceProvider.overrideWithValue(_FakeHealth()),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reminders'));
    await tester.pumpAndSettle();

    // Tap FAB → add screen.
    await tester.tap(find.byIcon(Icons.add_alarm));
    await tester.pumpAndSettle();

    // Default kind is flea — no vaccine note yet.
    expect(find.textContaining('Confirm timing with your vet'), findsNothing);

    // Switch to vaccine kind.
    await tester.tap(find.byType(DropdownButtonFormField<ReminderKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vaccine').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Confirm timing with your vet'),
      findsOneWidget,
    );
  });
}

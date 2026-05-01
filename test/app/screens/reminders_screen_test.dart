import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:petpal/app/platform/haptics.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/harness/scheduling/notification_template.dart';
import 'package:petpal/harness/scheduling/reminder_kinds.dart';
import 'package:petpal/main.dart';
import 'package:petpal/platform/alarm_scheduler.dart';
import 'package:petpal/platform/schedule_health.dart';
import 'package:petpal/platform/settings_storage.dart';
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
    // Phase 6.6 task 6.6.A.3 — bottom nav replaces the home grid;
    // the inline Reminders section on Home only renders when the pet
    // has upcoming reminders, which doesn't help reach the empty
    // sub-page. Use the go_router programmatic path to navigate to
    // the Home-branch nested `/home/reminders` route directly. This
    // mirrors what a system-notification deep-link would do.
    unawaited(
      GoRouter.of(tester.element(find.byType(NavigationBar)))
          .push('/home/reminders'),
    );
    await tester.pumpAndSettle();

    // App-bar interpolates the active pet's name (VOICE.md §5).
    expect(find.text("Milo's reminders"), findsOneWidget);
    // Empty state.
    // Empty state — task 5.7 redesign. Heading is per-pet (VOICE.md
    // §5), body teaches what kinds of reminders to set.
    expect(find.text('No reminders for Milo yet.'), findsOneWidget);
    expect(
      find.textContaining('Heartworm. Flea treatment. Vaccines.'),
      findsOneWidget,
    );
    // CTA mirrors the FAB so the empty state has its own primary
    // affordance.
    expect(find.widgetWithText(FilledButton, 'Add reminder'), findsOneWidget);
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

    // Phase 6.6 task 6.6.A.3 — bottom nav replaces the home grid;
    // the inline Reminders section on Home only renders when the pet
    // has upcoming reminders, which doesn't help reach the empty
    // sub-page. Use the go_router programmatic path to navigate to
    // the Home-branch nested `/home/reminders` route directly. This
    // mirrors what a system-notification deep-link would do.
    unawaited(
      GoRouter.of(tester.element(find.byType(NavigationBar)))
          .push('/home/reminders'),
    );
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

    // Phase 6.6 task 6.6.A.3 — bottom nav replaces the home grid;
    // the inline Reminders section on Home only renders when the pet
    // has upcoming reminders, which doesn't help reach the empty
    // sub-page. Use the go_router programmatic path to navigate to
    // the Home-branch nested `/home/reminders` route directly. This
    // mirrors what a system-notification deep-link would do.
    unawaited(
      GoRouter.of(tester.element(find.byType(NavigationBar)))
          .push('/home/reminders'),
    );
    await tester.pumpAndSettle();

    // Tap FAB → add screen. Both the FAB and the empty-state PetButton
    // use the add_alarm icon (intentional action consistency, task 5.7).
    // Disambiguate to the FAB.
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.byIcon(PhosphorIconsRegular.bellRinging),
      ),
    );
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

  // -------------------------------------------------------------------
  // Task 5.8 — haptics. Asserts the light-impact haptic fires at the
  // two reminder commit points: schedule (on successful create) and
  // complete/cancel (on swipe-dismiss confirm). Counts via FakeHaptics
  // since HapticFeedback's platform channel is a no-op under test.
  // -------------------------------------------------------------------
  testWidgets('schedule-reminder fires a light haptic on successful save',
      (tester) async {
    final haptics = FakeHaptics();
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
          settingsStorageProvider.overrideWithValue(InMemorySettingsStorage()),
          hapticsProvider.overrideWithValue(haptics),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Phase 6.6 task 6.6.A.3 — bottom nav replaces the home grid;
    // the inline Reminders section on Home only renders when the pet
    // has upcoming reminders, which doesn't help reach the empty
    // sub-page. Use the go_router programmatic path to navigate to
    // the Home-branch nested `/home/reminders` route directly. This
    // mirrors what a system-notification deep-link would do.
    unawaited(
      GoRouter.of(tester.element(find.byType(NavigationBar)))
          .push('/home/reminders'),
    );
    await tester.pumpAndSettle();

    // Open the add-reminder form via the FAB (disambiguated from the
    // empty-state PetButton — both share the icon by design).
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.byIcon(PhosphorIconsRegular.bellRinging),
      ),
    );
    await tester.pumpAndSettle();

    // Milo is a dog → the form pre-populates `_when` from the
    // species-default cadence, so we don't need to tap through the
    // date picker. Just commit.
    expect(haptics.lightCount, 0,
        reason: 'no haptic until the user actually commits the schedule');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(haptics.lightCount, 1,
        reason: 'one light haptic fires on a successful schedule commit');
  });
}

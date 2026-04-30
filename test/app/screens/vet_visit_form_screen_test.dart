import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/app/screens/vet_visit_form_screen.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/data/soul_file.dart';
import 'package:petpal/harness/scheduling/notification_template.dart';
import 'package:petpal/harness/scheduling/reminder_kinds.dart';
import 'package:petpal/platform/alarm_scheduler.dart';
import 'package:petpal/platform/work_scheduler.dart';

import '../../_helpers/fake_api_key_storage.dart';
import '../../_helpers/scripted_llm_client.dart';
import '../../_helpers/test_provider_scope.dart';

/// No-op alarm bindings so the platform-trigger arm path doesn't try
/// to reach AndroidAlarmManager (which doesn't exist in `flutter
/// test`). Always reports exact-arm success.
class _NoOpAlarmBindings implements AlarmManagerBindings {
  @override
  Future<bool> oneShotAt({
    required DateTime whenTs,
    required int id,
    required bool exact,
  }) async => true;

  @override
  Future<void> cancel(int id) async {}
}

class _NoOpWorkBindings implements WorkmanagerBindings {
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

/// Phase 6 task 6.10 — vet-visit structured entry creator.
///
/// The form fills a fixed set of fields and writes a structured-
/// frontmatter markdown file to `wiki/<petId>/vet/<date>-<slug>.md`.
/// The tests below exercise:
///   - the form renders all locked fields,
///   - Save composes a valid YAML frontmatter with the expected keys
///     and writes the file via WikiRepo,
///   - the freeform notes textarea content lands in the body,
///   - empty `reason` falls back to "Vet visit".
void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  testWidgets('renders the locked field set: visit date, vet name, reason, '
      'diagnosis, prescriptions, follow-up, notes', (tester) async {
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
        ],
        child: const MaterialApp(home: VetVisitFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Date of visit'), findsOneWidget);
    expect(find.text('Vet name (optional)'), findsOneWidget);
    expect(find.text('Reason for visit'), findsOneWidget);
    expect(find.text('Diagnosis (what the vet said)'), findsOneWidget);
    expect(find.text('Prescriptions (one per line)'), findsOneWidget);
    expect(find.text('Follow-up (optional)'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
  });

  testWidgets('Save writes a vet entry whose frontmatter carries the '
      'locked structured keys (type, date, vet_name, reason, diagnosis, '
      'prescriptions, follow_up_date)', (tester) async {
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
        ],
        child: const MaterialApp(home: VetVisitFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Vet name (optional)'),
      'Dr. Patel',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason for visit'),
      'Annual checkup',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Diagnosis (what the vet said)'),
      'No issues found.',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Prescriptions (one per line)'),
      'Frontline Plus monthly\nApoquel 16mg, twice daily',
    );

    // Notes field is the last TextField; locate by hint text.
    await tester.enterText(
      find.widgetWithText(
        TextField,
        "Anything else worth remembering — owner's notes go here, in your voice.",
      ),
      'He was nervous in the waiting room but settled in the exam.',
    );

    await tester.ensureVisible(find.text('Save vet visit'));
    await tester.tap(find.text('Save vet visit'));
    await tester.pumpAndSettle();

    // Find the written file. Path shape: wiki/1/vet/<YYYY-MM-DD>-annual-checkup.md
    final petWikiKeys = stack.wiki.writes.keys.where(
      (k) => k.startsWith('wiki/${stack.petId}/vet/'),
    );
    expect(petWikiKeys, hasLength(1));
    final path = petWikiKeys.single;
    expect(path, contains('-annual-checkup.md'));

    final body = stack.wiki.writes[path]!;
    final parsed = parseSoul(body);

    expect(parsed.frontmatter['type'], 'vet');
    expect(parsed.frontmatter['date'], isA<String>());
    expect(parsed.frontmatter['vet_name'], 'Dr. Patel');
    expect(parsed.frontmatter['reason'], 'Annual checkup');
    expect(parsed.frontmatter['diagnosis'], 'No issues found.');
    expect(parsed.frontmatter['prescriptions'], [
      'Frontline Plus monthly',
      'Apoquel 16mg, twice daily',
    ]);
    // Follow-up was not set; key must be absent from frontmatter.
    expect(parsed.frontmatter.containsKey('follow_up_date'), isFalse);

    // Body carries the heading + freeform notes.
    expect(parsed.body, contains('# Annual checkup'));
    expect(parsed.body, contains('He was nervous'));
  });

  testWidgets('empty reason falls back to "Vet visit" title (path slug + '
      'body heading)', (tester) async {
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
        ],
        child: const MaterialApp(home: VetVisitFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // No reason entered — Save anyway.
    await tester.ensureVisible(find.text('Save vet visit'));
    await tester.tap(find.text('Save vet visit'));
    await tester.pumpAndSettle();

    final paths = stack.wiki.writes.keys.where(
      (k) => k.startsWith('wiki/${stack.petId}/vet/'),
    );
    expect(paths, hasLength(1));
    expect(paths.single, endsWith('-vet-visit.md'),
        reason: 'empty-reason fallback uses "Vet visit" → vet-visit slug');

    final body = stack.wiki.writes[paths.single]!;
    final parsed = parseSoul(body);
    expect(parsed.frontmatter['type'], 'vet');
    expect(parsed.frontmatter.containsKey('reason'), isFalse,
        reason: 'empty reason is omitted from frontmatter');
    expect(parsed.body, contains('# Vet visit'));
  });

  // Phase 6 task 6.11 — when the user picks a follow-up date in the
  // form, the save handler auto-creates a notification-mode reminder
  // via ReminderService. The form's date picker is hard to drive
  // from a widget test without dragging a calendar; the simpler
  // proof is that the reminder repo gains a row of kind=vet_followup
  // when the form's `_followUpDate` is set programmatically. We
  // exercise the screen state directly via a friend-test pattern —
  // pump the screen, locate the State, set _followUpDate, then tap
  // Save.
  testWidgets('Phase 6 task 6.11 — follow_up_date set → notification '
      'reminder of kind=vet_followup is auto-created', (tester) async {
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          // Override the asset-backed templates with an in-memory
          // map so the test doesn't need an asset bundle. Notifies
          // surface the locked Phase 6.11 body shape.
          notificationTemplatesProvider.overrideWithValue(
            InMemoryNotificationTemplates({
              ReminderKind.vetFollowUp: const NotificationTemplate(
                title: 'Vet follow-up',
                body:
                    "Time for {pet_name}'s vet follow-up — book an appointment.",
              ),
            }),
          ),
          // Stub the platform schedulers so arm() doesn't try to
          // reach Android/Workmanager plugins in the test binding.
          alarmSchedulerProvider.overrideWithValue(
            AlarmScheduler(bindings: _NoOpAlarmBindings()),
          ),
          workSchedulerProvider.overrideWithValue(
            WorkScheduler(bindings: _NoOpWorkBindings()),
          ),
          ...stack.overrides,
        ],
        child: const MaterialApp(home: VetVisitFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Reach into the State to set the follow-up date programmatically
    // — the date picker is awkward to drive from a widget test. The
    // public setFollowUpDateForTesting hook is the supported seam.
    final state = tester.state<State<VetVisitFormScreen>>(
      find.byType(VetVisitFormScreen),
    );
    // ignore: avoid_dynamic_calls
    (state as dynamic).setFollowUpDateForTesting(DateTime(2026, 12, 15));
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, 'Reason for visit'),
      'Annual checkup',
    );
    await tester.ensureVisible(find.text('Save vet visit'));
    await tester.tap(find.text('Save vet visit'));
    await tester.pumpAndSettle();

    // Inspect the in-memory reminders table directly.
    final rows = await stack.db.select(stack.db.reminders).get();
    expect(rows, hasLength(1),
        reason: 'follow_up_date present → exactly one reminder row');
    expect(rows.single.kind, ReminderKind.vetFollowUp.id);
    expect(rows.single.mode, 'notification');
    // Fire time bumps to 9 AM local on the picked date.
    expect(rows.single.whenTs.year, 2026);
    expect(rows.single.whenTs.month, 12);
    expect(rows.single.whenTs.day, 15);
    expect(rows.single.whenTs.hour, 9);
  });

  testWidgets('Phase 6 task 6.11 — follow_up_date NOT set → no reminder '
      'is created', (tester) async {
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
        ],
        child: const MaterialApp(home: VetVisitFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Reason for visit'),
      'Quick checkup',
    );
    await tester.ensureVisible(find.text('Save vet visit'));
    await tester.tap(find.text('Save vet visit'));
    await tester.pumpAndSettle();

    final rows = await stack.db.select(stack.db.reminders).get();
    expect(rows, isEmpty,
        reason: 'no follow_up_date → save handler skips the reminder path');
  });
}

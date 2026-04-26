import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/repos/reminder_repo.dart';
import 'package:petpal/harness/agent/messages.dart';
import 'package:petpal/harness/agent/tool_dispatcher.dart';
import 'package:petpal/harness/guardrails/red_flag_screener.dart';
import 'package:petpal/harness/scheduling/notification_template.dart';
import 'package:petpal/harness/scheduling/reminder_kinds.dart';
import 'package:petpal/harness/scheduling/reminder_scheduler.dart';
import 'package:petpal/harness/scheduling/reminder_service.dart';
import 'package:petpal/harness/scheduling/schedule_mode.dart';
import 'package:petpal/harness/tools/scheduling_tools.dart';
import 'package:petpal/platform/alarm_scheduler.dart';
import 'package:petpal/platform/work_scheduler.dart';

class _NoopAlarmBindings implements AlarmManagerBindings {
  @override
  Future<bool> oneShotAt({
    required DateTime whenTs,
    required int id,
    required bool exact,
  }) async =>
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

void main() {
  late AppDatabase db;
  late ReminderRepo repo;
  late ReminderService service;
  late RedFlagScreener screener;
  late ToolDispatcher dispatcher;
  late int petId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ReminderRepo(db: db);
    petId = await db.into(db.pets).insert(
          PetsCompanion.insert(name: 'Loki', createdAt: DateTime(2026, 4, 26)),
        );

    final templates = InMemoryNotificationTemplates({
      ReminderKind.fleaTreatment: const NotificationTemplate(
        title: 'Flea treatment due',
        body: "Time for {pet_name}'s flea treatment.",
      ),
      ReminderKind.heartwormDose: const NotificationTemplate(
        title: 'Heartworm dose due',
        body: "Time for {pet_name}'s heartworm dose.",
      ),
    });
    service = ReminderService(
      repo: repo,
      scheduler: ReminderScheduler(
        alarms: AlarmScheduler(bindings: _NoopAlarmBindings()),
        work: WorkScheduler(bindings: _NoopWorkBindings()),
      ),
      templates: templates,
      petNameLookup: (id) async => 'Loki',
    );
    screener = RedFlagScreener();

    dispatcher = ToolDispatcher();
    registerSchedulingTools(
      dispatcher,
      reminders: service,
      screener: screener,
      activePetId: () => petId,
    );
  });

  tearDown(() async => db.close());

  Future<Map<String, Object?>> call(String name,
      Map<String, Object?> input) async {
    final block = await dispatcher.handle(
      ToolUseBlock(id: 't1', name: name, input: input),
    );
    return jsonDecode(block.content) as Map<String, Object?>;
  }

  group('schedule_reminder', () {
    test('creates a reminder, defaults mode=notification, returns the id + arm '
        'result', () async {
      final result = await call('schedule_reminder', {
        'kind': 'flea_treatment',
        'when_iso': '2026-05-26T09:00:00',
      });
      expect(result['mode'], 'notification');
      expect(result['arm_result'], 'exact');
      expect(result['reminder_id'], isA<int>());

      final row = await repo.getById(result['reminder_id']! as int);
      expect(row!.kind, 'flea_treatment');
      expect(row.mode, ScheduleMode.notification);
      // Notification mode renders the template into payload.
      expect(row.payload['title'], 'Flea treatment due');
      expect(row.payload['body'], "Time for Loki's flea treatment.");
    });

    test('rejects unknown mode with ArgumentError (DECISIONS row 28)',
        () async {
      final block = await dispatcher.handle(
        const ToolUseBlock(id: 't', name: 'schedule_reminder', input: {
          'kind': 'flea_treatment',
          'when_iso': '2026-05-26T09:00:00',
          'mode': 'deterministic',
        }),
      );
      expect(block.isError, isTrue);
      expect(block.content.toLowerCase(), contains('unknown schedulemode'));
    });

    test('script mode does NOT render a template — payload stays empty',
        () async {
      final result = await call('schedule_reminder', {
        'kind': 'embedding_refresh',
        'when_iso': '2026-05-26T09:00:00',
        'mode': 'script',
      });
      final row = await repo.getById(result['reminder_id']! as int);
      expect(row!.mode, ScheduleMode.script);
      expect(row.payload, isEmpty);
      expect(result.containsKey('arm_result'), isFalse,
          reason: 'arm_result is notification-only');
    });

    test(
        'unknown kind in notification mode falls through to a generic but '
        'pet-aware body', () async {
      final result = await call('schedule_reminder', {
        'kind': 'custom_thing',
        'when_iso': '2026-05-26T09:00:00',
      });
      final row = await repo.getById(result['reminder_id']! as int);
      expect(row!.payload['title'], 'Reminder');
      expect(row.payload['body'], 'Reminder for Loki');
    });
  });

  group('list_reminders', () {
    test('returns all reminders for the active pet, sorted ascending',
        () async {
      await call('schedule_reminder', {
        'kind': 'flea_treatment',
        'when_iso': '2026-06-26T09:00:00',
      });
      await call('schedule_reminder', {
        'kind': 'heartworm_dose',
        'when_iso': '2026-05-26T09:00:00',
      });
      final result = await dispatcher.handle(
        const ToolUseBlock(id: 't', name: 'list_reminders', input: {}),
      );
      final list = jsonDecode(result.content) as List<dynamic>;
      expect(list, hasLength(2));
      // Sorted ascending — heartworm (May) before flea (June).
      expect(list[0]['kind'], 'heartworm_dose');
      expect(list[1]['kind'], 'flea_treatment');
    });
  });

  group('red_flag_check', () {
    test('returns flagged=true with the matched category for an urgent phrase',
        () async {
      final result = await call('red_flag_check', {
        'symptoms': ['Loki has blood in his stool'],
      });
      expect(result['flagged'], isTrue);
      expect(result['category'], 'blood_in_stool');
      expect(result['summary'], isA<String>());
    });

    test('returns flagged=false for a benign phrase', () async {
      final result = await call('red_flag_check', {
        'symptoms': ['Loki had a great walk today.'],
      });
      expect(result['flagged'], isFalse);
      expect(result.containsKey('category'), isFalse);
    });

    test('joins multiple phrases for multi-symptom AND patterns', () async {
      final result = await call('red_flag_check', {
        'symptoms': ['Loki seems lethargic', 'and he refuses to eat'],
      });
      expect(result['flagged'], isTrue);
      expect(result['category'], 'lethargy_anorexia');
    });

    test('rejects non-array symptoms input with ArgumentError', () async {
      final block = await dispatcher.handle(
        const ToolUseBlock(id: 't', name: 'red_flag_check', input: {
          'symptoms': 'just one string',
        }),
      );
      expect(block.isError, isTrue);
    });
  });
}

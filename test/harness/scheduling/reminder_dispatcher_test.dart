import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/repos/reminder_repo.dart';
import 'package:petpal/harness/scheduling/reminder_dispatcher.dart';
import 'package:petpal/harness/scheduling/reminder_engines.dart';
import 'package:petpal/harness/scheduling/schedule_mode.dart';

class _FakeNotifications implements NotificationsEngine {
  final List<({int reminderId, String title, String body})> shown = [];
  @override
  Future<void> show({
    required int reminderId,
    required String title,
    required String body,
  }) async {
    shown.add((reminderId: reminderId, title: title, body: body));
  }
}

class _FakeScriptEngine implements ScriptEngine {
  final List<({String taskId, Map<String, Object?> args})> runs = [];
  @override
  Future<void> run({
    required String taskId,
    required Map<String, Object?> args,
  }) async {
    runs.add((taskId: taskId, args: args));
  }
}

class _FakeSynthesisEngine implements SynthesisEngine {
  final List<({int petId, Map<String, Object?> args})> runs = [];
  @override
  Future<void> run({
    required int petId,
    required Map<String, Object?> args,
  }) async {
    runs.add((petId: petId, args: args));
  }
}

void main() {
  late AppDatabase db;
  late ReminderRepo repo;
  late _FakeNotifications notifications;
  late _FakeScriptEngine scripts;
  late _FakeSynthesisEngine synthesis;
  late ReminderDispatcher dispatcher;
  late int petId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ReminderRepo(db: db);
    notifications = _FakeNotifications();
    scripts = _FakeScriptEngine();
    synthesis = _FakeSynthesisEngine();
    dispatcher = ReminderDispatcher(
      repo: repo,
      notifications: notifications,
      scripts: scripts,
      synthesis: synthesis,
    );
    petId = await db.into(db.pets).insert(
          PetsCompanion.insert(name: 'Loki', createdAt: DateTime(2026, 4, 26)),
        );
  });

  tearDown(() async => db.close());

  test('mode=notification fires the notifications engine with payload title/body',
      () async {
    final id = await repo.create(
      petId: petId,
      kind: 'flea_treatment',
      whenTs: DateTime(2026, 5, 26),
      mode: ScheduleMode.notification,
      payload: {
        'title': 'Reminder',
        'body': 'Flea treatment due tomorrow for Loki',
      },
    );
    await dispatcher.fire(id);
    expect(notifications.shown, hasLength(1));
    final call = notifications.shown.single;
    expect(call.reminderId, id);
    expect(call.title, 'Reminder');
    expect(call.body, 'Flea treatment due tomorrow for Loki');
    expect(scripts.runs, isEmpty);
    expect(synthesis.runs, isEmpty);
  });

  test('mode=notification falls back to "Reminder" / empty body when payload empty',
      () async {
    final id = await repo.create(
      petId: petId,
      kind: 'unknown',
      whenTs: DateTime(2026, 5, 26),
      mode: ScheduleMode.notification,
    );
    await dispatcher.fire(id);
    expect(notifications.shown.single.title, 'Reminder');
    expect(notifications.shown.single.body, '');
  });

  test('mode=script routes to the script engine with taskId + args', () async {
    final id = await repo.create(
      petId: petId,
      kind: 'unused',
      whenTs: DateTime(2026, 5, 26),
      mode: ScheduleMode.script,
      payload: {
        'taskId': 'weight_chart_rollup',
        'args': {'pet_id': petId, 'window_days': 30},
      },
    );
    await dispatcher.fire(id);
    expect(scripts.runs, hasLength(1));
    expect(scripts.runs.single.taskId, 'weight_chart_rollup');
    expect(scripts.runs.single.args, {'pet_id': petId, 'window_days': 30});
    expect(notifications.shown, isEmpty);
  });

  test('mode=script taskId falls back to row.kind when payload omits it', () async {
    final id = await repo.create(
      petId: petId,
      kind: 'embedding_refresh',
      whenTs: DateTime(2026, 5, 26),
      mode: ScheduleMode.script,
    );
    await dispatcher.fire(id);
    expect(scripts.runs.single.taskId, 'embedding_refresh');
    expect(scripts.runs.single.args, isEmpty);
  });

  test('mode=synthesis routes to the synthesis engine with petId + args',
      () async {
    final id = await repo.create(
      petId: petId,
      kind: 'weekly_summary',
      whenTs: DateTime(2026, 5, 3),
      mode: ScheduleMode.synthesis,
      payload: {
        'args': {'window': '7d'},
      },
    );
    await dispatcher.fire(id);
    expect(synthesis.runs, hasLength(1));
    expect(synthesis.runs.single.petId, petId);
    expect(synthesis.runs.single.args, {'window': '7d'});
  });

  test(
      'mode=synthesisNotify is the Phase 5 stub branch — throws '
      'UnimplementedError so the dispatcher switch is exhaustive '
      '(DECISIONS row 28)', () async {
    final id = await repo.create(
      petId: petId,
      kind: 'weekly_summary_notify',
      whenTs: DateTime(2026, 5, 3),
      mode: ScheduleMode.synthesisNotify,
    );
    expect(
      () => dispatcher.fire(id),
      throwsA(
        isA<UnimplementedError>().having(
          (e) => e.message,
          'message',
          contains('Phase 5'),
        ),
      ),
    );
  });

  test('fire() is a no-op when the row was deleted between scheduling and fire',
      () async {
    final id = await repo.create(
      petId: petId,
      kind: 'flea_treatment',
      whenTs: DateTime(2026, 5, 26),
      mode: ScheduleMode.notification,
    );
    await repo.delete(id);
    await dispatcher.fire(id); // must not throw
    expect(notifications.shown, isEmpty);
    expect(scripts.runs, isEmpty);
    expect(synthesis.runs, isEmpty);
  });
}

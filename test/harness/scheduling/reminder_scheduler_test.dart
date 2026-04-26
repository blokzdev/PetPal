import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/repos/reminder_repo.dart';
import 'package:petpal/harness/scheduling/reminder_scheduler.dart';
import 'package:petpal/harness/scheduling/schedule_mode.dart';
import 'package:petpal/platform/alarm_scheduler.dart';
import 'package:petpal/platform/work_scheduler.dart';

class _FakeAlarmBindings implements AlarmManagerBindings {
  bool exactAllowed = true;
  final List<({int id, DateTime whenTs, bool exact})> arms = [];
  final List<int> cancels = [];

  @override
  Future<bool> oneShotAt({
    required DateTime whenTs,
    required int id,
    required bool exact,
  }) async {
    arms.add((id: id, whenTs: whenTs, exact: exact));
    if (exact && !exactAllowed) return false;
    return true;
  }

  @override
  Future<void> cancel(int id) async => cancels.add(id);
}

class _FakeWorkBindings implements WorkmanagerBindings {
  bool initialised = false;
  final List<({String uniqueName, String taskName, Duration delay})> arms = [];
  final List<String> cancels = [];

  @override
  Future<void> initialize() async => initialised = true;

  @override
  Future<void> registerOneOff({
    required String uniqueName,
    required String taskName,
    required Duration initialDelay,
    required Map<String, dynamic> inputData,
  }) async {
    arms.add((
      uniqueName: uniqueName,
      taskName: taskName,
      delay: initialDelay,
    ));
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    cancels.add(uniqueName);
  }
}

ReminderRow _row({
  int id = 1,
  int petId = 1,
  required ScheduleMode mode,
  DateTime? whenTs,
}) =>
    ReminderRow(
      id: id,
      petId: petId,
      kind: 'sample',
      whenTs: whenTs ?? DateTime(2026, 5, 26, 9),
      mode: mode,
      payload: const {},
    );

void main() {
  late _FakeAlarmBindings alarmBindings;
  late _FakeWorkBindings workBindings;
  late ReminderScheduler scheduler;

  setUp(() {
    alarmBindings = _FakeAlarmBindings();
    workBindings = _FakeWorkBindings();
    scheduler = ReminderScheduler(
      alarms: AlarmScheduler(bindings: alarmBindings),
      work: WorkScheduler(bindings: workBindings),
    );
  });

  test('mode=notification routes to AlarmScheduler with exact=true', () async {
    final result = await scheduler.arm(_row(mode: ScheduleMode.notification));
    expect(result, AlarmArmResult.exact);
    expect(alarmBindings.arms, hasLength(1));
    expect(alarmBindings.arms.single.exact, isTrue);
    expect(workBindings.arms, isEmpty);
  });

  test(
      'mode=notification falls back to inexact when SCHEDULE_EXACT_ALARM '
      'denied — DECISIONS row 31', () async {
    alarmBindings.exactAllowed = false;
    final result = await scheduler.arm(_row(mode: ScheduleMode.notification));
    expect(result, AlarmArmResult.inexactFallback);
    // Two attempts: exact first (fails), then inexact (succeeds).
    expect(alarmBindings.arms, hasLength(2));
    expect(alarmBindings.arms.first.exact, isTrue);
    expect(alarmBindings.arms.last.exact, isFalse);
  });

  test('mode=script routes to WorkScheduler', () async {
    final result = await scheduler.arm(_row(mode: ScheduleMode.script));
    expect(result, isNull);
    expect(workBindings.arms, hasLength(1));
    expect(workBindings.arms.single.uniqueName, 'petpal.reminder.1');
    expect(workBindings.arms.single.taskName, 'fire_reminder');
    expect(alarmBindings.arms, isEmpty);
  });

  test('mode=synthesis routes to WorkScheduler', () async {
    final result = await scheduler.arm(_row(mode: ScheduleMode.synthesis));
    expect(result, isNull);
    expect(workBindings.arms, hasLength(1));
  });

  test('mode=synthesisNotify routes to WorkScheduler', () async {
    final result =
        await scheduler.arm(_row(mode: ScheduleMode.synthesisNotify));
    expect(result, isNull);
    expect(workBindings.arms, hasLength(1));
  });

  test('cancel routes by mode just like arm', () async {
    await scheduler.cancel(_row(id: 7, mode: ScheduleMode.notification));
    expect(alarmBindings.cancels, [7]);
    expect(workBindings.cancels, isEmpty);

    await scheduler.cancel(_row(id: 8, mode: ScheduleMode.script));
    expect(workBindings.cancels, ['petpal.reminder.8']);
  });

  test(
      'WorkScheduler clamps a past whenTs to zero delay rather than rejecting',
      () async {
    await scheduler.arm(_row(
      mode: ScheduleMode.script,
      whenTs: DateTime(2020, 6, 15),
    ));
    expect(workBindings.arms.single.delay, Duration.zero);
  });
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/app/entitlement/quota_exception.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/repos/reminder_repo.dart';
import 'package:petpal/harness/scheduling/notification_template.dart';
import 'package:petpal/harness/scheduling/reminder_kinds.dart';
import 'package:petpal/harness/scheduling/reminder_scheduler.dart';
import 'package:petpal/harness/scheduling/reminder_service.dart';
import 'package:petpal/platform/alarm_scheduler.dart';
import 'package:petpal/platform/work_scheduler.dart';

/// Phase 7 task D.1 — reminder quota gate.
///
/// 5-reminder cap on free tier (DECISIONS row 36). Pro + BYOK have
/// `reminderCap == null` and skip the gate. The gate fires before
/// `_repo.create`, so a quota-rejected create leaves no DB row.
void main() {
  late AppDatabase db;
  late int petId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    petId = await db.into(db.pets).insert(PetsCompanion.insert(
          name: 'Loki',
          createdAt: DateTime(2026, 5),
        ));
  });

  tearDown(() => db.close());

  ReminderService build(Entitlement Function() entitlementSource) {
    return ReminderService(
      repo: ReminderRepo(db: db),
      scheduler: ReminderScheduler(
        alarms: AlarmScheduler(bindings: _NoopAlarmBindings()),
        work: WorkScheduler(bindings: _NoopWorkBindings()),
      ),
      templates: InMemoryNotificationTemplates(_stubTemplates),
      petNameLookup: (id) async => 'Loki',
      entitlementSource: entitlementSource,
    );
  }

  test('Free tier — first 5 reminders create successfully; 6th throws '
      'ReminderQuotaExceeded; DB count stays at 5', () async {
    final svc = build(Entitlement.freeAnonymous);

    for (var i = 0; i < 5; i++) {
      await svc.create(
        petId: petId,
        kind: 'flea',
        when: DateTime(2026, 6, i + 1),
      );
    }

    expect(
      () => svc.create(
        petId: petId,
        kind: 'flea',
        when: DateTime(2026, 6, 10),
      ),
      throwsA(isA<ReminderQuotaExceeded>()),
    );

    final all = await ReminderRepo(db: db).listForPet(petId);
    expect(all, hasLength(5),
        reason: 'gate must fire BEFORE the insert; failed creates '
            'must NOT leave dangling rows');
  });

  test('Pro — no cap (creates past 5 succeed)', () async {
    final svc = build(() => Entitlement(
          state: EntitlementState.proMonthly,
          userId: 'user-pro',
          counterPeriodStart: DateTime(2026, 5),
        ));

    for (var i = 0; i < 7; i++) {
      await svc.create(
        petId: petId,
        kind: 'flea',
        when: DateTime(2026, 6, i + 1),
      );
    }

    final all = await ReminderRepo(db: db).listForPet(petId);
    expect(all, hasLength(7));
  });

  test('BYOK — keeps the 5-reminder cap (BYOK lifts cost-driven caps '
      'only; reminders are server-cost-trivial UX, not a cost gate)',
      () async {
    final svc = build(() => Entitlement(
          state: EntitlementState.byok,
          userId: 'user-byok',
          counterPeriodStart: DateTime(2026, 5),
        ));

    for (var i = 0; i < 5; i++) {
      await svc.create(
        petId: petId,
        kind: 'flea',
        when: DateTime(2026, 6, i + 1),
      );
    }

    expect(
      () => svc.create(
        petId: petId,
        kind: 'flea',
        when: DateTime(2026, 6, 10),
      ),
      throwsA(isA<ReminderQuotaExceeded>()),
    );
  });

  test('null entitlementSource → gate is bypassed (legacy callers + '
      'tests that don\'t care about quota stay working)', () async {
    final svc = ReminderService(
      repo: ReminderRepo(db: db),
      scheduler: ReminderScheduler(
        alarms: AlarmScheduler(bindings: _NoopAlarmBindings()),
        work: WorkScheduler(bindings: _NoopWorkBindings()),
      ),
      templates: InMemoryNotificationTemplates(_stubTemplates),
      petNameLookup: (id) async => 'Loki',
      // entitlementSource omitted
    );

    for (var i = 0; i < 10; i++) {
      await svc.create(
        petId: petId,
        kind: 'flea',
        when: DateTime(2026, 6, i + 1),
      );
    }

    final all = await ReminderRepo(db: db).listForPet(petId);
    expect(all, hasLength(10));
  });
}

final Map<ReminderKind, NotificationTemplate> _stubTemplates = {
  for (final k in ReminderKind.values)
    k: const NotificationTemplate(
      title: 'Reminder',
      body: 'Reminder for {pet_name}',
    ),
};

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

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/repos/entitlement_repo.dart';

/// Phase 7 task B.1 — entitlement cache I/O round-trip.
///
/// Pins the Drift schema bump v1→v2 + the EntitlementRepo's
/// upsert/read/clear contract. Mirrors how the reconciliation pass
/// (later task) will persist server state for the agent loop's
/// quota gate to read offline.
void main() {
  late AppDatabase db;
  late EntitlementRepo repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = EntitlementRepo(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('schema bump v1→v2 creates the entitlements table', () async {
    // The migration runs onCreate (since this is a fresh in-memory DB
    // at the current schemaVersion). A successful select confirms the
    // table exists with the expected columns.
    final result = await db.select(db.entitlements).get();
    expect(result, isEmpty);
    expect(db.schemaVersion, 2);
  });

  test('read returns null when no row exists for the user', () async {
    final result = await repo.read('nonexistent-user-id');
    expect(result, isNull);
  });

  test('upsert inserts a Pro entitlement; read round-trips fields', () async {
    final ent = Entitlement(
      state: EntitlementState.proMonthly,
      userId: 'user-abc',
      renewalDate: DateTime(2026, 6),
      photoCreditsBalance: 50,
      monthlyTextCount: 127,
      monthlyVisionCount: 12,
      counterPeriodStart: DateTime(2026, 5),
      fetchedAt: DateTime(2026, 5, 15, 10, 30),
    );

    await repo.upsert(ent);
    final readBack = await repo.read('user-abc');

    expect(readBack, isNotNull);
    expect(readBack!.state, EntitlementState.proMonthly);
    expect(readBack.userId, 'user-abc');
    expect(readBack.renewalDate, DateTime(2026, 6));
    expect(readBack.photoCreditsBalance, 50);
    expect(readBack.monthlyTextCount, 127);
    expect(readBack.monthlyVisionCount, 12);
    expect(readBack.counterPeriodStart, DateTime(2026, 5));
    expect(readBack.fetchedAt, DateTime(2026, 5, 15, 10, 30));
  });

  test('upsert overwrites an existing row (insertOnConflictUpdate)', () async {
    await repo.upsert(Entitlement(
      state: EntitlementState.free,
      userId: 'user-x',
      monthlyTextCount: 50,
      counterPeriodStart: DateTime(2026, 5),
    ));

    // Simulate a Pro upgrade — same userId, different state.
    await repo.upsert(Entitlement(
      state: EntitlementState.proAnnual,
      userId: 'user-x',
      renewalDate: DateTime(2027, 5, 15),
      monthlyTextCount: 50, // counter carries over
      counterPeriodStart: DateTime(2026, 5),
    ));

    final final_ = await repo.read('user-x');
    expect(final_!.state, EntitlementState.proAnnual);
    expect(final_.renewalDate, DateTime(2027, 5, 15));
  });

  test('upsert is a no-op for freeAnonymous (anonymous users have no row)',
      () async {
    await repo.upsert(Entitlement.freeAnonymous());
    final all = await db.select(db.entitlements).get();
    expect(all, isEmpty,
        reason: 'freeAnonymous has null userId; cannot persist');
  });

  test('upsert is a no-op when userId is null (defensive)', () async {
    await repo.upsert(Entitlement(
      state: EntitlementState.free, // signed-in shape but no userId
      counterPeriodStart: DateTime(2026, 5),
    ));
    final all = await db.select(db.entitlements).get();
    expect(all, isEmpty);
  });

  test('clear deletes the row for the given userId', () async {
    await repo.upsert(Entitlement(
      state: EntitlementState.proMonthly,
      userId: 'user-to-delete',
      counterPeriodStart: DateTime(2026, 5),
    ));
    expect(await repo.read('user-to-delete'), isNotNull);

    await repo.clear('user-to-delete');
    expect(await repo.read('user-to-delete'), isNull);
  });

  test('clear is a no-op for unknown userId (no exception)', () async {
    await repo.clear('never-existed');
    // Reaching this line means clear didn't throw.
    expect(true, isTrue);
  });

  test('multiple users can coexist (cache supports multi-user device)',
      () async {
    await repo.upsert(Entitlement(
      state: EntitlementState.proMonthly,
      userId: 'user-1',
      counterPeriodStart: DateTime(2026, 5),
    ));
    await repo.upsert(Entitlement(
      state: EntitlementState.byok,
      userId: 'user-2',
      counterPeriodStart: DateTime(2026, 5),
    ));

    final u1 = await repo.read('user-1');
    final u2 = await repo.read('user-2');
    expect(u1!.state, EntitlementState.proMonthly);
    expect(u2!.state, EntitlementState.byok);
  });

  test('round-trip via wire encoding (state survives fromWire/wireValue)',
      () async {
    for (final state in [
      EntitlementState.free,
      EntitlementState.proMonthly,
      EntitlementState.proAnnual,
      EntitlementState.byok,
    ]) {
      await repo.upsert(Entitlement(
        state: state,
        userId: 'user-${state.name}',
        counterPeriodStart: DateTime(2026, 5),
      ));
      final result = await repo.read('user-${state.name}');
      expect(result!.state, state, reason: '$state did not round-trip');
    }
  });
}

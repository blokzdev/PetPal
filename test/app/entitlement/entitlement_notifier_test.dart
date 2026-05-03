import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/database.dart';

/// Phase 7 task B.1 — entitlementProvider behaviour.
///
/// Confirms the provider's B.1 contract: returns
/// [Entitlement.freeAnonymous] by default; setOptimistic emits a
/// new state and persists to the cache; refresh is a no-op stub
/// (real Supabase reconciliation lands later).
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async {
          ref.onDispose(() async {});
          return db;
        }),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('default state is Entitlement.freeAnonymous (no auth wired in B.1)',
      () async {
    final ent = await container.read(entitlementProvider.future);
    expect(ent.state, EntitlementState.freeAnonymous);
    expect(ent.userId, isNull);
  });

  test('refresh is a no-op stub in B.1 (preserves current state)', () async {
    await container.read(entitlementProvider.future);
    final notifier = container.read(entitlementProvider.notifier);
    final before = container.read(entitlementProvider).value!;

    await notifier.refresh();

    final after = container.read(entitlementProvider).value!;
    expect(after, equals(before));
  });

  test('setOptimistic emits the new entitlement and persists to cache',
      () async {
    await container.read(entitlementProvider.future);
    final notifier = container.read(entitlementProvider.notifier);

    final pro = Entitlement(
      state: EntitlementState.proMonthly,
      userId: 'user-pro',
      renewalDate: DateTime(2026, 6),
      photoCreditsBalance: 50,
      counterPeriodStart: DateTime(2026, 5),
    );
    await notifier.setOptimistic(pro);

    expect(container.read(entitlementProvider).value, equals(pro));

    // Cache row was upserted. A subsequent app launch (simulated by
    // re-reading via repo) sees the persisted state.
    final repo = await container.read(entitlementRepoProvider.future);
    final cached = await repo.read('user-pro');
    expect(cached, isNotNull);
    expect(cached!.state, EntitlementState.proMonthly);
  });

  test('setOptimistic for freeAnonymous does NOT persist '
      '(no cache row by design)', () async {
    await container.read(entitlementProvider.future);
    final notifier = container.read(entitlementProvider.notifier);

    await notifier.setOptimistic(Entitlement.freeAnonymous());

    final all = await db.select(db.entitlements).get();
    expect(all, isEmpty);
  });
}

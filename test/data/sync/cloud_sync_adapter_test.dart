import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/app/entitlement/quota_exception.dart';
import 'package:petpal/data/sync/cloud_sync_adapter.dart';

void main() {
  test('NoopCloudSyncAdapter starts idle and stays idle through push/pull',
      () async {
    final sync = NoopCloudSyncAdapter();
    expect(sync.status.state, SyncState.idle);
    expect(sync.status.lastSyncAt, isNull);

    final pushed = await sync.push(petId: 1);
    expect(pushed.changedPaths, isEmpty);
    expect(sync.status.state, SyncState.idle);
    expect(sync.status.lastSyncAt, isNotNull);

    final pulled = await sync.pull(petId: 1);
    expect(pulled.changedPaths, isEmpty);
    expect(sync.status.state, SyncState.idle);
  });

  group('Phase 7 task D.1 — EntitlementGatedSyncAdapter', () {
    Entitlement pro() => Entitlement(
          state: EntitlementState.proMonthly,
          userId: 'user-pro',
          counterPeriodStart: DateTime(2026, 5),
        );

    test('Pro → push delegates to inner', () async {
      final inner = NoopCloudSyncAdapter();
      final gated = EntitlementGatedSyncAdapter(
        inner: inner,
        entitlementSource: pro,
      );
      final result = await gated.push(petId: 1);
      expect(result.changedPaths, isEmpty);
    });

    test('Pro → pull delegates to inner', () async {
      final inner = NoopCloudSyncAdapter();
      final gated = EntitlementGatedSyncAdapter(
        inner: inner,
        entitlementSource: pro,
      );
      final result = await gated.pull(petId: 1);
      expect(result.changedPaths, isEmpty);
    });

    test('Free anonymous → push throws SyncQuotaExceeded', () {
      final gated = EntitlementGatedSyncAdapter(
        inner: NoopCloudSyncAdapter(),
        entitlementSource: Entitlement.freeAnonymous,
      );
      expect(
        () => gated.push(petId: 1),
        throwsA(isA<SyncQuotaExceeded>()),
      );
    });

    test('Free signed-in → pull throws SyncQuotaExceeded', () {
      final gated = EntitlementGatedSyncAdapter(
        inner: NoopCloudSyncAdapter(),
        entitlementSource: () => Entitlement(
          state: EntitlementState.free,
          userId: 'user-free',
          counterPeriodStart: DateTime(2026, 5),
        ),
      );
      expect(
        () => gated.pull(petId: 1),
        throwsA(isA<SyncQuotaExceeded>()),
      );
    });

    test('BYOK → throws SyncQuotaExceeded (sync is NOT cost-driven; '
        'BYOK does NOT unlock sync per row 36)', () {
      final gated = EntitlementGatedSyncAdapter(
        inner: NoopCloudSyncAdapter(),
        entitlementSource: () => Entitlement(
          state: EntitlementState.byok,
          userId: 'user-byok',
          counterPeriodStart: DateTime(2026, 5),
        ),
      );
      expect(
        () => gated.push(petId: 1),
        throwsA(isA<SyncQuotaExceeded>()),
      );
    });

    test('status getter passes through without triggering the gate '
        '(UI reads status to render "sync requires Pro" without '
        'throwing)', () {
      final gated = EntitlementGatedSyncAdapter(
        inner: NoopCloudSyncAdapter(),
        entitlementSource: Entitlement.freeAnonymous,
      );
      expect(gated.status.state, SyncState.idle);
    });
  });
}

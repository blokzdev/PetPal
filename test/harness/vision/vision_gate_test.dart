import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/harness/vision/vision_gate.dart';

Entitlement _pro({
  int monthlyVisionCount = 0,
  int photoCreditsBalance = 0,
}) =>
    Entitlement(
      state: EntitlementState.proMonthly,
      userId: 'user-pro',
      counterPeriodStart: DateTime(2026, 5),
      monthlyVisionCount: monthlyVisionCount,
      photoCreditsBalance: photoCreditsBalance,
    );

RealVisionGate _gate(Entitlement ent) =>
    RealVisionGate(entitlementSource: () => ent);

void main() {
  group('Phase 6 task 6.4 — VisionGate stub', () {
    test('StubVisionGate.check() returns allowed', () async {
      const gate = StubVisionGate();
      final decision = await gate.check();
      expect(decision.isAllowed, isTrue);
      expect(decision.reason, isNull);
    });

    test('VisionGateDecision.allowed is the canonical singleton — '
        'multiple lookups return identical const instance', () {
      const a = VisionGateDecision.allowed;
      const b = VisionGateDecision.allowed;
      expect(identical(a, b), isTrue);
      expect(a.isAllowed, isTrue);
      expect(a.reason, isNull);
    });

    test('VisionGateDecision.blocked carries the user-facing reason', () {
      final d = VisionGateDecision.blocked('Photo quota reached.');
      expect(d.isAllowed, isFalse);
      expect(d.reason, 'Photo quota reached.');
    });

    test('VisionGate is implementable — Phase 7 task D.1 plugs in '
        'RealVisionGate via the same surface (no breaking change at '
        'the call sites in 6.5 / 6.6 / 6.9)', () async {
      final fake = _FakeQuotaGate(remaining: 0);
      final blocked = await fake.check();
      expect(blocked.isAllowed, isFalse);
      expect(blocked.reason, contains('quota'));

      final fakeAllowed = _FakeQuotaGate(remaining: 5);
      final allowed = await fakeAllowed.check();
      expect(allowed.isAllowed, isTrue);
    });
  });

  group('Phase 7 task D.1 — RealVisionGate decision matrix', () {
    test('Pro under cap → allowed', () async {
      final r = await _gate(_pro(monthlyVisionCount: 10)).check();
      expect(r.isAllowed, isTrue);
    });

    test('Pro at cap with credits → allowed (credits cover overage)',
        () async {
      final r = await _gate(_pro(
        monthlyVisionCount: 30,
        photoCreditsBalance: 50,
      )).check();
      expect(r.isAllowed, isTrue);
    });

    test('Pro at cap with zero credits → blocked with credit-pack copy',
        () async {
      final r = await _gate(_pro(monthlyVisionCount: 30)).check();
      expect(r.isAllowed, isFalse);
      expect(r.reason, contains('Top up with 50 more for'));
      expect(r.reason, contains('Photo analysis: 30 a month on Pro'),
          reason: 'must use VOICE.md §6 example 13 register');
    });

    test('BYOK → allowed (user pays Anthropic directly)', () async {
      final r = await _gate(Entitlement(
        state: EntitlementState.byok,
        userId: 'user-byok',
        counterPeriodStart: DateTime(2026, 5),
      )).check();
      expect(r.isAllowed, isTrue,
          reason: 'BYOK lifts cost-driven caps; vision goes via the '
              "user's own key");
    });

    test('Free anonymous → blocked with Pro upgrade copy', () async {
      final r = await _gate(Entitlement.freeAnonymous()).check();
      expect(r.isAllowed, isFalse);
      expect(r.reason, contains('Photo analysis is part of Pro'));
      expect(r.reason, contains('7.99/mo'));
    });

    test('Free signed-in → blocked same as anonymous', () async {
      final r = await _gate(Entitlement(
        state: EntitlementState.free,
        userId: 'user-free',
        counterPeriodStart: DateTime(2026, 5),
      )).check();
      expect(r.isAllowed, isFalse);
      expect(r.reason, contains('Photo analysis is part of Pro'));
    });

    test('source is called every check — no caching of stale verdict',
        () async {
      var ent = Entitlement.freeAnonymous();
      final gate = RealVisionGate(entitlementSource: () => ent);

      expect((await gate.check()).isAllowed, isFalse);
      ent = _pro(); // simulate Pro upgrade
      expect((await gate.check()).isAllowed, isTrue,
          reason: 'gate must consult the source on each check');
    });
  });
}

class _FakeQuotaGate implements VisionGate {
  _FakeQuotaGate({required this.remaining});
  final int remaining;

  @override
  Future<VisionGateDecision> check() async {
    if (remaining <= 0) {
      return VisionGateDecision.blocked(
        'Photo quota reached. Upgrade to Pro or buy a credit pack.',
      );
    }
    return VisionGateDecision.allowed;
  }
}


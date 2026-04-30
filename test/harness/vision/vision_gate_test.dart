import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/vision/vision_gate.dart';

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

    test('VisionGate is implementable — Phase 7 task 7.10 plugs in '
        'RealVisionGate via the same surface (no breaking change at '
        'the call sites in 6.5 / 6.6 / 6.9)', () async {
      // Smoke test for the abstract surface — a hand-rolled fake
      // implements the interface and Phase 7 will swap in the real
      // entitlement-backed version.
      final fake = _FakeQuotaGate(remaining: 0);
      final blocked = await fake.check();
      expect(blocked.isAllowed, isFalse);
      expect(blocked.reason, contains('quota'));

      final fakeAllowed = _FakeQuotaGate(remaining: 5);
      final allowed = await fakeAllowed.check();
      expect(allowed.isAllowed, isTrue);
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

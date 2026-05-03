import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/entitlement/entitlement.dart';

/// Phase 7 task B.1 — entitlement value class + state-derived flag tests.
///
/// Pins the canonical mapping from [EntitlementState] to the gates
/// the agent loop / Settings UI / paywall consume. Drift-by-state is
/// the canonical regression risk: a future cleanup that "simplifies"
/// the enum could silently flip the meter for Pro users or open the
/// reminder cap for free users without anyone noticing in production.
void main() {
  group('EntitlementState — flag derivations (DECISIONS row 36)', () {
    test('isPro covers proMonthly + proAnnual; nothing else', () {
      expect(EntitlementState.proMonthly.isPro, isTrue);
      expect(EntitlementState.proAnnual.isPro, isTrue);
      expect(EntitlementState.free.isPro, isFalse);
      expect(EntitlementState.freeAnonymous.isPro, isFalse);
      expect(EntitlementState.byok.isPro, isFalse);
    });

    test('isFree covers freeAnonymous + free; nothing else', () {
      expect(EntitlementState.freeAnonymous.isFree, isTrue);
      expect(EntitlementState.free.isFree, isTrue);
      expect(EntitlementState.proMonthly.isFree, isFalse);
      expect(EntitlementState.proAnnual.isFree, isFalse);
      expect(EntitlementState.byok.isFree, isFalse,
          reason: 'BYOK is a free-tier MODIFIER, not the free tier itself');
    });

    test('isTextMetered = isFree (Pro + BYOK are unmetered for text)', () {
      expect(EntitlementState.freeAnonymous.isTextMetered, isTrue);
      expect(EntitlementState.free.isTextMetered, isTrue);
      expect(EntitlementState.proMonthly.isTextMetered, isFalse);
      expect(EntitlementState.byok.isTextMetered, isFalse);
    });

    test('isVisionMetered = isPro (free has no vision; BYOK is unmetered)',
        () {
      expect(EntitlementState.proMonthly.isVisionMetered, isTrue);
      expect(EntitlementState.proAnnual.isVisionMetered, isTrue);
      expect(EntitlementState.free.isVisionMetered, isFalse);
      expect(EntitlementState.freeAnonymous.isVisionMetered, isFalse);
      expect(EntitlementState.byok.isVisionMetered, isFalse);
    });

    test('usesProxy is true everywhere except byok '
        '(BYOK routes via DirectTransport)', () {
      expect(EntitlementState.freeAnonymous.usesProxy, isTrue);
      expect(EntitlementState.free.usesProxy, isTrue);
      expect(EntitlementState.proMonthly.usesProxy, isTrue);
      expect(EntitlementState.proAnnual.usesProxy, isTrue);
      expect(EntitlementState.byok.usesProxy, isFalse);
    });

    test('textCap = 200 for free*; null for Pro + BYOK', () {
      expect(EntitlementState.freeAnonymous.textCap, 200);
      expect(EntitlementState.free.textCap, 200);
      expect(EntitlementState.proMonthly.textCap, isNull);
      expect(EntitlementState.byok.textCap, isNull);
    });

    test('visionCap = 30 for Pro; null elsewhere', () {
      expect(EntitlementState.proMonthly.visionCap, 30);
      expect(EntitlementState.proAnnual.visionCap, 30);
      expect(EntitlementState.free.visionCap, isNull);
      expect(EntitlementState.freeAnonymous.visionCap, isNull);
      expect(EntitlementState.byok.visionCap, isNull);
    });

    test('reminderCap = 5 for free; null for Pro + BYOK', () {
      expect(EntitlementState.freeAnonymous.reminderCap, 5);
      expect(EntitlementState.free.reminderCap, 5);
      expect(EntitlementState.proMonthly.reminderCap, isNull);
      expect(EntitlementState.byok.reminderCap, isNull,
          reason: 'BYOK gets unlimited reminders per row 36 — they are '
              'trivially cheap server-side');
    });

    test('petCap = 1 for free + BYOK; null for Pro', () {
      expect(EntitlementState.freeAnonymous.petCap, 1);
      expect(EntitlementState.free.petCap, 1);
      expect(EntitlementState.byok.petCap, 1,
          reason: 'BYOK keeps the 1-pet cap; multi-pet is a pure UX gate, '
              'not a cost-driven cap');
      expect(EntitlementState.proMonthly.petCap, isNull);
    });
  });

  group('EntitlementState — wire format round-trip', () {
    test('fromWire maps known values correctly', () {
      expect(EntitlementState.fromWire('free'), EntitlementState.free);
      expect(EntitlementState.fromWire('pro_monthly'),
          EntitlementState.proMonthly);
      expect(EntitlementState.fromWire('pro_annual'),
          EntitlementState.proAnnual);
      expect(EntitlementState.fromWire('byok'), EntitlementState.byok);
    });

    test('fromWire defaults unknown values to free (never silent upgrade)',
        () {
      expect(
          EntitlementState.fromWire('pro_lifetime_legendary'),
          EntitlementState.free,
          reason: 'Unknown server states must NOT silently grant Pro '
              'access — the reconciliation pass should warn instead');
    });

    test('wireValue mirrors fromWire (round-trip)', () {
      for (final state in [
        EntitlementState.free,
        EntitlementState.proMonthly,
        EntitlementState.proAnnual,
        EntitlementState.byok,
      ]) {
        expect(
          EntitlementState.fromWire(state.wireValue),
          state,
          reason: 'round-trip failed for $state',
        );
      }
    });

    test('freeAnonymous wireValue is "free" (server-side they look free)',
        () {
      // Anonymous users have no Supabase row; if we ever serialize a
      // freeAnonymous Entitlement for upload it should look like free.
      expect(EntitlementState.freeAnonymous.wireValue, 'free');
    });
  });

  group('Entitlement.freeAnonymous default', () {
    test('state is freeAnonymous; no userId; no fetchedAt', () {
      final e = Entitlement.freeAnonymous(now: DateTime(2026, 5, 15));
      expect(e.state, EntitlementState.freeAnonymous);
      expect(e.userId, isNull);
      expect(e.fetchedAt, isNull);
    });

    test('counterPeriodStart anchors to first of current month', () {
      final e = Entitlement.freeAnonymous(now: DateTime(2026, 5, 15, 12, 30));
      expect(e.counterPeriodStart, DateTime(2026, 5));
    });

    test('all flag derivations consistent with freeAnonymous state', () {
      final e = Entitlement.freeAnonymous();
      expect(e.isPro, isFalse);
      expect(e.isFree, isTrue);
      expect(e.usesProxy, isTrue);
      expect(e.textCap, 200);
      expect(e.visionCap, isNull);
      expect(e.reminderCap, 5);
      expect(e.petCap, 1);
    });
  });

  group('Entitlement quota-exhaustion derivations', () {
    test('isTextQuotaExhausted true at exact cap, true above, false below',
        () {
      final e = Entitlement.freeAnonymous();
      expect(e.copyWith(monthlyTextCount: 199).isTextQuotaExhausted, isFalse);
      expect(e.copyWith(monthlyTextCount: 200).isTextQuotaExhausted, isTrue);
      expect(e.copyWith(monthlyTextCount: 999).isTextQuotaExhausted, isTrue);
    });

    test('isTextQuotaExhausted always false for unmetered states', () {
      final pro = Entitlement(
        state: EntitlementState.proMonthly,
        userId: 'user-123',
        monthlyTextCount: 9999,
        counterPeriodStart: DateTime(2026, 5),
      );
      expect(pro.isTextQuotaExhausted, isFalse);

      final byok = Entitlement(
        state: EntitlementState.byok,
        userId: 'user-456',
        monthlyTextCount: 9999,
        counterPeriodStart: DateTime(2026, 5),
      );
      expect(byok.isTextQuotaExhausted, isFalse);
    });

    test('isVisionQuotaExhausted respects the credit-pack rollover', () {
      final pro = Entitlement(
        state: EntitlementState.proMonthly,
        userId: 'user-123',
        monthlyVisionCount: 30,
        counterPeriodStart: DateTime(2026, 5),
      );
      expect(pro.isVisionQuotaExhausted, isTrue,
          reason: '30/mo cap met, 0 credits → exhausted');

      // With credits, vision keeps flowing.
      expect(
        pro.copyWith(photoCreditsBalance: 50).isVisionQuotaExhausted,
        isFalse,
        reason: '30/mo cap met but 50 credits remain — credits cover overage',
      );
    });

    test('isVisionQuotaExhausted always false for non-Pro '
        '(no vision feature OR unmetered BYOK)', () {
      final free = Entitlement.freeAnonymous();
      expect(free.copyWith(monthlyVisionCount: 9999).isVisionQuotaExhausted,
          isFalse);

      final byok = Entitlement(
        state: EntitlementState.byok,
        userId: 'u',
        monthlyVisionCount: 9999,
        counterPeriodStart: DateTime(2026, 5),
      );
      expect(byok.isVisionQuotaExhausted, isFalse);
    });
  });

  group('Entitlement equality + copyWith', () {
    test('equality compares all fields', () {
      final a = Entitlement.freeAnonymous(now: DateTime(2026, 5));
      final b = Entitlement.freeAnonymous(now: DateTime(2026, 5));
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);

      final c = a.copyWith(monthlyTextCount: 1);
      expect(c, isNot(equals(a)));
    });

    test('copyWith preserves unprovided fields', () {
      final base = Entitlement(
        state: EntitlementState.proMonthly,
        userId: 'user-x',
        renewalDate: DateTime(2026, 6),
        photoCreditsBalance: 25,
        monthlyTextCount: 100,
        monthlyVisionCount: 5,
        counterPeriodStart: DateTime(2026, 5),
        fetchedAt: DateTime(2026, 5, 15),
      );
      final updated = base.copyWith(monthlyTextCount: 101);
      expect(updated.monthlyTextCount, 101);
      expect(updated.userId, base.userId);
      expect(updated.renewalDate, base.renewalDate);
      expect(updated.photoCreditsBalance, base.photoCreditsBalance);
      expect(updated.fetchedAt, base.fetchedAt);
    });
  });
}

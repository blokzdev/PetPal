/// Phase 6 task 6.4 — VisionGate stub. Both 6.5 (extractor) and 6.9
/// (chat upload) call through this gate before issuing a vision
/// request to the LLM. Phase 7 task D.1 plugged in the real
/// entitlement check (Pro tier active OR photo-credit balance > 0)
/// without a code re-shape — the abstract surface stays.
///
/// v1 contract (DECISIONS row 36):
/// - Anonymous / free signed-in (no BYOK): NO vision feature.
///   Vision is Pro-only. Gate blocks with the upgrade prompt.
/// - Free + BYOK: unmetered (calls go direct to Anthropic with
///   the user's key; this gate's allow path lets the request
///   through; the user pays Anthropic).
/// - Pro: 30 vision/mo cap (counter on Supabase) + photo-credit
///   balance for overage. The combined check fires only when
///   BOTH are exhausted.
library;

import '../../app/entitlement/entitlement.dart';

abstract class VisionGate {
  /// Check whether a vision call is allowed at this moment for
  /// this user. Returns a [VisionGateDecision] with the verdict
  /// and an optional reason for blocked decisions (the chat
  /// surface renders `reason` as user-facing copy when blocked).
  Future<VisionGateDecision> check();
}

class VisionGateDecision {
  const VisionGateDecision._({required this.isAllowed, this.reason});

  /// Blocked — caller surfaces [reason] to the user.
  factory VisionGateDecision.blocked(String reason) =>
      VisionGateDecision._(isAllowed: false, reason: reason);

  /// Allowed — proceed with the vision call.
  static const VisionGateDecision allowed =
      VisionGateDecision._(isAllowed: true);

  /// True when the vision call may proceed.
  final bool isAllowed;

  /// User-facing copy when [isAllowed] is false. Null when allowed.
  final String? reason;
}

/// Always-allowed implementation. Used in tests + as the v1 default
/// when the entitlement source isn't yet wired (e.g. during the
/// brief startup window before [entitlementProvider] resolves).
class StubVisionGate implements VisionGate {
  const StubVisionGate();

  @override
  Future<VisionGateDecision> check() async => VisionGateDecision.allowed;
}

/// Phase 7 task D.1 — production VisionGate.
///
/// Reads the active entitlement at check time (pull, not push) so
/// the gate's verdict reflects the most recent reconciliation.
/// Caller is responsible for pumping the entitlement state into
/// the provider; this gate just consults what's there.
///
/// Decision matrix:
///   - Pro + cap NOT exhausted (cap met but credits remain) →
///     allowed. The credit-balance decrement happens at the proxy
///     side per row 82; the client doesn't decrement here.
///   - Pro + cap AND credit balance exhausted → blocked with
///     "buy a credit pack" copy (VOICE.md §6 example 13).
///   - Free + BYOK → allowed (user pays Anthropic directly).
///   - Free anonymous / Free signed-in (no BYOK) → blocked with
///     "vision is part of Pro" copy.
class RealVisionGate implements VisionGate {
  const RealVisionGate({required this.entitlementSource});

  /// Pulls the current [Entitlement]. Production wires this to
  /// `() => ref.read(entitlementProvider).value ?? Entitlement.freeAnonymous()`.
  /// Tests inject a static getter.
  final Entitlement Function() entitlementSource;

  @override
  Future<VisionGateDecision> check() async {
    final ent = entitlementSource();
    switch (ent.state) {
      case EntitlementState.proMonthly:
      case EntitlementState.proAnnual:
        if (ent.isVisionQuotaExhausted) {
          // Per VOICE.md §6 example 13.
          return VisionGateDecision.blocked(
            "Photo analysis: 30 a month on Pro. You've used this month's "
            "allowance. Top up with 50 more for \$2.99 — they don't "
            'expire, so unused ones roll into next month.',
          );
        }
        return VisionGateDecision.allowed;
      case EntitlementState.byok:
        // BYOK lifts the cost-driven cap; vision call is between
        // user and Anthropic.
        return VisionGateDecision.allowed;
      case EntitlementState.free:
      case EntitlementState.freeAnonymous:
        // Vision is a Pro feature per row 36.
        return VisionGateDecision.blocked(
          'Photo analysis is part of Pro — \$7.99/mo lifts every limit '
          'and unlocks photo memories.',
        );
    }
  }
}

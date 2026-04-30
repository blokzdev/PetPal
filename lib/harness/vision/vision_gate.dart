/// Phase 6 task 6.4 — VisionGate stub. Both 6.5 (extractor) and 6.9
/// (chat upload) call through this gate before issuing a vision
/// request to the LLM. Phase 7 task 7.10 plugs in the real
/// entitlement check (Pro tier active, photo-credit balance > 0)
/// without a code re-shape — the abstract surface stays.
///
/// v1 contract (DECISIONS row 36):
/// - Free tier (BYOK off): vision quota is part of the 200
///   message/month allowance; vision turns count as 1 message
///   each. The free user with no key configured can spend their
///   monthly quota on vision turns until 200 is hit.
/// - Free tier (BYOK on): unlimited vision (BYOK lifts the
///   quota in exchange for the user supplying their own
///   Anthropic key).
/// - Pro: unmetered text + 30 vision/mo + photo-credit packs
///   for overage. The 30/mo cap is enforced in the gate's Pro
///   branch landing in Phase 7.
///
/// Phase 6 stub: always allowed. The gate exists now so 6.5 + 6.6
/// + 6.9 wire through it; Phase 7 swaps the implementation.
library;

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
  /// Phase 7 fills this with quota / paywall messaging keyed off
  /// the entitlement state.
  final String? reason;
}

/// Always-allowed implementation for Phase 6. Phase 7 task 7.10
/// replaces this with `RealVisionGate` (entitlement service +
/// photo-credit-balance enforcement) wired through the same
/// `visionGateProvider`.
class StubVisionGate implements VisionGate {
  const StubVisionGate();

  @override
  Future<VisionGateDecision> check() async => VisionGateDecision.allowed;
}

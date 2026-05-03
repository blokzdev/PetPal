import 'package:collection/collection.dart' show SetEquality;
import 'package:flutter/foundation.dart' show immutable;

/// Phase 7 Group B.1 — entitlement state machine.
///
/// Mirrors the Supabase canonical states (DECISIONS row 36 + 78) plus
/// two implicit states the local model needs: anonymous (signed-out
/// free) and BYOK (free-tier modifier per row 36).
///
/// State derivation:
///   - `freeAnonymous` — no auth, no entitlements row. Default on
///     fresh install before sign-in. Subject to 200 msg/mo cap on the
///     proxy path.
///   - `free` — signed-in, no Pro subscription. Same 200 msg/mo cap.
///   - `proMonthly` / `proAnnual` — active Pro subscription. Unmetered
///     text; 30 vision/mo + photo-credit balance; sync; multi-pet;
///     unlimited reminders.
///   - `byok` — free tier with the BYOK toggle on. Calls route via
///     [DirectTransport] straight to api.anthropic.com using the
///     user's own key. No quotas (user pays Anthropic directly).
///     Sync, multi-pet, and unlimited reminders are NOT unlocked
///     (per row 36 BYOK lane: cost-driven caps lift only).
enum EntitlementState {
  freeAnonymous,
  free,
  proMonthly,
  proAnnual,
  byok;

  /// True for active Pro subscribers (monthly or annual).
  bool get isPro => this == EntitlementState.proMonthly ||
      this == EntitlementState.proAnnual;

  /// True for any free path (anonymous or signed-in non-Pro).
  bool get isFree =>
      this == EntitlementState.freeAnonymous || this == EntitlementState.free;

  /// True when the text-chat quota gate fires. False for Pro and BYOK
  /// (both paths are unmetered for text per row 36).
  bool get isTextMetered => isFree;

  /// True when vision quota gate fires. Pro is metered (30/mo +
  /// credit packs); free has no vision feature; BYOK is unmetered.
  bool get isVisionMetered => isPro;

  /// True when the agent loop should route through `ProxyTransport`
  /// (the funded path). False only for BYOK, which routes through
  /// `DirectTransport` straight to Anthropic.
  bool get usesProxy => this != EntitlementState.byok;

  /// Free-tier text-chat cap per row 36. Null for Pro + BYOK
  /// (unmetered).
  int? get textCap => isTextMetered ? 200 : null;

  /// Pro-tier monthly vision cap per row 36. Null for non-Pro.
  int? get visionCap => isPro ? 30 : null;

  /// Free-tier reminder cap per row 36. Null for Pro (unlimited).
  /// BYOK keeps the 5-cap — reminders are server-cost-trivial UX,
  /// not a cost-driven gate, and BYOK lifts COST-driven caps only.
  /// (Row 36: "BYOK does NOT unlock sync, multi-pet, and unlimited
  /// reminders — those are Pro-only.")
  int? get reminderCap => isPro ? null : 5;

  /// Free-tier pet count cap per row 36. Null for Pro (unlimited).
  /// BYOK keeps the 1-pet cap (multi-pet is a Pro UX feature, not
  /// a cost-driven gate).
  int? get petCap => isPro ? null : 1;

  static EntitlementState fromWire(String wireValue) {
    switch (wireValue) {
      case 'free':
        return EntitlementState.free;
      case 'pro_monthly':
        return EntitlementState.proMonthly;
      case 'pro_annual':
        return EntitlementState.proAnnual;
      case 'byok':
        return EntitlementState.byok;
      default:
        // Unknown server-side state → treat as free-signed-in, never
        // upgrade silently. The reconciliation pass should warn.
        return EntitlementState.free;
    }
  }

  String get wireValue {
    switch (this) {
      case EntitlementState.freeAnonymous:
      case EntitlementState.free:
        return 'free';
      case EntitlementState.proMonthly:
        return 'pro_monthly';
      case EntitlementState.proAnnual:
        return 'pro_annual';
      case EntitlementState.byok:
        return 'byok';
    }
  }
}

/// Immutable snapshot of the active user's entitlement.
///
/// Read by:
///   - The agent loop's quota gate (DECISIONS row 75) — checks
///     [state] + [monthlyTextCount] + [textCap] before each chat call
///     to decide whether to even attempt the proxy round-trip.
///   - The Settings screen (Pro badge, message counter, BYOK toggle
///     state, photo credit balance display).
///   - The paywall dispatcher — surfaces the upgrade screen on Pro
///     gates.
@immutable
class Entitlement {
  const Entitlement({
    required this.state,
    this.userId,
    this.renewalDate,
    this.graceUntil,
    this.photoCreditsBalance = 0,
    this.monthlyTextCount = 0,
    this.monthlyVisionCount = 0,
    required this.counterPeriodStart,
    this.fetchedAt,
    this.ownedCarePackSkillIds = const <String>{},
  });

  /// Synthetic default for signed-out users. Reconciliation against
  /// Supabase replaces this once auth lands.
  factory Entitlement.freeAnonymous({DateTime? now}) {
    final t = now ?? DateTime.now();
    return Entitlement(
      state: EntitlementState.freeAnonymous,
      counterPeriodStart: DateTime(t.year, t.month),
    );
  }

  /// Phase 7 task F.1 — synthetic default for the BYOK lane.
  ///
  /// BYOK is a free-tier modifier (DECISIONS row 36): the user
  /// supplies their own Anthropic key, calls go direct via
  /// [DirectTransport], and the cost-driven caps lift (text +
  /// vision + synthesis). Sync, multi-pet, and the 5-reminder cap
  /// remain Pro-only — those aren't cost-driven gates.
  factory Entitlement.byok({DateTime? now}) {
    final t = now ?? DateTime.now();
    return Entitlement(
      state: EntitlementState.byok,
      counterPeriodStart: DateTime(t.year, t.month),
    );
  }

  final EntitlementState state;

  /// Supabase auth user ID (UUID). Null for [EntitlementState.freeAnonymous].
  final String? userId;

  /// Subscription anniversary; null for free + byok.
  final DateTime? renewalDate;

  /// Grace window after a billing failure. Null when not in grace.
  final DateTime? graceUntil;

  /// Photo credit pack balance per row 36 ($2.99 = 50, rolls over
  /// indefinitely).
  final int photoCreditsBalance;

  /// Monthly text-chat counter mirrored from Supabase. Display-only;
  /// the canonical counter lives server-side (the proxy increments
  /// atomically per DECISIONS row 75). UI surfaces this for VOICE.md
  /// §6 example 11 ("127 / 200 used this month").
  final int monthlyTextCount;

  /// Monthly vision-call counter mirrored from Supabase. Pro-only
  /// (free + BYOK have no vision feature; row 36).
  final int monthlyVisionCount;

  /// Counter period anchor — counters reset when this + 1 month elapses.
  final DateTime counterPeriodStart;

  /// When this snapshot was last reconciled with Supabase. Null for
  /// the synthetic [freeAnonymous] default.
  final DateTime? fetchedAt;

  /// Phase 7 task C.3 — skill IDs the user has unlocked via care
  /// pack purchases. Pro users implicitly have access to every
  /// `requiresPro` skill regardless of this set; non-Pro users
  /// access a `requiresPro` skill only if its ID is in this set.
  ///
  /// Authoritative value lives on Supabase (per the
  /// play-billing-verify Edge Function); this field is the
  /// optimistic local mirror.
  final Set<String> ownedCarePackSkillIds;

  bool get isPro => state.isPro;
  bool get isFree => state.isFree;
  bool get isTextMetered => state.isTextMetered;
  bool get isVisionMetered => state.isVisionMetered;
  bool get usesProxy => state.usesProxy;
  int? get textCap => state.textCap;
  int? get visionCap => state.visionCap;
  int? get reminderCap => state.reminderCap;
  int? get petCap => state.petCap;

  /// True when text quota has been exhausted (cap met or exceeded).
  /// Always false for unmetered states.
  bool get isTextQuotaExhausted {
    final cap = textCap;
    return cap != null && monthlyTextCount >= cap;
  }

  /// True when vision quota has been exhausted AND no credit-pack
  /// balance remains. Pro users buying credit packs (row 36) keep
  /// vision calls flowing past 30/mo via [photoCreditsBalance].
  bool get isVisionQuotaExhausted {
    final cap = visionCap;
    if (cap == null) return false;
    return monthlyVisionCount >= cap && photoCreditsBalance <= 0;
  }

  Entitlement copyWith({
    EntitlementState? state,
    String? userId,
    DateTime? renewalDate,
    DateTime? graceUntil,
    int? photoCreditsBalance,
    int? monthlyTextCount,
    int? monthlyVisionCount,
    DateTime? counterPeriodStart,
    DateTime? fetchedAt,
    Set<String>? ownedCarePackSkillIds,
  }) =>
      Entitlement(
        state: state ?? this.state,
        userId: userId ?? this.userId,
        renewalDate: renewalDate ?? this.renewalDate,
        graceUntil: graceUntil ?? this.graceUntil,
        photoCreditsBalance: photoCreditsBalance ?? this.photoCreditsBalance,
        monthlyTextCount: monthlyTextCount ?? this.monthlyTextCount,
        monthlyVisionCount: monthlyVisionCount ?? this.monthlyVisionCount,
        counterPeriodStart: counterPeriodStart ?? this.counterPeriodStart,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        ownedCarePackSkillIds:
            ownedCarePackSkillIds ?? this.ownedCarePackSkillIds,
      );

  @override
  bool operator ==(Object other) =>
      other is Entitlement &&
      other.state == state &&
      other.userId == userId &&
      other.renewalDate == renewalDate &&
      other.graceUntil == graceUntil &&
      other.photoCreditsBalance == photoCreditsBalance &&
      other.monthlyTextCount == monthlyTextCount &&
      other.monthlyVisionCount == monthlyVisionCount &&
      other.counterPeriodStart == counterPeriodStart &&
      other.fetchedAt == fetchedAt &&
      const SetEquality<String>().equals(
        other.ownedCarePackSkillIds,
        ownedCarePackSkillIds,
      );

  @override
  int get hashCode => Object.hash(
        state,
        userId,
        renewalDate,
        graceUntil,
        photoCreditsBalance,
        monthlyTextCount,
        monthlyVisionCount,
        counterPeriodStart,
        fetchedAt,
        const SetEquality<String>().hash(ownedCarePackSkillIds),
      );

  @override
  String toString() => 'Entitlement(state=$state, userId=$userId, '
      'textCount=$monthlyTextCount/$textCap, '
      'visionCount=$monthlyVisionCount/$visionCap, '
      'credits=$photoCreditsBalance)';
}

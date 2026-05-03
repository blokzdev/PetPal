import 'entitlement.dart';

/// Phase 7 task D.1 — quota exhaustion signal.
///
/// Thrown by the four client-side quota gates (chat / vision /
/// reminders / pet count) when the active [Entitlement] prohibits
/// the action. The chat surface, settings, paywall dispatcher, and
/// add-pet flow catch this and surface the right paywall prompt
/// per VOICE.md §6 examples 9 + 13 + 14.
///
/// Server enforcement (the proxy's canonical text counter per
/// DECISIONS row 75) is independent — when the server sends 402,
/// `ProxyTransport` surfaces it as `AnthropicApiException` with
/// `statusCode: 402`; the chat notifier maps that to
/// `ChatErrorCategory.quotaExceeded`. So the client-side gate IS
/// a UX optimization (skip the round-trip when we can predict the
/// server will say no), not a load-bearing security boundary.
sealed class QuotaExceededException implements Exception {
  const QuotaExceededException(this.entitlement);

  /// The entitlement state that triggered the gate. Caller uses
  /// this to render the right upgrade ladder ("Pro lifts the
  /// limit, or switch to your own Anthropic key" for text;
  /// "buy a credit pack" for vision; etc.).
  final Entitlement entitlement;

  /// Short label used by the paywall dispatcher's `switch`.
  String get kind;

  @override
  String toString() => 'QuotaExceededException($kind, '
      'state=${entitlement.state})';
}

/// Free-tier 200 msg/mo cap exhausted. Per VOICE.md §6 example 14
/// the upgrade ladder offers Pro OR BYOK as escape valves.
class TextQuotaExceeded extends QuotaExceededException {
  const TextQuotaExceeded(super.entitlement);
  @override
  String get kind => 'text';
}

/// Pro-tier 30 vision/mo cap + photo-credit balance both exhausted.
/// Per VOICE.md §6 example 13 the upgrade ladder offers a credit
/// pack purchase ($2.99 = 50 credits, rolls over).
class VisionQuotaExceeded extends QuotaExceededException {
  const VisionQuotaExceeded(super.entitlement);
  @override
  String get kind => 'vision';
}

/// Free-tier 5-reminder cap. Per VOICE.md §6 example 14 register
/// the upgrade is to Pro (BYOK does NOT lift the reminder cap per
/// row 36 — reminders are a server-cost-trivial UX feature, not a
/// cost-driven gate).
class ReminderQuotaExceeded extends QuotaExceededException {
  const ReminderQuotaExceeded(super.entitlement);
  @override
  String get kind => 'reminder';
}

/// Free-tier 1-pet cap. Per VOICE.md §6 example 9 ("You already
/// have a pet on the free plan. Adding a second pet is part of
/// Pro.").
class PetQuotaExceeded extends QuotaExceededException {
  const PetQuotaExceeded(super.entitlement);
  @override
  String get kind => 'pet';
}

/// Sync requested but the active tier doesn't include it. Sync is
/// Pro-only per row 36 (BYOK does NOT unlock sync — sync is a
/// server-cost feature). Stub at D.1 because CloudSyncAdapter is
/// itself a stub until G.2; the gate is here so G.2 has the
/// throwing path ready.
class SyncQuotaExceeded extends QuotaExceededException {
  const SyncQuotaExceeded(super.entitlement);
  @override
  String get kind => 'sync';
}

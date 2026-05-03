/// Phase 7 Group C — Play Console product IDs.
///
/// **These IDs MUST match the Play Console product registrations exactly.**
/// They're the contract between the Flutter client and Play Billing;
/// once a product is published with a given ID, the ID can never be
/// changed without orphaning all existing purchases.
///
/// Naming convention (locked for v1):
///   - Subscriptions: `pro_<period>` — short, period-suffixed.
///   - Consumables: `<feature>_<quantity>` — vision credit packs.
///   - Non-consumable IAPs: `<feature>_<slug>` — care packs, expert packs.
///
/// All product registration in Play Console (sandbox + production)
/// uses these exact strings. The deploy checklist (later commit at
/// the C-group wrap-up) will enumerate them as the manual setup step
/// the user does in Play Console.
abstract final class ProductIds {
  // ─── Subscriptions (DECISIONS row 36 pricing locks) ──────────────────

  /// Pro monthly subscription — $7.99/mo.
  static const proMonthly = 'pro_monthly';

  /// Pro annual subscription — $59/yr.
  static const proAnnual = 'pro_annual';

  // ─── Consumable IAPs ─────────────────────────────────────────────────

  /// Photo credit pack — $2.99 = 50 vision analyses (rolls over
  /// indefinitely per row 36).
  static const photoCredits50 = 'photo_credits_50';

  // ─── Non-consumable IAPs (care packs, expert packs) ──────────────────

  /// Care pack: Reactive Dog ($2.99–$4.99 range; first care pack to ship).
  static const carePackReactiveDog = 'care_pack_reactive_dog';

  /// Expert pack: Senior Dog Care ($14.99–$39.99 range). May defer to
  /// v1.x per the Stage 1 plan; ID reserved here so Play Console
  /// product registration can land in Phase 7 alongside the rest.
  static const expertPackSeniorDog = 'expert_pack_senior_dog';

  // ─── Grouped sets for convenience ────────────────────────────────────

  /// All subscription product IDs.
  static const subscriptions = <String>{proMonthly, proAnnual};

  /// All consumable product IDs.
  static const consumables = <String>{photoCredits50};

  /// All non-consumable product IDs (care + expert packs).
  static const nonConsumables = <String>{
    carePackReactiveDog,
    expertPackSeniorDog,
  };

  /// Every product ID the Flutter client queries from Play. The
  /// `BillingService.initialize()` pass uses this to pre-fetch
  /// `ProductDetails` so the paywall renders instantly without a
  /// per-tap network round-trip.
  static const all = <String>{
    proMonthly,
    proAnnual,
    photoCredits50,
    carePackReactiveDog,
    expertPackSeniorDog,
  };

  /// Phase 7 task C.2 — quantity granted per consumable purchase.
  /// Adding a new credit pack (e.g. `photo_credits_200` in v1.x) is
  /// a one-line change here + Play Console product registration; the
  /// dispatch path in `BillingService` reads from this map.
  static const creditPackQuantities = <String, int>{
    photoCredits50: 50,
  };
}

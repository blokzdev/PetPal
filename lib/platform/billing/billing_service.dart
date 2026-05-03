import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../app/entitlement/entitlement.dart';
import 'iap_platform.dart';
import 'product_ids.dart';

/// Phase 7 Group C — high-level Play Billing facade.
///
/// Wraps [IapPlatform] with PetPal-specific purchase flows. Owns the
/// `purchaseStream` subscription, dispatches `purchased` /
/// `restored` events to the entitlement layer, and surfaces
/// [BillingEvent]s for the paywall UI.
///
/// **Server verification is stubbed in C.1.** On `purchased`, the
/// service emits an OPTIMISTIC entitlement update (the user sees Pro
/// immediately) and pings the backend for canonical verification in
/// the background. The backend round-trip lands when the
/// `play-billing-verify` Edge Function ships (post-Group-C wiring) —
/// for C.1 the optimistic emit IS the entitlement update; the user
/// must trust the device-side state until the server-side
/// reconciliation pass overwrites it.
class BillingService {
  BillingService({
    required IapPlatform iap,
    required Future<void> Function(Entitlement) onOptimisticEntitlement,
    Future<void> Function(int credits)? onPhotoCreditsGranted,
  })  : _iap = iap,
        _onOptimisticEntitlement = onOptimisticEntitlement,
        _onPhotoCreditsGranted = onPhotoCreditsGranted;

  final IapPlatform _iap;
  final Future<void> Function(Entitlement) _onOptimisticEntitlement;
  final Future<void> Function(int credits)? _onPhotoCreditsGranted;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  final StreamController<BillingEvent> _events =
      StreamController<BillingEvent>.broadcast();

  bool _initialized = false;
  bool _available = false;
  Map<String, ProductDetails> _products = const {};

  /// Broadcast stream of purchase outcomes — paywall UI listens for
  /// success / error / cancel toasts. Multiple listeners OK.
  Stream<BillingEvent> get events => _events.stream;

  bool get isAvailable => _available;
  bool get isInitialized => _initialized;
  Map<String, ProductDetails> get products => Map.unmodifiable(_products);

  /// Pre-fetch products + start listening for purchase updates. Idempotent.
  ///
  /// **Call at app start, not lazily** — Play redelivers any
  /// pending-on-relaunch purchases through the stream as soon as
  /// it's subscribed; missing the subscription window means the
  /// purchase has to flow through `restorePurchases` on the next
  /// app launch (worse UX).
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _available = await _iap.isAvailable();
    if (!_available) {
      _events.add(const BillingEvent.unavailable());
      return;
    }

    _purchaseSub = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object e, StackTrace st) {
        _events.add(BillingEvent.error('purchase stream error: $e'));
      },
    );

    final response = await _iap.queryProductDetails(ProductIds.all);
    if (response.error != null) {
      _events.add(
        BillingEvent.error('product query failed: ${response.error!.message}'),
      );
      return;
    }
    _products = {
      for (final p in response.productDetails) p.id: p,
    };
    if (response.notFoundIDs.isNotEmpty) {
      // Product IDs unknown to Play — most commonly because the
      // sandbox tester account hasn't been added to the test track,
      // or the product hasn't been activated in Play Console. Surface
      // for dev visibility but don't block initialization (some
      // products may still be queryable).
      debugPrint(
        'BillingService: products not found in Play Console: '
        '${response.notFoundIDs}',
      );
    }
    _events.add(BillingEvent.ready(_products.values.toList(growable: false)));
  }

  /// Trigger a Pro subscription purchase. Use [annual]=false for the
  /// monthly tier, true for annual. Result arrives via [events] —
  /// caller listens, does NOT await this future for completion.
  ///
  /// Returns `true` when the request was successfully sent to Play
  /// (the user sees the Play sheet). `false` when the product isn't
  /// loaded or the request couldn't be dispatched.
  Future<bool> buyPro({required bool annual}) async {
    final productId = annual ? ProductIds.proAnnual : ProductIds.proMonthly;
    return _buyNonConsumableById(productId);
  }

  /// Phase 7 task C.2 — trigger a consumable photo-credit-pack
  /// purchase ($2.99 = 50 credits per row 36, rolls over indefinitely).
  /// On success, [_onPhotoCreditsGranted] is called with the
  /// quantity (50); the provider wiring increments the cached
  /// `photoCreditsBalance` on the active entitlement via
  /// `EntitlementNotifier.setOptimistic`.
  ///
  /// Result arrives via [events]; caller listens.
  Future<bool> buyPhotoCredits() =>
      _buyConsumableById(ProductIds.photoCredits50);

  /// Restore previous non-consumable purchases (subs + care packs).
  /// Restored purchases stream through [events] as `purchased` /
  /// `restored` outcomes. **Consumable purchases (photo credits) are
  /// NOT restorable by Play** — credits granted but never consumed
  /// stay on the account, but Play's `restorePurchases` doesn't
  /// surface them (consumables are "owned" only briefly between
  /// grant and consume). The backend tracks credit balance
  /// canonically per row 82.
  Future<void> restorePurchases({String? userId}) =>
      _iap.restorePurchases(applicationUserName: userId);

  Future<bool> _buyNonConsumableById(String productId) async {
    if (!_available) {
      _events.add(const BillingEvent.unavailable());
      return false;
    }
    final product = _products[productId];
    if (product == null) {
      _events.add(BillingEvent.error('product not loaded: $productId'));
      return false;
    }
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  Future<bool> _buyConsumableById(String productId) async {
    if (!_available) {
      _events.add(const BillingEvent.unavailable());
      return false;
    }
    final product = _products[productId];
    if (product == null) {
      _events.add(BillingEvent.error('product not loaded: $productId'));
      return false;
    }
    // autoConsume: true is the plugin default — Play marks the
    // consumable as consumed after a successful purchase so the
    // user can buy another one. We additionally call completePurchase
    // in _onPurchaseSuccess (the plugin's auto-consume + our
    // completePurchase are both required for a clean Play handoff).
    return _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> updates) async {
    for (final purchase in updates) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _events.add(BillingEvent.pending(purchase.productID));
        case PurchaseStatus.canceled:
          _events.add(BillingEvent.canceled(purchase.productID));
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.error:
          _events.add(
            BillingEvent.error(
              purchase.error?.message ?? 'unknown purchase error',
              productId: purchase.productID,
            ),
          );
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _onPurchaseSuccess(purchase);
      }
    }
  }

  Future<void> _onPurchaseSuccess(PurchaseDetails purchase) async {
    // Optimistic entitlement / credits update. Server reconciliation
    // (when the play-billing-verify Edge Function ships) will
    // overwrite this with the canonical state from Supabase.
    final entitlement = _entitlementFor(purchase.productID);
    if (entitlement != null) {
      try {
        await _onOptimisticEntitlement(entitlement);
      } catch (e) {
        debugPrint('BillingService: optimistic entitlement update failed: $e');
      }
    } else {
      // Phase 7 task C.2 — consumable photo credit pack. Quantity
      // lookup from ProductIds.creditPackQuantities; the provider
      // wiring increments the cached photoCreditsBalance on the
      // active entitlement.
      final credits = ProductIds.creditPackQuantities[purchase.productID];
      final granted = _onPhotoCreditsGranted;
      if (credits != null && granted != null) {
        try {
          await granted(credits);
        } catch (e) {
          debugPrint('BillingService: optimistic credits grant failed: $e');
        }
      }
    }

    _events.add(
      purchase.status == PurchaseStatus.restored
          ? BillingEvent.restored(purchase.productID)
          : BillingEvent.purchased(purchase.productID),
    );

    if (purchase.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(purchase);
      } catch (e) {
        debugPrint('BillingService: completePurchase failed: $e');
      }
    }
  }

  /// Map a successful purchase product ID to the entitlement to emit.
  /// Returns null for products that don't map to entitlement state
  /// changes (consumables, care packs handled via separate paths in
  /// C.2/C.3).
  Entitlement? _entitlementFor(String productId) {
    final now = DateTime.now();
    switch (productId) {
      case ProductIds.proMonthly:
        return Entitlement(
          state: EntitlementState.proMonthly,
          // userId resolves once auth wires (Group F.1); B.1's
          // setOptimistic accepts null userId for anonymous-but-Pro
          // (rare; happens during the brief window between purchase
          // success and the post-IAP reconciliation that ties the
          // purchase to the signed-in account).
          renewalDate: DateTime(now.year, now.month + 1, now.day),
          counterPeriodStart: DateTime(now.year, now.month),
        );
      case ProductIds.proAnnual:
        return Entitlement(
          state: EntitlementState.proAnnual,
          renewalDate: DateTime(now.year + 1, now.month, now.day),
          counterPeriodStart: DateTime(now.year, now.month),
        );
      case ProductIds.photoCredits50:
      case ProductIds.carePackReactiveDog:
      case ProductIds.expertPackSeniorDog:
        // Consumables + care packs don't change Pro state; balance /
        // installation is handled in C.2 / C.3 dispatch paths.
        return null;
      default:
        debugPrint('BillingService: unknown product id $productId');
        return null;
    }
  }

  Future<void> dispose() async {
    await _purchaseSub?.cancel();
    await _events.close();
  }
}

/// Outcomes the paywall + Settings surface listen for.
sealed class BillingEvent {
  const BillingEvent();

  const factory BillingEvent.unavailable() = BillingUnavailable;
  const factory BillingEvent.ready(List<ProductDetails> products) =
      BillingReady;
  const factory BillingEvent.pending(String productId) = BillingPending;
  const factory BillingEvent.purchased(String productId) = BillingPurchased;
  const factory BillingEvent.restored(String productId) = BillingRestored;
  const factory BillingEvent.canceled(String productId) = BillingCanceled;
  const factory BillingEvent.error(String message, {String? productId}) =
      BillingError;
}

class BillingUnavailable extends BillingEvent {
  const BillingUnavailable();
}

class BillingReady extends BillingEvent {
  const BillingReady(this.products);
  final List<ProductDetails> products;
}

class BillingPending extends BillingEvent {
  const BillingPending(this.productId);
  final String productId;
}

class BillingPurchased extends BillingEvent {
  const BillingPurchased(this.productId);
  final String productId;
}

class BillingRestored extends BillingEvent {
  const BillingRestored(this.productId);
  final String productId;
}

class BillingCanceled extends BillingEvent {
  const BillingCanceled(this.productId);
  final String productId;
}

class BillingError extends BillingEvent {
  const BillingError(this.message, {this.productId});
  final String message;
  final String? productId;
}

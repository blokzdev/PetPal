import 'package:in_app_purchase/in_app_purchase.dart';

/// Phase 7 Group C — testable façade over the `in_app_purchase` plugin.
///
/// The plugin exposes a singleton (`InAppPurchase.instance`) with a
/// private constructor. Subclassing for tests isn't possible; the
/// canonical pattern is to wrap the singleton behind an interface
/// the production code talks to + inject the singleton in main().
/// Tests inject a fake.
abstract class IapPlatform {
  /// True when the underlying payment platform is reachable. Returns
  /// false on emulators without Play Services, on devices missing
  /// the Play Store, or when Play Billing's connection handshake
  /// fails. The paywall surfaces a "billing unavailable" empty state
  /// when this is false.
  Future<bool> isAvailable();

  /// Pre-fetch [ProductDetails] for the given product IDs. Returns
  /// the response with `productDetails`, `notFoundIDs`, and an
  /// optional `error` field. Called once at app start so the paywall
  /// renders instantly.
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers);

  /// Trigger a non-consumable purchase (subscriptions + care packs +
  /// expert packs). The result arrives via [purchaseStream]; this
  /// future returns whether the request was sent successfully.
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam});

  /// Trigger a consumable purchase (photo credit packs). `autoConsume`
  /// is true by default; on Android the plugin auto-consumes after
  /// success so the user can buy more.
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  });

  /// Mark a purchase as fulfilled. Must be called for every
  /// `purchased` / `restored` `PurchaseDetails` after delivering the
  /// content (entitlement updated, credits granted, care pack
  /// installed) — otherwise Play will redeliver the purchase on
  /// next stream subscription.
  Future<void> completePurchase(PurchaseDetails purchase);

  /// Restore non-consumable purchases (subscriptions + care packs).
  /// Restored purchases stream through [purchaseStream] with status
  /// `restored`. v1 surfaces this on first sign-in to a Pro account
  /// from a new device.
  Future<void> restorePurchases({String? applicationUserName});

  /// Real-time purchase update stream. **Subscribe at app start** —
  /// purchases that complete while the app isn't listening are
  /// redelivered on next subscription.
  Stream<List<PurchaseDetails>> get purchaseStream;
}

/// Production [IapPlatform] backed by `InAppPurchase.instance`.
class IapPlatformImpl implements IapPlatform {
  IapPlatformImpl({InAppPurchase? iap}) : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) =>
      _iap.queryProductDetails(identifiers);

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) =>
      _iap.buyNonConsumable(purchaseParam: purchaseParam);

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) =>
      _iap.buyConsumable(
        purchaseParam: purchaseParam,
        autoConsume: autoConsume,
      );

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);

  @override
  Future<void> restorePurchases({String? applicationUserName}) =>
      _iap.restorePurchases(applicationUserName: applicationUserName);

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;
}

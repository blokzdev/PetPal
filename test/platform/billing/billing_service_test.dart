import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/platform/billing/billing_service.dart';
import 'package:petpal/platform/billing/iap_platform.dart';
import 'package:petpal/platform/billing/product_ids.dart';

/// Phase 7 task C.1 — Play Billing flow invariants.
///
/// Pins the BillingService contract: initialization handshake,
/// subscription purchase dispatch, optimistic entitlement on
/// success, error / cancel surfacing, restore purchases. Uses a
/// `_FakeIap` impl of the [IapPlatform] interface so the tests
/// don't touch the real plugin (which can't be initialized in
/// `flutter test` — no Play Services).
void main() {
  late _FakeIap iap;
  late List<Entitlement> optimisticUpdates;
  late List<int> creditGrants;
  late List<String> carePackGrants;
  late BillingService service;
  late StreamSubscription<BillingEvent> sub;
  late List<BillingEvent> events;

  // Hoisted helper so test bodies can call before its declaration. Cannot
  // be a local function (Dart forbids forward-reference); cannot be
  // top-level (it closes over `iap`, `service`, `events`).
  Future<void> initReady() async {
    iap.available = true;
    iap.productResponse = ProductDetailsResponse(
      productDetails: [
        _stubProduct(ProductIds.proMonthly, '\$7.99'),
        _stubProduct(ProductIds.proAnnual, '\$59.00'),
        _stubProduct(ProductIds.photoCredits50, '\$2.99'),
        _stubProduct(ProductIds.carePackReactiveDog, '\$2.99'),
      ],
      notFoundIDs: const [],
    );
    await service.initialize();
    events.clear();
  }

  setUp(() {
    iap = _FakeIap();
    optimisticUpdates = [];
    creditGrants = [];
    carePackGrants = [];
    service = BillingService(
      iap: iap,
      onOptimisticEntitlement: (ent) async {
        optimisticUpdates.add(ent);
      },
      onPhotoCreditsGranted: (credits) async {
        creditGrants.add(credits);
      },
      onCarePackOwned: (skillId) async {
        carePackGrants.add(skillId);
      },
    );
    events = [];
    sub = service.events.listen(events.add);
  });

  tearDown(() async {
    await sub.cancel();
    await service.dispose();
  });

  group('initialize', () {
    test('emits BillingUnavailable + skips product query when '
        'isAvailable returns false', () async {
      iap.available = false;
      await service.initialize();
      await pumpEventQueue();

      expect(service.isAvailable, isFalse);
      expect(events.last, isA<BillingUnavailable>());
      expect(iap.productQueryCount, 0);
    });

    test('queries products + emits BillingReady when available', () async {
      iap.available = true;
      iap.productResponse = ProductDetailsResponse(
        productDetails: [
          _stubProduct(ProductIds.proMonthly, '\$7.99'),
          _stubProduct(ProductIds.proAnnual, '\$59.00'),
        ],
        notFoundIDs: const [],
      );

      await service.initialize();
      await pumpEventQueue();

      expect(service.isAvailable, isTrue);
      expect(iap.productQueryCount, 1);
      expect(iap.productQueryArg, ProductIds.all);
      expect(service.products[ProductIds.proMonthly], isNotNull);
      expect(service.products[ProductIds.proAnnual], isNotNull);
      expect(events.last, isA<BillingReady>());
    });

    test('idempotent — second call is a no-op', () async {
      iap.available = true;
      iap.productResponse = ProductDetailsResponse(
        productDetails: [_stubProduct(ProductIds.proMonthly, '\$7.99')],
        notFoundIDs: const [],
      );

      await service.initialize();
      await service.initialize();

      expect(iap.productQueryCount, 1);
    });

    test('surfaces product query errors as BillingError', () async {
      iap.available = true;
      iap.productResponse = ProductDetailsResponse(
        productDetails: const [],
        notFoundIDs: const [],
        error: IAPError(
          source: 'test',
          code: 'fake_error',
          message: 'Play handshake failed',
        ),
      );

      await service.initialize();
      await pumpEventQueue();

      expect(events.last, isA<BillingError>());
      final err = events.last as BillingError;
      expect(err.message, contains('Play handshake failed'));
    });
  });

  group('buyPro', () {
    test('triggers buyNonConsumable with the proMonthly product', () async {
      await initReady();

      final ok = await service.buyPro(annual: false);
      expect(ok, isTrue);
      expect(iap.lastNonConsumableProductId, ProductIds.proMonthly);
    });

    test('triggers buyNonConsumable with the proAnnual product', () async {
      await initReady();

      final ok = await service.buyPro(annual: true);
      expect(ok, isTrue);
      expect(iap.lastNonConsumableProductId, ProductIds.proAnnual);
    });

    test('returns false + emits unavailable when billing unavailable',
        () async {
      iap.available = false;
      await service.initialize();
      await pumpEventQueue();
      events.clear();

      final ok = await service.buyPro(annual: false);
      await pumpEventQueue();
      expect(ok, isFalse);
      expect(events.last, isA<BillingUnavailable>());
    });

    test('returns false + emits BillingError when product not loaded',
        () async {
      iap.available = true;
      iap.productResponse = ProductDetailsResponse(
        productDetails: const [], // no products loaded
        notFoundIDs: ProductIds.all.toList(),
      );
      await service.initialize();
      await pumpEventQueue();
      events.clear();

      final ok = await service.buyPro(annual: false);
      await pumpEventQueue();
      expect(ok, isFalse);
      expect(events.last, isA<BillingError>());
      expect((events.last as BillingError).message, contains('pro_monthly'));
    });
  });

  group('purchaseStream — purchase outcomes', () {
    test('PURCHASED on proMonthly → optimistic Pro entitlement + '
        'BillingPurchased event + completePurchase called', () async {
      await initReady();

      iap.streamController.add([
        _purchaseDetails(
          ProductIds.proMonthly,
          PurchaseStatus.purchased,
          pendingComplete: true,
        ),
      ]);
      // Let the stream microtask settle.
      await Future<void>.delayed(Duration.zero);

      // Optimistic Pro emit fired.
      expect(optimisticUpdates, hasLength(1));
      expect(optimisticUpdates.first.state, EntitlementState.proMonthly);
      expect(optimisticUpdates.first.renewalDate, isNotNull);

      // Purchased event fired.
      expect(events.whereType<BillingPurchased>(), hasLength(1));
      expect(events.whereType<BillingPurchased>().first.productId,
          ProductIds.proMonthly);

      // completePurchase was called.
      expect(iap.completedPurchases, hasLength(1));
    });

    test('PURCHASED on proAnnual → optimistic ProAnnual entitlement', () async {
      await initReady();

      iap.streamController.add([
        _purchaseDetails(
          ProductIds.proAnnual,
          PurchaseStatus.purchased,
          pendingComplete: true,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(optimisticUpdates, hasLength(1));
      expect(optimisticUpdates.first.state, EntitlementState.proAnnual);
      // Annual renewal is ~1 year out.
      final r = optimisticUpdates.first.renewalDate!;
      final now = DateTime.now();
      expect(r.year, now.year + 1);
    });

    test('RESTORED on proMonthly → optimistic Pro emit + BillingRestored',
        () async {
      await initReady();

      iap.streamController.add([
        _purchaseDetails(
          ProductIds.proMonthly,
          PurchaseStatus.restored,
          pendingComplete: true,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(optimisticUpdates, hasLength(1));
      expect(optimisticUpdates.first.state, EntitlementState.proMonthly);
      expect(events.whereType<BillingRestored>(), hasLength(1));
    });

    test('PENDING → BillingPending event; no optimistic emit; '
        'no completePurchase', () async {
      await initReady();

      iap.streamController.add([
        _purchaseDetails(ProductIds.proMonthly, PurchaseStatus.pending),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<BillingPending>(), hasLength(1));
      expect(optimisticUpdates, isEmpty);
      expect(iap.completedPurchases, isEmpty);
    });

    test('CANCELED → BillingCanceled; no entitlement change', () async {
      await initReady();

      iap.streamController.add([
        _purchaseDetails(ProductIds.proMonthly, PurchaseStatus.canceled),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<BillingCanceled>(), hasLength(1));
      expect(optimisticUpdates, isEmpty);
    });

    test('ERROR → BillingError with productId; no entitlement change',
        () async {
      await initReady();

      iap.streamController.add([
        _purchaseDetails(
          ProductIds.proMonthly,
          PurchaseStatus.error,
          error: IAPError(
            source: 'test',
            code: 'declined',
            message: 'card declined',
            ),
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<BillingError>(), hasLength(1));
      final err = events.whereType<BillingError>().first;
      expect(err.message, contains('card declined'));
      expect(err.productId, ProductIds.proMonthly);
      expect(optimisticUpdates, isEmpty);
    });

    test('photo credit pack purchase does NOT change Pro state '
        '(state stays free; only photoCreditsBalance increments via '
        'the C.2 callback path)', () async {
      await initReady();

      iap.streamController.add([
        _purchaseDetails(
          ProductIds.photoCredits50,
          PurchaseStatus.purchased,
          pendingComplete: true,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      // Purchased event fires (UI shows success toast).
      expect(events.whereType<BillingPurchased>(), hasLength(1));
      // No state-change entitlement emit (the credits-grant callback
      // runs instead — see C.2 tests below).
      expect(optimisticUpdates, isEmpty);
      // Credits-grant callback fired with the right quantity.
      expect(creditGrants, hasLength(1));
      expect(creditGrants.first, 50);
      // completePurchase still called (auto-consume on Android +
      // explicit completePurchase together — both required).
      expect(iap.completedPurchases, hasLength(1));
    });
  });

  group('Phase 7 task C.2 — buyPhotoCredits', () {
    test('triggers buyConsumable with the photoCredits50 product',
        () async {
      await initReady();

      final ok = await service.buyPhotoCredits();
      expect(ok, isTrue);
      expect(iap.lastConsumableProductId, ProductIds.photoCredits50);
    });

    test('returns false + emits unavailable when billing unavailable',
        () async {
      iap.available = false;
      await service.initialize();
      await pumpEventQueue();
      events.clear();

      final ok = await service.buyPhotoCredits();
      await pumpEventQueue();
      expect(ok, isFalse);
      expect(events.last, isA<BillingUnavailable>());
    });

    test('returns false + emits BillingError when product not loaded',
        () async {
      iap.available = true;
      iap.productResponse = ProductDetailsResponse(
        productDetails: const [], // no products loaded
        notFoundIDs: ProductIds.all.toList(),
      );
      await service.initialize();
      await pumpEventQueue();
      events.clear();

      final ok = await service.buyPhotoCredits();
      await pumpEventQueue();
      expect(ok, isFalse);
      expect(events.last, isA<BillingError>());
      expect((events.last as BillingError).message,
          contains(ProductIds.photoCredits50));
    });

    test('PURCHASED on photoCredits50 → 50-credit grant via callback',
        () async {
      await initReady();

      iap.streamController.add([
        _purchaseDetails(
          ProductIds.photoCredits50,
          PurchaseStatus.purchased,
          pendingComplete: true,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(creditGrants, hasLength(1));
      expect(creditGrants.first, 50);
    });

    test('callback omitted on construction → grant is silently '
        'skipped (no exception)', () async {
      // Build a service with no credit-grant callback. PURCHASED
      // events on credit packs still fire BillingPurchased + complete
      // the purchase, but the credits-grant path is a no-op.
      final localIap = _FakeIap();
      final localService = BillingService(
        iap: localIap,
        onOptimisticEntitlement: (_) async {},
        // intentionally omit onPhotoCreditsGranted
      );
      final localEvents = <BillingEvent>[];
      final localSub = localService.events.listen(localEvents.add);
      localIap.available = true;
      localIap.productResponse = ProductDetailsResponse(
        productDetails: [_stubProduct(ProductIds.photoCredits50, '\$2.99')],
        notFoundIDs: const [],
      );
      await localService.initialize();
      await pumpEventQueue();

      localIap.streamController.add([
        _purchaseDetails(
          ProductIds.photoCredits50,
          PurchaseStatus.purchased,
          pendingComplete: true,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(localEvents.whereType<BillingPurchased>(), hasLength(1));
      expect(localIap.completedPurchases, hasLength(1));
      // No creditGrants array on the local service — the assertion
      // is just "no exception thrown."
      await localSub.cancel();
      await localService.dispose();
    });
  });

  group('restorePurchases', () {
    test('forwards to IapPlatform with userId as applicationUserName',
        () async {
      await initReady();

      await service.restorePurchases(userId: 'user-abc');
      expect(iap.restoreCalls, hasLength(1));
      expect(iap.restoreCalls.first, 'user-abc');
    });

    test('forwards null userId for anonymous users', () async {
      await initReady();

      await service.restorePurchases();
      expect(iap.restoreCalls, hasLength(1));
      expect(iap.restoreCalls.first, isNull);
    });
  });

  group('Phase 7 task C.3 — buyCarePack', () {
    test('triggers buyNonConsumable with the care pack product ID',
        () async {
      await initReady();

      final ok = await service.buyCarePack(ProductIds.carePackReactiveDog);
      expect(ok, isTrue);
      expect(iap.lastNonConsumableProductId, ProductIds.carePackReactiveDog);
    });

    test('rejects unknown product IDs (not in carePackToSkillId map) — '
        'returns false + emits BillingError without dispatching to IAP',
        () async {
      await initReady();

      final ok = await service.buyCarePack('not_a_care_pack');
      await pumpEventQueue();

      expect(ok, isFalse);
      expect(events.last, isA<BillingError>());
      expect((events.last as BillingError).message,
          contains('not_a_care_pack'));
      expect(iap.lastNonConsumableProductId, isNull,
          reason: 'unknown care pack must NOT trigger a Play Billing '
              'purchase request');
    });

    test('PURCHASED on care pack → resolves skill ID via map and fires '
        'onCarePackOwned callback', () async {
      await initReady();

      iap.streamController.add([
        _purchaseDetails(
          ProductIds.carePackReactiveDog,
          PurchaseStatus.purchased,
          pendingComplete: true,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      // Skill ID resolved from ProductIds.carePackToSkillId.
      expect(carePackGrants, hasLength(1));
      expect(carePackGrants.first, 'reactive-dog');
      // BillingPurchased event fired.
      expect(events.whereType<BillingPurchased>(), hasLength(1));
      // completePurchase called.
      expect(iap.completedPurchases, hasLength(1));
      // No Pro state change — care pack ownership is orthogonal to
      // Pro tier.
      expect(optimisticUpdates, isEmpty);
    });

    test('RESTORED on care pack → same dispatch path (cross-device '
        'restore re-grants ownership)', () async {
      await initReady();

      iap.streamController.add([
        _purchaseDetails(
          ProductIds.carePackReactiveDog,
          PurchaseStatus.restored,
          pendingComplete: true,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(carePackGrants, hasLength(1));
      expect(events.whereType<BillingRestored>(), hasLength(1));
    });

    test('callback omitted on construction → care pack grant is silently '
        'skipped (no exception)', () async {
      final localIap = _FakeIap();
      final localService = BillingService(
        iap: localIap,
        onOptimisticEntitlement: (_) async {},
        // intentionally omit onCarePackOwned
      );
      final localEvents = <BillingEvent>[];
      final localSub = localService.events.listen(localEvents.add);
      localIap.available = true;
      localIap.productResponse = ProductDetailsResponse(
        productDetails: [
          _stubProduct(ProductIds.carePackReactiveDog, '\$2.99')
        ],
        notFoundIDs: const [],
      );
      await localService.initialize();
      await pumpEventQueue();

      localIap.streamController.add([
        _purchaseDetails(
          ProductIds.carePackReactiveDog,
          PurchaseStatus.purchased,
          pendingComplete: true,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(localEvents.whereType<BillingPurchased>(), hasLength(1));
      expect(localIap.completedPurchases, hasLength(1));
      await localSub.cancel();
      await localService.dispose();
    });
  });
}

ProductDetails _stubProduct(String id, String priceText) => ProductDetails(
      id: id,
      title: id,
      description: 'test product $id',
      price: priceText,
      rawPrice: 0.0,
      currencyCode: 'USD',
    );

PurchaseDetails _purchaseDetails(
  String productId,
  PurchaseStatus status, {
  bool pendingComplete = false,
  IAPError? error,
}) {
  return PurchaseDetails(
    productID: productId,
    purchaseID: 'fake-purchase-${DateTime.now().microsecondsSinceEpoch}',
    transactionDate: '${DateTime.now().millisecondsSinceEpoch}',
    verificationData: PurchaseVerificationData(
      localVerificationData: 'fake-local',
      serverVerificationData: 'fake-server',
      source: 'test',
    ),
    status: status,
  )
    ..pendingCompletePurchase = pendingComplete
    ..error = error;
}

class _FakeIap implements IapPlatform {
  bool available = true;
  ProductDetailsResponse productResponse = ProductDetailsResponse(
    productDetails: const [],
    notFoundIDs: const [],
  );
  int productQueryCount = 0;
  Set<String>? productQueryArg;
  String? lastNonConsumableProductId;
  String? lastConsumableProductId;
  final List<PurchaseDetails> completedPurchases = [];
  final List<String?> restoreCalls = [];

  final streamController =
      StreamController<List<PurchaseDetails>>.broadcast();

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    productQueryCount++;
    productQueryArg = identifiers;
    return productResponse;
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    lastNonConsumableProductId = purchaseParam.productDetails.id;
    return true;
  }

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    lastConsumableProductId = purchaseParam.productDetails.id;
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completedPurchases.add(purchase);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalls.add(applicationUserName);
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => streamController.stream;
}

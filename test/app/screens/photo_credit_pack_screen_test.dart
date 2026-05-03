import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/app/entitlement/entitlement_notifier.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/app/screens/photo_credit_pack_screen.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/platform/billing/iap_platform.dart';
import 'package:petpal/platform/billing/product_ids.dart';

/// Phase 7 task E.1 — photo credit pack screen.
///
/// Pro user → hero (VOICE.md §6 example 13 register) + buy CTA.
/// Free / BYOK user → "Photo analysis is part of Pro" redirect to
/// /paywall.
void main() {
  late _FakeIap iap;

  setUp(() => iap = _FakeIap());

  Widget wrap({required ProviderContainer Function() container}) {
    return UncontrolledProviderScope(
      container: container(),
      child: MaterialApp.router(
        theme: buildLightTheme(),
        routerConfig: GoRouter(
          initialLocation: '/paywall/credits',
          routes: [
            GoRoute(
              path: '/paywall',
              builder: (_, _) => const Scaffold(body: Text('paywall_root')),
              routes: [
                GoRoute(
                  path: 'credits',
                  builder: (_, _) => const PhotoCreditPackScreen(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ProviderContainer proContainer() => ProviderContainer(
        overrides: [
          iapPlatformProvider.overrideWithValue(iap),
          entitlementProvider.overrideWith(_ProEntitlementNotifier.new),
        ],
      );

  ProviderContainer freeContainer() => ProviderContainer(
        overrides: [
          iapPlatformProvider.overrideWithValue(iap),
        ],
      );

  testWidgets('Pro + product loaded → hero copy + price + Buy CTA',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    iap.available = true;
    iap.productResponse = ProductDetailsResponse(
      productDetails: [_stubProduct(ProductIds.photoCredits50, '\$2.99')],
      notFoundIDs: const [],
    );
    await tester.pumpWidget(wrap(container: proContainer));
    await tester.pumpAndSettle();

    // VOICE.md §6 example 13 hero copy.
    expect(find.text('Photo analysis: 30 a month on Pro'), findsOneWidget);
    expect(find.text('50 photo credits'), findsOneWidget);
    expect(find.text('\$2.99'), findsOneWidget);
    expect(find.text('Buy'), findsOneWidget);
    // Roll-over disclosure (VOICE.md §6 example 13 lock).
    expect(
      find.textContaining("don't expire"),
      findsOneWidget,
    );
  });

  testWidgets('Buy tap → iap.buyConsumable(photoCredits50)', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    iap.available = true;
    iap.productResponse = ProductDetailsResponse(
      productDetails: [_stubProduct(ProductIds.photoCredits50, '\$2.99')],
      notFoundIDs: const [],
    );
    await tester.pumpWidget(wrap(container: proContainer));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buy'));
    await tester.pump();
    expect(iap.lastConsumableProductId, ProductIds.photoCredits50);
  });

  testWidgets('Free user → "Photo analysis is part of Pro" + '
      '"See Pro options" redirect (vision is Pro-only per row 36)',
      (tester) async {
    iap.available = true;
    iap.productResponse = ProductDetailsResponse(
      productDetails: [_stubProduct(ProductIds.photoCredits50, '\$2.99')],
      notFoundIDs: const [],
    );
    await tester.pumpWidget(wrap(container: freeContainer));
    await tester.pumpAndSettle();

    expect(find.text('Photo analysis is part of Pro'), findsOneWidget);
    expect(find.text('See Pro options'), findsOneWidget);
    // Buy CTA must NOT be reachable on the free path.
    expect(find.text('Buy'), findsNothing);
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

class _FakeIap implements IapPlatform {
  bool available = true;
  ProductDetailsResponse productResponse = ProductDetailsResponse(
    productDetails: const [],
    notFoundIDs: const [],
  );
  String? lastConsumableProductId;
  final streamController =
      StreamController<List<PurchaseDetails>>.broadcast();

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async =>
      productResponse;

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async =>
      true;

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    lastConsumableProductId = purchaseParam.productDetails.id;
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {}

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => streamController.stream;
}

class _ProEntitlementNotifier extends EntitlementNotifier {
  @override
  Future<Entitlement> build() async => Entitlement(
        state: EntitlementState.proMonthly,
        userId: 'user-pro',
        counterPeriodStart: DateTime(2026, 5),
      );
}

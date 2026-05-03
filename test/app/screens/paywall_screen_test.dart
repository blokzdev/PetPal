import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/app/entitlement/entitlement_notifier.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/app/screens/paywall_screen.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/platform/billing/iap_platform.dart';
import 'package:petpal/platform/billing/product_ids.dart';

/// Phase 7 task E.1 — paywall screen integration tests.
///
/// Covers: hero copy + product cards render once products load;
/// "Subscribe yearly" / "Subscribe monthly" buttons invoke
/// buyNonConsumable with the right product IDs; "Restore purchases"
/// invokes restorePurchases; the BYOK escape note renders;
/// already-Pro users see the "You're on Pro" surface instead of
/// the upgrade pitch.
void main() {
  late _FakeIap iap;

  setUp(() {
    iap = _FakeIap();
  });

  Widget wrap({required Widget home}) {
    final router = GoRouter(
      initialLocation: '/paywall',
      routes: [
        GoRoute(path: '/paywall', builder: (_, _) => home),
      ],
    );
    return ProviderScope(
      overrides: [
        iapPlatformProvider.overrideWithValue(iap),
      ],
      child: MaterialApp.router(
        theme: buildLightTheme(),
        routerConfig: router,
      ),
    );
  }

  Future<void> pumpReady(WidgetTester tester) async {
    // Tall viewport so the paywall ListView renders all sections
    // (hero + plan cards + feature list + BYOK note + restore link)
    // in one frame; the default 800x600 cuts off the BYOK note +
    // restore link which the assertions need to reach.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    iap.available = true;
    iap.productResponse = ProductDetailsResponse(
      productDetails: [
        _stubProduct(ProductIds.proMonthly, '\$7.99'),
        _stubProduct(ProductIds.proAnnual, '\$59.00'),
      ],
      notFoundIDs: const [],
    );
    await tester.pumpWidget(wrap(home: const PaywallScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('renders hero + monthly + annual cards + Pro feature list '
      '(VOICE.md §6 example 14 register)', (tester) async {
    await pumpReady(tester);

    expect(find.text('PetPal Pro'), findsAtLeastNWidgets(1),
        reason: 'hero title');
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Annual'), findsOneWidget);
    expect(find.text('\$7.99'), findsOneWidget);
    expect(find.text('\$59.00'), findsOneWidget);
    expect(find.text('Best value'), findsOneWidget,
        reason: 'annual card carries the best-value badge');
    expect(find.text('Subscribe monthly'), findsOneWidget);
    expect(find.text('Subscribe yearly'), findsOneWidget);

    // Feature list — at least one VOICE.md §6 ex. 14 lock surfaces.
    expect(find.text('Unmetered chat'), findsOneWidget);
    expect(find.text('Sync across devices'), findsOneWidget);
    expect(find.text('Unlimited pets'), findsOneWidget);
    expect(find.text('Photo analysis'), findsOneWidget);

    // BYOK escape note (§6 ex. 14 "or, switch to your own Anthropic
    // API key in Settings").
    expect(find.text('Or bring your own Anthropic key'), findsOneWidget);

    // Restore link.
    expect(find.text('Restore purchases'), findsOneWidget);
  });

  testWidgets('Subscribe monthly tap → iap.buyNonConsumable(proMonthly)',
      (tester) async {
    await pumpReady(tester);

    await tester.tap(find.text('Subscribe monthly'));
    await tester.pump();
    expect(iap.lastNonConsumableProductId, ProductIds.proMonthly);
  });

  testWidgets('Subscribe yearly tap → iap.buyNonConsumable(proAnnual)',
      (tester) async {
    await pumpReady(tester);

    await tester.tap(find.text('Subscribe yearly'));
    await tester.pump();
    expect(iap.lastNonConsumableProductId, ProductIds.proAnnual);
  });

  testWidgets('Restore purchases tap → iap.restorePurchases', (tester) async {
    await pumpReady(tester);

    await tester.tap(find.text('Restore purchases'));
    await tester.pump();
    expect(iap.restoreCalls, hasLength(1));
  });

  testWidgets('Pro user lands on "You\'re on Pro" body, not the upgrade '
      'pitch (defensive — paywall not normally routed to for Pro)',
      (tester) async {
    iap.available = true;
    iap.productResponse = ProductDetailsResponse(
      productDetails: const [],
      notFoundIDs: const [],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          iapPlatformProvider.overrideWithValue(iap),
          // Override entitlement to Pro before the screen mounts.
          entitlementProvider.overrideWith(_FakeEntitlementNotifier.new),
        ],
        child: MaterialApp.router(
          theme: buildLightTheme(),
          routerConfig: GoRouter(
            initialLocation: '/paywall',
            routes: [
              GoRoute(
                path: '/paywall',
                builder: (_, _) => const PaywallScreen(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("You're on Pro."), findsOneWidget);
    expect(find.text('Subscribe monthly'), findsNothing);
    expect(find.text('Subscribe yearly'), findsNothing);
  });

  testWidgets('Billing unavailable → "Play Billing isn\'t available" '
      'empty state instead of crashing', (tester) async {
    iap.available = false;
    await tester.pumpWidget(wrap(home: const PaywallScreen()));
    await tester.pumpAndSettle();

    expect(find.text("Play Billing isn't available"), findsOneWidget);
    expect(find.text('Subscribe monthly'), findsNothing);
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
  String? lastNonConsumableProductId;
  String? lastConsumableProductId;
  final List<String?> restoreCalls = [];
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
  Future<void> completePurchase(PurchaseDetails purchase) async {}

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalls.add(applicationUserName);
  }

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => streamController.stream;
}

/// Stub that emits a Pro entitlement on build. Used by the
/// "Pro user → You're on Pro body" test.
class _FakeEntitlementNotifier extends EntitlementNotifier {
  @override
  Future<Entitlement> build() async {
    return Entitlement(
      state: EntitlementState.proMonthly,
      userId: 'user-pro',
      counterPeriodStart: DateTime(2026, 5),
    );
  }
}

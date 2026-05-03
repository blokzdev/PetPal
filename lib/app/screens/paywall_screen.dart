import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../platform/billing/billing_service.dart';
import '../../platform/billing/product_ids.dart';
import '../design/design.dart';
import '../entitlement/entitlement.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_button.dart';
import '../widgets/pet_card.dart';
import '../widgets/pet_section_header.dart';

/// Phase 7 task E.1 — Pro upgrade paywall.
///
/// Full-screen surface (lives outside the StatefulShellRoute) reached
/// from quota-hit dispatchers (`paywall_dispatcher.dart`) and from
/// the Settings "Upgrade to Pro" link (E.1.b). Hard-wall UX per
/// Stage 1 decision #5 — at chat msg 201 the chat error bar offers
/// "See Pro options" → here.
///
/// Copy register: VOICE.md §6 example 14 ("That's 200 messages this
/// month..."). §7 monetization principles enforced — additive
/// framing, Pro lifts the limit, BYOK escape mentioned at the
/// bottom (a non-paying ladder out per row 36).
///
/// Sage register only — coral is reserved for medical-attention
/// surfaces (DECISIONS row 64). The upgrade is a positive moment.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  StreamSubscription<BillingEvent>? _eventSub;
  String? _purchasingProductId; // null when no purchase in flight
  bool _restoring = false;
  Timer? _restoreTimeoutTimer;

  @override
  void dispose() {
    _eventSub?.cancel();
    _restoreTimeoutTimer?.cancel();
    super.dispose();
  }

  void _ensureSubscribed(BillingService service) {
    _eventSub ??= service.events.listen(_onBillingEvent);
  }

  void _onBillingEvent(BillingEvent event) {
    if (!mounted) return;
    switch (event) {
      case BillingPurchased():
      case BillingRestored():
        setState(() {
          _purchasingProductId = null;
          _restoring = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Welcome to Pro.')),
        );
        // Pop the paywall so user lands back where they were. The
        // entitlement notifier already saw the optimistic update via
        // BillingService → setOptimistic; the surface they came from
        // re-reads the new state.
        if (GoRouter.of(context).canPop()) {
          GoRouter.of(context).pop();
        }
      case BillingCanceled():
      case BillingError():
        setState(() {
          _purchasingProductId = null;
          _restoring = false;
        });
        if (event is BillingError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("That didn't go through: ${event.message}")),
          );
        }
      case BillingPending():
      case BillingReady():
      case BillingUnavailable():
        // Pending: Play handles the UI; we wait for purchased/error.
        // Ready: initialization completed (no UI feedback needed here).
        // Unavailable: surfaced as a static empty state below.
        break;
    }
  }

  Future<void> _buyPro({required bool annual}) async {
    final service = await ref.read(billingServiceProvider.future);
    _ensureSubscribed(service);
    setState(() {
      _purchasingProductId =
          annual ? ProductIds.proAnnual : ProductIds.proMonthly;
    });
    final ok = await service.buyPro(annual: annual);
    if (!ok && mounted) {
      // Plugin rejected the request before Play even saw it — error
      // event will arrive via the stream listener.
      setState(() => _purchasingProductId = null);
    }
  }

  Future<void> _restore() async {
    final service = await ref.read(billingServiceProvider.future);
    _ensureSubscribed(service);
    setState(() => _restoring = true);
    await service.restorePurchases();
    // Stream listener handles the success/error path. Time the
    // spinner out at 10s as a fallback; cancel on dispose so test
    // teardown doesn't see a pending Timer.
    _restoreTimeoutTimer?.cancel();
    _restoreTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _restoring) {
        setState(() => _restoring = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entitlement = ref.watch(entitlementProvider).maybeWhen(
          data: (e) => e,
          orElse: Entitlement.freeAnonymous,
        );

    // Already Pro? Surface a "you're on Pro" affordance instead of
    // the upgrade pitch (defensive — paywall shouldn't normally
    // route here for Pro users, but Settings "Manage subscription"
    // could in v1.x).
    if (entitlement.isPro) {
      return AppScaffold(
        title: 'PetPal Pro',
        body: _AlreadyProBody(entitlement: entitlement),
      );
    }

    final billingAsync = ref.watch(billingServiceProvider);
    return AppScaffold(
      title: 'PetPal Pro',
      body: billingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _PaywallErrorBody(message: '$e'),
        data: (service) {
          _ensureSubscribed(service);
          if (!service.isAvailable) {
            return const _BillingUnavailableBody();
          }
          final monthly = service.products[ProductIds.proMonthly];
          final annual = service.products[ProductIds.proAnnual];
          if (monthly == null && annual == null) {
            return const _ProductsNotLoadedBody();
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Spacing.m,
              Spacing.s,
              Spacing.m,
              Spacing.l,
            ),
            children: [
              const _PaywallHero(),
              const SizedBox(height: Spacing.l),
              const PetSectionHeader(title: 'Choose a plan'),
              if (annual != null)
                _PlanCard(
                  product: annual,
                  isAnnual: true,
                  isLoading: _purchasingProductId == ProductIds.proAnnual,
                  isOtherPurchasing: _purchasingProductId != null &&
                      _purchasingProductId != ProductIds.proAnnual,
                  onTap: () => _buyPro(annual: true),
                ),
              const SizedBox(height: Spacing.s),
              if (monthly != null)
                _PlanCard(
                  product: monthly,
                  isAnnual: false,
                  isLoading: _purchasingProductId == ProductIds.proMonthly,
                  isOtherPurchasing: _purchasingProductId != null &&
                      _purchasingProductId != ProductIds.proMonthly,
                  onTap: () => _buyPro(annual: false),
                ),
              const SizedBox(height: Spacing.l),
              const PetSectionHeader(title: 'What Pro adds'),
              const _ProFeatureList(),
              const SizedBox(height: Spacing.l),
              const _ByokEscapeCard(),
              const SizedBox(height: Spacing.m),
              Center(
                child: TextButton(
                  onPressed: _restoring ? null : _restore,
                  child: _restoring
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Restore purchases'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Hero serif title + warm sage gradient backdrop. VOICE.md §6
/// example 14 register — "Pro lifts the limit."
class _PaywallHero extends StatelessWidget {
  const _PaywallHero();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.m,
        vertical: Spacing.l,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.7),
            scheme.surface,
          ],
        ),
        borderRadius: Corners.m,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PetPal Pro',
            style: JournalText.weeklySummaryTitle(
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: Spacing.s),
          Text(
            'Lift every limit, sync across devices, and keep the '
            'memories flowing.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
                ),
          ),
        ],
      ),
    );
  }
}

/// One subscription product. Tap to start the purchase. Shows a
/// "Save \$XX/yr" badge on the annual card (computed from the two
/// product prices when both are loaded).
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.product,
    required this.isAnnual,
    required this.isLoading,
    required this.isOtherPurchasing,
    required this.onTap,
  });

  final ProductDetails product;
  final bool isAnnual;
  final bool isLoading;
  final bool isOtherPurchasing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return PetCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isAnnual ? 'Annual' : 'Monthly',
                      style: textTheme.titleMedium,
                    ),
                    if (isAnnual) ...[
                      const SizedBox(width: Spacing.s),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: Corners.s,
                        ),
                        child: Text(
                          'Best value',
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  product.price,
                  style: textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          PetButton(
            label: isAnnual ? 'Subscribe yearly' : 'Subscribe monthly',
            onPressed: isOtherPurchasing ? null : onTap,
            isLoading: isLoading,
            icon: PhosphorIconsRegular.sparkle,
          ),
        ],
      ),
    );
  }
}

/// Bullet list of what Pro adds. Locked from DECISIONS row 36 +
/// VOICE.md §6 example 14. Uses `sparkle` (Pro register), never
/// coral (medical register).
class _ProFeatureList extends StatelessWidget {
  const _ProFeatureList();

  static const _features = <(String, String)>[
    ('Unmetered chat', 'No 200-a-month cap.'),
    ('Sync across devices', 'Pick up where you left off on any phone.'),
    ('Unlimited pets', 'Add as many as live with you.'),
    ('Photo analysis', '30 a month, plus credit packs that roll over.'),
    ('Weekly summary', 'A recap entry every Sunday, written for you.'),
    ('Monthly health report', 'A longer arc once a month.'),
    ('Unlimited reminders', 'No 5-cap.'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in _features) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    PhosphorIconsRegular.sparkle,
                    size: 16,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: Spacing.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.$1, style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            )),
                        Text(
                          f.$2,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// VOICE.md §6 example 14 — the BYOK ladder out. "Or, switch to
/// your own Anthropic API key in Settings to keep chatting now."
/// Surfaced as a small note, NOT a competing CTA. The Pro buttons
/// stay primary; this is the privacy-maximalist escape valve for
/// users who don't want to pay PetPal but want to keep using the app.
class _ByokEscapeCard extends StatelessWidget {
  const _ByokEscapeCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return PetCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            PhosphorIconsRegular.key,
            color: scheme.onSurface.withValues(alpha: 0.65),
          ),
          const SizedBox(width: Spacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Or bring your own Anthropic key',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Switch BYOK on in Settings to chat without limits '
                  '— your messages go directly to Anthropic, and '
                  "PetPal's monthly cap doesn't apply.",
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlreadyProBody extends StatelessWidget {
  const _AlreadyProBody({required this.entitlement});
  final Entitlement entitlement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(Spacing.l),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIconsRegular.sparkle,
            size: 48,
            color: scheme.primary,
          ),
          const SizedBox(height: Spacing.m),
          Text("You're on Pro.", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Spacing.s),
          Text(
            entitlement.state == EntitlementState.proAnnual
                ? 'Annual plan.'
                : 'Monthly plan.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _BillingUnavailableBody extends StatelessWidget {
  const _BillingUnavailableBody();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.l),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIconsRegular.warningCircle,
            size: 48,
            color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: 0.5,
                ),
          ),
          const SizedBox(height: Spacing.m),
          Text(
            "Play Billing isn't available",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Spacing.s),
          Text(
            "PetPal can't reach Google Play right now. Make sure "
            "you're signed into a Google account on this device, "
            'then come back.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ProductsNotLoadedBody extends StatelessWidget {
  const _ProductsNotLoadedBody();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.l),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: Spacing.m),
          Text(
            'Loading plans from Google Play…',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _PaywallErrorBody extends StatelessWidget {
  const _PaywallErrorBody({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.l),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

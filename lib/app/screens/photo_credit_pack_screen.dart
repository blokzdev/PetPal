import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../platform/billing/billing_service.dart';
import '../../platform/billing/product_ids.dart';
import '../design/design.dart';
import '../entitlement/entitlement.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_button.dart';
import '../widgets/pet_card.dart';

/// Phase 7 task E.1 — focused photo-credit-pack purchase surface.
///
/// Reached from `dispatchPaywall(ctx, VisionQuotaExceeded(...))` per
/// E.1.b's vision-blocked dispatcher. Pro-only feature gate — only
/// Pro users can buy credit packs (free + BYOK have no vision
/// feature surface in v1; row 36).
///
/// Copy register: VOICE.md §6 example 13 verbatim — "Photo
/// analysis: 30 a month on Pro / You've used this month's
/// allowance. Top up with 50 more for $2.99..."
class PhotoCreditPackScreen extends ConsumerStatefulWidget {
  const PhotoCreditPackScreen({super.key});

  @override
  ConsumerState<PhotoCreditPackScreen> createState() =>
      _PhotoCreditPackScreenState();
}

class _PhotoCreditPackScreenState
    extends ConsumerState<PhotoCreditPackScreen> {
  StreamSubscription<BillingEvent>? _eventSub;
  bool _purchasing = false;

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  void _ensureSubscribed(BillingService service) {
    _eventSub ??= service.events.listen(_onBillingEvent);
  }

  void _onBillingEvent(BillingEvent event) {
    if (!mounted) return;
    if (event is BillingPurchased &&
        event.productId == ProductIds.photoCredits50) {
      setState(() => _purchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('50 photo credits added.')),
      );
      if (GoRouter.of(context).canPop()) {
        GoRouter.of(context).pop();
      }
    } else if (event is BillingError &&
        event.productId == ProductIds.photoCredits50) {
      setState(() => _purchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("That didn't go through: ${event.message}")),
      );
    } else if (event is BillingCanceled &&
        event.productId == ProductIds.photoCredits50) {
      setState(() => _purchasing = false);
    }
  }

  Future<void> _buy() async {
    final service = await ref.read(billingServiceProvider.future);
    _ensureSubscribed(service);
    setState(() => _purchasing = true);
    final ok = await service.buyPhotoCredits();
    if (!ok && mounted) {
      setState(() => _purchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entitlement = ref.watch(entitlementProvider).maybeWhen(
          data: (e) => e,
          orElse: Entitlement.freeAnonymous,
        );

    // Free + BYOK don't have vision in v1 (row 36 — vision is
    // Pro-only). If a free user reaches this screen somehow,
    // redirect them to the main paywall.
    if (!entitlement.isPro) {
      return AppScaffold(
        title: 'Photo credits',
        body: _ProRequiredBody(),
      );
    }

    final billingAsync = ref.watch(billingServiceProvider);
    return AppScaffold(
      title: 'Photo credits',
      body: billingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(Spacing.l),
          child: Center(child: Text('$e')),
        ),
        data: (service) {
          _ensureSubscribed(service);
          if (!service.isAvailable) {
            return const _BillingUnavailableBody();
          }
          final product = service.products[ProductIds.photoCredits50];
          if (product == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Spacing.m,
              Spacing.s,
              Spacing.m,
              Spacing.l,
            ),
            children: [
              _PhotoCreditHero(entitlement: entitlement),
              const SizedBox(height: Spacing.l),
              PetCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '50 photo credits',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                product.price,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        PetButton(
                          label: 'Buy',
                          onPressed: _buy,
                          isLoading: _purchasing,
                          icon: PhosphorIconsRegular.sparkle,
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.s),
                    Text(
                      "They don't expire — unused credits roll over to "
                      'next month.',
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.65),
                              ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.m),
              Center(
                child: TextButton(
                  onPressed: () => GoRouter.of(context).pop(),
                  child: const Text('Maybe later'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// VOICE.md §6 example 13 hero — "Photo analysis: 30 a month on
/// Pro." Sage register; current usage stat surfaced as ambient
/// information, not metering language.
class _PhotoCreditHero extends StatelessWidget {
  const _PhotoCreditHero({required this.entitlement});
  final Entitlement entitlement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
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
            'Photo analysis: 30 a month on Pro',
            style: JournalText.entryTitle(
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: Spacing.s),
          Text(
            "You've used this month's allowance. Top up with 50 more "
            'so PetPal can keep describing what it sees.',
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
            ),
          ),
          if (entitlement.photoCreditsBalance > 0) ...[
            const SizedBox(height: Spacing.s),
            Text(
              'Current balance: ${entitlement.photoCreditsBalance}',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProRequiredBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.l),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIconsRegular.sparkle,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: Spacing.m),
          Text(
            'Photo analysis is part of Pro',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Spacing.s),
          Text(
            'Upgrade to Pro to start, then top up with credit packs '
            'whenever you need extras.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Spacing.l),
          PetButton(
            label: 'See Pro options',
            onPressed: () => GoRouter.of(context).pushReplacement('/paywall'),
            icon: PhosphorIconsRegular.sparkle,
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
        ],
      ),
    );
  }
}

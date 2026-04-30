import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/pet_name.dart';
import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pets = ref.watch(petsProvider);

    // Resolve the per-state body + optional hero. Always feed a single
    // AppScaffold.hero so the AnimatedSwitcher in the body keeps the
    // empty→named-pet cross-fade (added in 5.8). The hero collapses
    // to height 0 when there's no pet so the empty state still owns
    // the full surface; once a pet exists, the 120dp hero zone fades
    // in above the body.
    Widget? hero;
    Widget body = const SizedBox.shrink();
    pets.when(
      data: (list) {
        final keyValue = list.isEmpty ? 'empty' : 'pet-${list.last.id}';
        final child = list.isEmpty
            ? const _EmptyState()
            : _GreetingBody(pet: list.last);
        body = Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AnimatedSwitcher(
              duration: Motion.short,
              switchInCurve: Motion.standardCurve,
              switchOutCurve: Motion.standardCurve,
              child: KeyedSubtree(
                key: ValueKey(keyValue),
                child: child,
              ),
            ),
          ),
        );
        if (list.isNotEmpty) {
          hero = _PetGreetingHero(
            key: ValueKey('hero-${list.last.id}'),
            // Bug-2 defense: route the raw name through
            // displayPetName so an empty/whitespace name renders
            // as "Your pet" rather than a blank gradient.
            petName: displayPetName(list.last.name),
          );
        }
      },
      loading: () =>
          body = const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          body = Center(child: Text('Could not read pets: $e')),
    );

    if (hero == null) {
      return AppScaffold(
        title: 'PetPal',
        body: body,
      );
    }
    return AppScaffold.hero(
      title: 'PetPal',
      heroBuilder: (_) => hero!,
      body: body,
    );
  }
}

/// Per-pet home greeting hero — task 5.10 (user-locked: centered name
/// on a warm gradient sweep + copy = name only). Phase 6 will overlay
/// the pet's photo as a low-opacity backdrop behind the name; nothing
/// in this composition needs to be removed for that addition. The
/// FittedBox + scaleDown lets long names ("Mr. Whiskers", "Princess
/// Buttercup") shrink to fit the 120dp hero zone without overflowing.
///
/// The gradient runs primaryContainer (top, ~60% alpha) → surface
/// (bottom). Soft, sky-like, leaves the AppBar reading clean.
class _PetGreetingHero extends StatelessWidget {
  const _PetGreetingHero({super.key, required this.petName});
  final String petName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.6),
            scheme.surface,
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.l),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              petName,
              textAlign: TextAlign.center,
              style: text.displaySmall?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(PhosphorIconsRegular.pawPrint, size: 72, color: scheme.primary),
        const SizedBox(height: 16),
        Text('PetPal', style: text.headlineMedium),
        const SizedBox(height: 8),
        Text(
          "PetPal remembers your pet's life so you don't have to.",
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: () => GoRouter.of(context).push('/pets/add'),
          icon: const Icon(PhosphorIconsRegular.plus),
          label: const Text('Add your pet'),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => GoRouter.of(context).push('/dev'),
            icon: const Icon(PhosphorIconsRegular.flask),
            label: const Text('Dev tools'),
          ),
        ],
      ],
    );
  }
}

class _GreetingBody extends ConsumerWidget {
  const _GreetingBody({required this.pet});
  final dynamic pet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    // Bug-2 defense: route the raw name through displayPetName so
    // an empty/whitespace name renders as "Your pet" rather than
    // emitting orphan apostrophes ("PetPal remembers 's life...")
    // or trailing-space CTAs ("Chat with ").
    final name = displayPetName(pet.name as String?);
    // Free tier (DECISIONS row 8) — chat with the most recently-created pet.
    return SingleChildScrollView(
      child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Pet name + the previous Icons.pets header have moved into
        // the AppScaffold.hero zone above (task 5.10). The body opens
        // directly with the tagline so the name doesn't repeat.
        Text(
          "PetPal remembers $name's life so you don't have to.",
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: Spacing.xl),
        // Primary CTA — stays prominent above the destinations grid
        // (5.12 user-locked intent: 'Chat with Loki' is the most-used
        // home action and must remain above-the-fold).
        FilledButton.icon(
          onPressed: () => GoRouter.of(context).push('/chat'),
          icon: const Icon(PhosphorIconsRegular.chatCircle),
          label: Text('Chat with $name'),
        ),
        const SizedBox(height: Spacing.l),
        // Destinations grid — task 5.12 (user-locked: 2-column card
        // grid below the CTA). Five tiles fill 2×3 with the last row
        // half-empty; debug-only dev screen drops a sixth tile to
        // square the grid in dev builds, but never in release.
        const _DestinationsGrid(),
      ],
      ),
    );
  }
}

/// 2-column responsive card grid of nav destinations. Each tile is
/// a [PetCardButton] (icon + label) routing through go_router. Layout
/// uses GridView.count (not Wrap) so tiles size equally and tap
/// targets stay predictable. The grid is shrink-wrapped + non-
/// scrollable because the body already lives inside a
/// SingleChildScrollView; nesting two scrollables here would steal
/// flings from the outer scroll.
class _DestinationsGrid extends StatelessWidget {
  const _DestinationsGrid();

  static const _items = <_Destination>[
    _Destination(
      label: 'Journal',
      icon: PhosphorIconsRegular.bookOpen,
      route: '/wiki',
    ),
    _Destination(
      label: 'Profile',
      icon: PhosphorIconsRegular.userCircle,
      route: '/soul',
    ),
    _Destination(
      label: 'Reminders',
      icon: PhosphorIconsRegular.bell,
      route: '/reminders',
    ),
    _Destination(
      label: 'Care guides',
      icon: PhosphorIconsRegular.puzzlePiece,
      route: '/skills',
    ),
    _Destination(
      label: 'Settings',
      icon: PhosphorIconsRegular.gear,
      route: '/settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final items = [
      ..._items,
      if (kDebugMode)
        const _Destination(
          label: 'Dev',
          icon: PhosphorIconsRegular.flask,
          route: '/dev',
        ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Spacing.s,
      crossAxisSpacing: Spacing.s,
      childAspectRatio: 1.4,
      children: [
        for (final dest in items)
          PetCardButton(
            onPressed: () => GoRouter.of(context).push(dest.route),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(dest.icon, size: 28),
                  const SizedBox(height: Spacing.s),
                  Text(
                    dest.label,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.route,
  });
  final String label;
  final IconData icon;
  final String route;
}

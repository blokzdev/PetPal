import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';

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
            petName: list.last.name,
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
        Icon(Icons.pets, size: 72, color: scheme.primary),
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
          icon: const Icon(Icons.add),
          label: const Text('Add your pet'),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => GoRouter.of(context).push('/dev'),
            icon: const Icon(Icons.science_outlined),
            label: const Text('Open harness · dev screen'),
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
    // Free tier (DECISIONS row 8) — chat with the most recently-created pet.
    return SingleChildScrollView(
      child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Pet name + the previous Icons.pets header have moved into
        // the AppScaffold.hero zone above (task 5.10). The body opens
        // directly with the tagline so the name doesn't repeat.
        Text(
          "PetPal remembers ${pet.name}'s life so you don't have to.",
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: () => GoRouter.of(context).push('/chat'),
          icon: const Icon(Icons.chat_bubble),
          label: Text('Chat with ${pet.name}'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => GoRouter.of(context).push('/wiki'),
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('Open journal'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => GoRouter.of(context).push('/soul'),
          icon: const Icon(Icons.person_outline),
          label: const Text('Edit profile'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => GoRouter.of(context).push('/reminders'),
          icon: const Icon(Icons.alarm_outlined),
          label: const Text('Reminders'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => GoRouter.of(context).push('/skills'),
          icon: const Icon(Icons.extension_outlined),
          label: const Text('Care guides'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => GoRouter.of(context).push('/settings'),
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Settings'),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => GoRouter.of(context).push('/dev'),
            icon: const Icon(Icons.science_outlined),
            label: const Text('Open harness · dev screen'),
          ),
        ],
      ],
      ),
    );
  }
}

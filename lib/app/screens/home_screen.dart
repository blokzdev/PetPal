import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/db/database.dart';
import '../../data/pet_name.dart';
import '../../data/repos/reminder_repo.dart';
import '../../harness/observation/affective_observation.dart';
import '../../harness/scheduling/reminder_kinds.dart';
import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/editorial_card.dart';
import '../widgets/pet_card.dart';
import '../widgets/pet_section_header.dart';

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
              duration: Motion.medium,
              switchInCurve: Motion.springCurve,
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
            petId: list.last.id,
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
///
/// Phase 6 task 6.2 — when the pet has a profile photo, it lands as
/// a low-opacity backdrop (~25%) behind the gradient sweep so the
/// displaySmall name stays legible. The image fills the hero zone
/// (`BoxFit.cover`) and the gradient overlay desaturates / softens
/// any photo so warm-cream / warm-graphite surface tones still win.
class _PetGreetingHero extends ConsumerWidget {
  const _PetGreetingHero({
    super.key,
    required this.petId,
    required this.petName,
  });
  final int petId;
  final String petName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final photoAsync = ref.watch(profilePhotoBytesProvider(petId));
    final photoBytes = photoAsync.maybeWhen(
      data: (bytes) => bytes,
      orElse: () => null,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (photoBytes != null)
          Opacity(
            opacity: 0.25,
            child: Image.memory(
              photoBytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              // Stale / corrupt profile photo bytes shouldn't break
              // the hero zone — fall through to gradient-only.
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        DecoratedBox(
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
        ),
      ],
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
    final observation = ref.watch(recentAffectiveObservationProvider);
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
        // Phase 6 task 6.8 — affective observation card. Surfaces
        // when a just-saved photo memory's pipeline returned a
        // grounded high-confidence observation. Sits below the
        // tagline, above the chat CTA — visible on land but doesn't
        // displace the primary action. Dismissible; cleared by the
        // notifier so re-navigating to home doesn't resurface it.
        if (observation != null) ...[
          const SizedBox(height: Spacing.l),
          _AffectiveObservationCard(observation: observation),
        ],
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
        // Phase 6.6 task 6.6.B.3 — Recent memories section. Top 3
        // entries from wikiEntriesProvider rendered as EditorialCards;
        // tapping a card routes to /wiki/entry. Auto-hides when the
        // pet has no entries yet so the home surface stays calm.
        const _RecentMemoriesSection(),
        // Phase 6.6 task 6.6.A.3 — Reminders inline section per
        // DECISIONS row 61. Replaces the home grid's "Reminders"
        // tile; tapping the header routes to the Home-branch nested
        // sub-page at `/home/reminders`. Section auto-hides when
        // there are no upcoming reminders so the home surface stays
        // calm. Group C.1 layers Quick Capture tiles + This Week
        // card around it.
        _RemindersSection(petId: pet.id as int),
        // Phase 6.6 — Debug-only Dev affordance for the verification
        // screen. The home grid that used to host this is gone; the
        // empty-state already exposes /dev for unonboarded states,
        // and named-pet states can reach it via deep link in debug
        // builds. A small inline button keeps it accessible without
        // re-introducing grid chrome.
        if (kDebugMode) ...[
          const SizedBox(height: Spacing.l),
          OutlinedButton.icon(
            onPressed: () => GoRouter.of(context).push('/dev'),
            icon: const Icon(PhosphorIconsRegular.flask),
            label: const Text('Dev tools'),
          ),
        ],
      ],
      ),
    );
  }
}

/// Phase 6.6 task 6.6.B.3 — Recent memories section on Home.
///
/// Top 3 entries from `wikiEntriesProvider` (newest first;
/// `wikiEntriesProvider` already orders desc by `ts`). Each entry
/// renders as an `EditorialCard` (B.1 primitive) — kicker + serif
/// title; tapping routes to `/wiki/entry`. Auto-hides when the pet
/// has no entries yet (calm empty surface, no explainer).
///
/// Section header is `PetSectionHeader` (B.0 small-caps + sage tint).
/// Layout:
///
///   RECENT MEMORIES
///   ┌─────────────────────────────────────────┐
///   │ FOOD · APR 25                           │
///   │ Carrot trial                            │
///   └─────────────────────────────────────────┘
///   ┌─────────────────────────────────────────┐
///   │ VET VISITS · APR 22                     │
///   │ Annual checkup                          │
///   └─────────────────────────────────────────┘
///   ...
///
/// Group C.1 will refine the home redesign around this section
/// (Quick Capture tiles + This Week card); B.3 lands the section in
/// its current shape.
class _RecentMemoriesSection extends ConsumerWidget {
  const _RecentMemoriesSection();

  static const _monthAbbrev = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  static String _kickerFor(Entry e) {
    final type = _humanTypeLabelHome(e.type).toUpperCase();
    final month = _monthAbbrev[e.ts.month - 1];
    return '$type · $month ${e.ts.day}';
  }

  /// Compact type-label translation for the home recent memories
  /// kicker. Mirrors `_humanTypeLabel` in the journal browser; copied
  /// inline rather than imported because the journal browser's
  /// helper is `private` to that file. If a third callsite arrives,
  /// promote to `lib/data/entry_labels.dart`.
  static String _humanTypeLabelHome(String type) {
    switch (type) {
      case 'digest':
        return 'Weekly summary';
      case 'vet':
        return 'Vet visits';
      case 'food':
        return 'Food';
      case 'weight':
        return 'Weight';
      case 'behavior':
        return 'Behavior';
      case 'photos':
        return 'Photo';
      default:
        return type.isEmpty
            ? type
            : '${type[0].toUpperCase()}${type.substring(1)}';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(wikiEntriesProvider);
    return entriesAsync.maybeWhen(
      data: (entries) {
        if (entries.isEmpty) return const SizedBox.shrink();
        final top3 = entries.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PetSectionHeader(title: 'Recent memories'),
            for (final e in top3)
              EditorialCard(
                kicker: _kickerFor(e),
                title: e.title,
                onTap: () => GoRouter.of(context).push(
                  '/wiki/entry',
                  extra: e.path,
                ),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// Phase 6.6 task 6.6.A.3 — Reminders inline section on Home.
///
/// Surfaces the next 3 upcoming reminders via the
/// `remindersForPetProvider` (chronological, soonest-first; only
/// reminders whose `whenTs` is in the future). The section header
/// is tap-targeted and routes to `/home/reminders` (Home branch
/// nested sub-page) so the user can see all reminders without
/// switching tabs (DECISIONS row 61).
///
/// **Group B.0 will refresh the section header** (small caps + sage
/// tint per DECISIONS row 58); A.3's transitional treatment uses an
/// existing `PetSectionHeader` wrapped in InkWell. **Group C.1 will
/// layer Quick Capture tiles + This Week card around this section**
/// — A.3 lands the IA-level change (section exists), Group C lands
/// the visual brief.
///
/// When the pet has no upcoming reminders the section renders
/// nothing (`SizedBox.shrink()`) — a calm empty surface beats an
/// empty-state explainer for a section that's secondary to the
/// chat CTA.
class _RemindersSection extends ConsumerWidget {
  const _RemindersSection({required this.petId});

  final int petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(remindersForPetProvider(petId));
    return remindersAsync.maybeWhen(
      data: (reminders) {
        final now = DateTime.now();
        final upcoming = reminders
            .where((r) => r.whenTs.isAfter(now))
            .toList()
          ..sort((a, b) => a.whenTs.compareTo(b.whenTs));
        if (upcoming.isEmpty) return const SizedBox.shrink();
        final top3 = upcoming.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: Corners.s,
              onTap: () => GoRouter.of(context).push('/home/reminders'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.m,
                  vertical: Spacing.s,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Reminders',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.65),
                              letterSpacing: 0.6,
                            ),
                      ),
                    ),
                    Icon(
                      PhosphorIconsRegular.caretRight,
                      size: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),
            for (final r in top3) _ReminderRow(reminder: r),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.reminder});

  final ReminderRow reminder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = ReminderKind.fromId(reminder.kind);
    final label = kind?.label ?? 'Reminder';
    return PetCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          _iconForKind(kind),
          color: scheme.onSurface.withValues(alpha: 0.8),
        ),
        title: Text(label),
        subtitle: Text(_formatDate(reminder.whenTs)),
      ),
    );
  }

  IconData _iconForKind(ReminderKind? kind) {
    switch (kind) {
      case ReminderKind.fleaTreatment:
        return PhosphorIconsRegular.bug;
      case ReminderKind.heartwormDose:
        return PhosphorIconsRegular.pill;
      case ReminderKind.vaccineDue:
        return PhosphorIconsRegular.syringe;
      case ReminderKind.weightCheck:
        return PhosphorIconsRegular.scales;
      case ReminderKind.vetFollowUp:
        return PhosphorIconsRegular.firstAidKit;
      case null:
        return PhosphorIconsRegular.bell;
    }
  }

  String _formatDate(DateTime ts) {
    return '${ts.year.toString().padLeft(4, '0')}-'
        '${ts.month.toString().padLeft(2, '0')}-'
        '${ts.day.toString().padLeft(2, '0')}';
  }
}

/// Phase 6 task 6.8 — surfaces a single warm grounded observation
/// after a photo save. Soft sage-tinted card; a leaf icon (Phosphor
/// regular, the journal-aesthetic register); the observation text in
/// body-medium; a small "from {grounding_ref}" footer; close button
/// dismisses via `recentAffectiveObservationProvider.notifier`.
///
/// VOICE.md §2 register applies — the card never claims emotion as
/// fact; the observer's prompt does the hedging, the card just
/// renders what arrives.
class _AffectiveObservationCard extends ConsumerWidget {
  const _AffectiveObservationCard({required this.observation});
  final AffectiveObservation observation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return PetCard(
      padding: const EdgeInsets.fromLTRB(
        Spacing.m,
        Spacing.m,
        Spacing.s,
        Spacing.m,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              PhosphorIconsRegular.leaf,
              size: 18,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: Spacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  observation.text,
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'from ${observation.groundingRef}',
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: Icon(
              PhosphorIconsRegular.x,
              size: 16,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
            onPressed: () => ref
                .read(recentAffectiveObservationProvider.notifier)
                .dismiss(),
          ),
        ],
      ),
    );
  }
}

// Phase 6.6 task 6.6.A.3 — `_DestinationsGrid` + `_Destination`
// removed. The 6 home tiles repurposed per DECISIONS row 59's
// orphan map: Journal / Profile / Settings → bottom-nav tabs;
// Reminders → inline section above (`_RemindersSection`); Add
// photo → Quick Capture (Group C.1); Care guides → Profile
// sub-page at /soul/guides (Group C.4 lands the GUIDES & SKILLS
// section). Settings reaches its existing `/settings` route via
// the Hub tab's ListTile.

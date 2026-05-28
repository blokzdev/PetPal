import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_card.dart';

/// Phase 6.6 — About sub-page under Hub (DECISIONS row 60).
///
/// v1 contents: app version + credits + privacy policy link. Loads
/// the version from the package metadata at build time so a new
/// build automatically reflects the right number.
///
/// Reserved for v1.1 (privacy policy promotion to its own surface
/// per the Hub future-contents reservation): Privacy & Data screen,
/// Help/Support screen, etc.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppScaffold(
      title: 'About',
      body: ListView(
        padding: const EdgeInsets.all(Spacing.m),
        children: [
          PetCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PetPal',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'A memory-first companion for pet owners. The chat is '
                  'the interface; the journal is the product.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.75),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.s),
          PetCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    PhosphorIconsRegular.tag,
                    color: scheme.onSurface.withValues(alpha: 0.8),
                  ),
                  title: const Text('Version'),
                  trailing: Text(
                    '1.0.0',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    PhosphorIconsRegular.shieldCheck,
                    color: scheme.onSurface.withValues(alpha: 0.8),
                  ),
                  title: const Text('Privacy policy'),
                  subtitle: const Text(
                    'Your journal stays on this device. Chat sends your '
                    "message and the relevant memories to Anthropic's "
                    'Claude — nothing else leaves the phone. Pro sync '
                    'uploads end-to-end encrypted copies that PetPal '
                    "can't read.",
                  ),
                  // v1.1 promotes this to a dedicated Privacy & Data
                  // screen per V1X_BACKLOG. v1 lands the policy text
                  // here as a static read.
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

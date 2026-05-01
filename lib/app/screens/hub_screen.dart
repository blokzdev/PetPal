import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_card.dart';

/// Phase 6.6 — Hub destination (4th bottom-nav tab, DECISIONS row 60).
///
/// Hub absorbs Settings + Export + About in v1; reserved future
/// contents (Privacy & Data, Help/Support, in-app Notifications,
/// Account/Subscription/Sync status) land in v1.1 / Phase 7
/// per V1X_BACKLOG.
///
/// **A.1 stub.** This screen lands as a navigable destination so the
/// `StatefulShellRoute` Hub branch resolves; the v1 contents
/// (Settings ListTile, Export action, About link) land in task
/// 6.6.A.3 when route migration finalises.
class HubScreen extends ConsumerWidget {
  const HubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return AppScaffold(
      title: 'Hub',
      body: ListView(
        padding: const EdgeInsets.all(Spacing.m),
        children: [
          PetCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    PhosphorIconsRegular.gear,
                    color: scheme.onSurface.withValues(alpha: 0.8),
                  ),
                  title: const Text('Settings'),
                  trailing: Icon(
                    PhosphorIconsRegular.caretRight,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                  onTap: () => GoRouter.of(context).push('/settings'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    PhosphorIconsRegular.shareNetwork,
                    color: scheme.onSurface.withValues(alpha: 0.8),
                  ),
                  title: const Text('Export'),
                  subtitle: const Text(
                    'Download a zip of your journal.',
                  ),
                  trailing: Icon(
                    PhosphorIconsRegular.caretRight,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                  // Wired in 6.6.A.3 when journal-browser export
                  // action moves here.
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    PhosphorIconsRegular.info,
                    color: scheme.onSurface.withValues(alpha: 0.8),
                  ),
                  title: const Text('About'),
                  trailing: Icon(
                    PhosphorIconsRegular.caretRight,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                  onTap: () => GoRouter.of(context).push('/about'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

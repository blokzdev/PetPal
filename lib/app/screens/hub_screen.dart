import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/wiki_export.dart';
import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_card.dart';

/// Phase 6.6 — Hub destination (4th bottom-nav tab, DECISIONS row 60).
///
/// Hub absorbs Settings + Export + About in v1. Reserved future
/// contents (Privacy & Data, Help/Support, in-app Notifications,
/// Account/Subscription/Sync status) land in v1.1 / Phase 7 per
/// V1X_BACKLOG.
///
/// The Export action lives on this screen (DECISIONS row 60 — moved
/// from the journal-browser AppBar so the IA stays single-rooted).
/// ConsumerStatefulWidget so the in-flight export can swap the
/// trailing icon for a spinner without blocking the rest of the Hub.
class HubScreen extends ConsumerStatefulWidget {
  const HubScreen({super.key});

  @override
  ConsumerState<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends ConsumerState<HubScreen> {
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final wiki = await ref.read(wikiIoProvider.future);
      final activePetId = ref.read(activePetIdProvider);
      final tempDir = await getTemporaryDirectory();
      final zip = await exportPetWikiAsZip(
        wiki: wiki,
        petId: activePetId(),
        outputDir: tempDir,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zip.path, mimeType: 'application/zip')],
          subject: 'PetPal journal export',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      appSnackBar(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  trailing: _exporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          PhosphorIconsRegular.caretRight,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                  onTap: _exporting ? null : _export,
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

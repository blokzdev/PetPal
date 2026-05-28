import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/wiki_export.dart';
import '../account/account_deletion_client.dart';
import '../account/local_data_wipe.dart';
import '../auth/auth_session_notifier.dart';
import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_card.dart';

/// Phase 7 task H.1.d — account deletion cascade.
///
/// Single-screen disclosure with typed-confirmation gate per
/// DECISIONS row 77 Option (e) and VOICE.md §6 example 20.
/// Friction-as-discipline lives in the typed gate at the end, NOT
/// in stretching the cascade across five screens.
///
/// Five disclosure points (in user-worry order):
///   1. Local data on this device deleted
///   2. Synced server data deleted within 30 days (undo via
///      sign-in during window)
///   3. Active subscriptions stay on Google Play (manual cancel)
///   4. Sync passphrase removed (cannot be recovered)
///   5. PetPal's records of AI chat usage deleted
///
/// Plus an inline export-first affordance — never a forced step.
///
/// The local-data-wipe portion of step 1 is staged: this commit
/// signs the user out + calls the Edge Function (server-side
/// cascade). A follow-up commit lands the local Drift + wiki-files
/// wipe so the device is genuinely empty post-delete. Until then,
/// the user is signed out and their cloud data is scheduled for
/// hard-purge — local data persists but is inaccessible to the
/// signed-out app surface (no longer attributed to a user).
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirmController = TextEditingController();
  bool _exporting = false;
  bool _deleting = false;
  String? _errorMessage;
  DateTime? _retentionEnd;

  static const _confirmPhrase = 'DELETE';

  @override
  void initState() {
    super.initState();
    _confirmController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  bool get _canConfirm =>
      _confirmController.text.trim() == _confirmPhrase && !_deleting;

  Future<void> _exportFirst() async {
    setState(() {
      _exporting = true;
      _errorMessage = null;
    });
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
          subject: 'PetPal journal export (before deletion)',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Could not export your journal. Try again or skip the '
            'export and delete anyway.';
      });
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _confirmDelete() async {
    setState(() {
      _deleting = true;
      _errorMessage = null;
    });
    try {
      final client = ref.read(accountDeletionClientProvider);
      if (client == null) {
        throw const AccountDeletionException(
          'PetPal cannot reach the server in this build. Try again '
          'from the official Play Store install.',
        );
      }
      final retentionEnd = await client.requestDeletion();

      // Phase 7 task H.1.d.wipe — server cascade succeeded; nuke
      // the local Drift DB + wiki files before signing out so the
      // device truly contains no trace of the deleted account.
      // Wipe failures are logged but never re-thrown — the
      // server-side deletion is the load-bearing step; surfacing a
      // local failure would tell the user "your account is deleted
      // but your device is in a half-broken state," which is not
      // actionable. (Per LocalDataWipe contract — DECISIONS row 90.)
      try {
        final wikiIo = await ref.read(wikiIoProvider.future);
        await ref.read(localDataWipeProvider).wipe(
              wikiIo: wikiIo,
              invalidateDatabase: () =>
                  ref.invalidate(appDatabaseProvider),
              invalidateWikiIo: () => ref.invalidate(wikiIoProvider),
            );
      } catch (_) {
        // Defensive — wipe() catches its own errors via onError.
      }

      // Server cascade succeeded — sign out locally so the JWT is
      // cleared from this device's secure storage and the auth
      // notifier flips to signed-out. Subsequent Settings reads
      // re-render in the signed-out register.
      try {
        await ref.read(authSessionProvider.notifier).signOut();
      } catch (_) {
        // Even if the local sign-out call fails, the server has
        // already invalidated the session. Don't surface this as
        // an error — the deletion succeeded.
      }

      if (!mounted) return;
      setState(() {
        _retentionEnd = retentionEnd;
      });
    } on AccountDeletionException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Could not delete your account. Check your connection '
            'and try again.';
      });
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Delete account',
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.m),
          child: _retentionEnd != null
              ? _buildSuccess(context, _retentionEnd!)
              : _buildForm(context),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Spacing.s),
        Text(
          'Delete your PetPal account',
          style: textTheme.headlineSmall?.copyWith(
            fontVariations: [const FontVariation('wght', 600)],
          ),
        ),
        const SizedBox(height: Spacing.s),
        Text(
          'This permanently removes your account from PetPal. '
          "Here's what happens:",
          style: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.85),
            height: 1.45,
          ),
        ),
        const SizedBox(height: Spacing.m),
        const _Disclosure(),
        const SizedBox(height: Spacing.m),
        // Inline export affordance — never a forced step.
        PetCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    PhosphorIconsRegular.shareNetwork,
                    size: 18,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: Spacing.s),
                  Expanded(
                    child: Text(
                      'Want to keep a copy of your journal first?',
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.85),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.s),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _exporting ? null : _exportFirst,
                  icon: _exporting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          PhosphorIconsRegular.downloadSimple,
                          size: 16,
                        ),
                  label: const Text('Export to ZIP'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.l),
        Text(
          'Type DELETE below to confirm.',
          style: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.85),
            fontVariations: [const FontVariation('wght', 500)],
          ),
        ),
        const SizedBox(height: Spacing.s),
        TextField(
          controller: _confirmController,
          enabled: !_deleting,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            // Force the user to type the literal phrase. Lowercase
            // input wouldn't match _confirmPhrase, but normalizing
            // here gives a smoother feel when the user has caps-lock
            // off.
            UpperCaseTextFormatter(),
          ],
          decoration: const InputDecoration(
            labelText: 'Type DELETE',
            prefixIcon: Icon(PhosphorIconsRegular.warning),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: Spacing.s),
          _ErrorBanner(message: _errorMessage!),
        ],
        const SizedBox(height: Spacing.m),
        FilledButton.icon(
          onPressed: _canConfirm ? _confirmDelete : null,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          icon: _deleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(PhosphorIconsRegular.trash, size: 16),
          label: const Text('Delete account'),
        ),
        const SizedBox(height: Spacing.s),
        Center(
          child: TextButton(
            onPressed: _deleting
                ? null
                : () => Navigator.of(context).maybePop(),
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess(BuildContext context, DateTime retentionEnd) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dateFmt = _formatDate(retentionEnd);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Spacing.l),
        Center(
          child: Icon(
            PhosphorIconsRegular.checkCircle,
            size: 56,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: Spacing.m),
        Text(
          'Your account is scheduled for deletion',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(
            fontVariations: [const FontVariation('wght', 600)],
          ),
        ),
        const SizedBox(height: Spacing.s),
        Text(
          "PetPal's servers will fully erase your data on $dateFmt. "
          'Until then, signing back in restores your account.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.75),
            height: 1.45,
          ),
        ),
        const SizedBox(height: Spacing.l),
        FilledButton(
          onPressed: () => GoRouter.of(context).go('/'),
          child: const Text('Back to PetPal'),
        ),
      ],
    );
  }

  static String _formatDate(DateTime t) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final local = t.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }
}

class _Disclosure extends StatelessWidget {
  const _Disclosure();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const items = [
      'Your journal on this device is signed out',
      "Your synced copy on PetPal's servers is deleted within 30 days "
          '— sign in within that window to undo',
      'Active subscriptions stay on your Google Play account; cancel '
          'them in Play Store before deleting if you want a refund',
      'Your sync passphrase is removed and cannot be recovered',
      "PetPal's records of your AI chat usage are deleted",
    ];

    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.s),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.s),
                  Expanded(
                    child: Text(
                      item,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.85),
                        height: 1.45,
                      ),
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

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Spacing.s),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: Corners.s,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            PhosphorIconsRegular.warning,
            size: 18,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: Spacing.s),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// TextInputFormatter that uppercases input as the user types.
/// Used by the typed-confirmation gate so caps-lock state doesn't
/// matter for the user.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

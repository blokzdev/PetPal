import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design.dart';
import 'sync_providers.dart';

/// Phase 7 task G.2 — passphrase setup flow.
///
/// **Two-step acknowledgment lock per DECISIONS row 71.**
/// Single checkbox is insufficient — passphrase loss =
/// unrecoverable synced wiki. The user must:
///
///   1. **Acknowledge "we cannot recover this"** — checkbox + Continue.
///   2. **Acknowledge "I have written it down"** — checkbox + Continue.
///   3. Enter the passphrase twice (matches before "Save" enables).
///
/// Back button in steps 2 / 3 walks back; back from step 1 cancels
/// (the AppBar X also cancels). Pushed as `fullscreenDialog: true`
/// so the system back gesture is a full screen dismissal — the
/// user can't accidentally swipe past the warning.
///
/// On Save → derive Argon2id key (~500ms wall time on real devices,
/// surfaced via the spinner), encrypt the passphrase challenge,
/// upload to Supabase, cache the derived key in [SyncSession].
/// Caller pops back to Settings; the Sync card flips to "Sync is
/// on" state.
class PassphraseSetupScreen extends ConsumerStatefulWidget {
  const PassphraseSetupScreen({super.key});

  @override
  ConsumerState<PassphraseSetupScreen> createState() =>
      _PassphraseSetupScreenState();
}

enum _Stage { warning, written, entry }

class _PassphraseSetupScreenState
    extends ConsumerState<PassphraseSetupScreen> {
  _Stage _stage = _Stage.warning;
  bool _ackUnrecoverable = false;
  bool _ackWrittenDown = false;
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pw = _passphrase.text;
    final confirm = _confirm.text;
    if (pw.length < 12) {
      setState(() => _error = 'Passphrase must be at least 12 characters.');
      return;
    }
    if (pw != confirm) {
      setState(() => _error = "Passphrases don't match.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(syncSetupActionProvider).runSetup(passphrase: pw);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Passphrase set. Sync is on — your journal will start '
            'mirroring across your devices.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = "Couldn't set up sync: $e";
      });
    }
  }

  /// Walk back one stage, or pop the screen if we're already on
  /// step 1. Routed from the AppBar back arrow + the system back
  /// gesture (via PopScope).
  bool _handleBack() {
    switch (_stage) {
      case _Stage.entry:
        setState(() => _stage = _Stage.written);
        return false;
      case _Stage.written:
        setState(() => _stage = _Stage.warning);
        return false;
      case _Stage.warning:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == _Stage.warning,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Set sync passphrase'),
          leading: IconButton(
            icon: Icon(_stage == _Stage.warning
                ? PhosphorIconsRegular.x
                : PhosphorIconsRegular.caretLeft),
            onPressed: () {
              if (_handleBack()) {
                Navigator.of(context).pop(false);
              }
            },
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.l),
            child: switch (_stage) {
              _Stage.warning => _WarningStage(
                  acknowledged: _ackUnrecoverable,
                  onChanged: (v) =>
                      setState(() => _ackUnrecoverable = v ?? false),
                  onContinue: _ackUnrecoverable
                      ? () => setState(() => _stage = _Stage.written)
                      : null,
                ),
              _Stage.written => _WrittenDownStage(
                  acknowledged: _ackWrittenDown,
                  onChanged: (v) =>
                      setState(() => _ackWrittenDown = v ?? false),
                  onContinue: _ackWrittenDown
                      ? () => setState(() => _stage = _Stage.entry)
                      : null,
                ),
              _Stage.entry => _EntryStage(
                  passphrase: _passphrase,
                  confirm: _confirm,
                  saving: _saving,
                  error: _error,
                  onSave: _save,
                ),
            },
          ),
        ),
      ),
    );
  }
}

class _WrittenDownStage extends StatelessWidget {
  const _WrittenDownStage({
    required this.acknowledged,
    required this.onChanged,
    required this.onContinue,
  });

  final bool acknowledged;
  final ValueChanged<bool?> onChanged;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          PhosphorIconsRegular.notebook,
          size: 56,
          color: scheme.primary,
        ),
        Gaps.l,
        Text(
          'Write it down before you set it.',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        Gaps.l,
        Text(
          "A password manager is best. A paper note in a drawer is "
          "fine. Phone notes that sync to another account that you "
          "control also works.",
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        Gaps.m,
        Text(
          "What doesn't work: only remembering it. Only storing it "
          "inside this app (the whole point of E2EE is that the "
          "app doesn't see it). Only on this phone (if the phone "
          "breaks before the second device installs, your synced "
          "wiki goes with it).",
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const Spacer(),
        CheckboxListTile(
          value: acknowledged,
          onChanged: onChanged,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            "I have written this down somewhere safe — a password "
            "manager, paper, or another device I control.",
          ),
        ),
        Gaps.m,
        FilledButton(
          onPressed: onContinue,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _WarningStage extends StatelessWidget {
  const _WarningStage({
    required this.acknowledged,
    required this.onChanged,
    required this.onContinue,
  });

  final bool acknowledged;
  final ValueChanged<bool?> onChanged;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          PhosphorIconsRegular.lock,
          size: 56,
          color: scheme.primary,
        ),
        Gaps.l,
        Text(
          'Your passphrase is the only key.',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        Gaps.l,
        Text(
          "Sync wraps your journal in end-to-end encryption before "
          "it leaves the phone — only your devices can read it. "
          "PetPal can't.",
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        Gaps.m,
        Text(
          "If you forget your passphrase, your synced journal is "
          "unrecoverable. We don't have a copy. We can't reset it. "
          "We can't email it. There is no support path.",
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        const Spacer(),
        CheckboxListTile(
          value: acknowledged,
          onChanged: onChanged,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            "I understand that PetPal cannot recover this "
            "passphrase if I lose it.",
          ),
        ),
        Gaps.m,
        FilledButton(
          onPressed: onContinue,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _EntryStage extends StatelessWidget {
  const _EntryStage({
    required this.passphrase,
    required this.confirm,
    required this.saving,
    required this.error,
    required this.onSave,
  });

  final TextEditingController passphrase;
  final TextEditingController confirm;
  final bool saving;
  final String? error;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Choose your sync passphrase.",
          style: theme.textTheme.headlineSmall,
        ),
        Gaps.s,
        Text(
          "12+ characters. Use a sentence you'll remember — "
          '"my orange tabby loki turned three on a rainy april '
          'morning" works fine and is harder to guess than a short '
          'password.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        Gaps.l,
        TextField(
          controller: passphrase,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Passphrase',
            border: OutlineInputBorder(),
          ),
        ),
        Gaps.m,
        TextField(
          controller: confirm,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Confirm passphrase',
            border: const OutlineInputBorder(),
            errorText: error,
          ),
          onSubmitted: (_) => saving ? null : onSave(),
        ),
        const Spacer(),
        FilledButton(
          onPressed: saving ? null : onSave,
          child: saving
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: Spacing.s),
                    Text('Deriving key…'),
                  ],
                )
              : const Text('Save passphrase'),
        ),
      ],
    );
  }
}

/// Phase 7 task G.2 — passphrase unlock sheet for second-device
/// scenarios. Pulls the existing challenge, prompts for the
/// passphrase, decrypts the challenge to validate, caches the
/// derived key on [SyncSession]. Returns true on success, false
/// on cancel; surfaces inline error on wrong passphrase.
Future<bool?> showPassphraseUnlockSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
      ),
      child: const _UnlockSheet(),
    ),
  );
}

class _UnlockSheet extends ConsumerStatefulWidget {
  const _UnlockSheet();

  @override
  ConsumerState<_UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends ConsumerState<_UnlockSheet> {
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final pw = _input.text;
    if (pw.isEmpty) {
      setState(() => _error = 'Passphrase required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await ref
          .read(syncSetupActionProvider)
          .runUnlock(passphrase: pw);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _busy = false;
          _error = "That passphrase doesn't match. Try again.";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't unlock sync: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.l,
        Spacing.s,
        Spacing.l,
        Spacing.l,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Unlock sync',
            style: theme.textTheme.titleMedium,
          ),
          Gaps.s,
          Text(
            "Enter the passphrase you set up on your other device.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Gaps.l,
          TextField(
            controller: _input,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Passphrase',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _unlock(),
          ),
          Gaps.l,
          Row(
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _unlock,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Unlock'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

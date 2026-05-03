import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design.dart';
import '../entitlement/entitlement_notifier.dart';
import '../providers.dart';
import 'byok_validator.dart';

/// Phase 7 task F.1 — modal sheet that captures + validates an
/// `sk-ant-…` key, then flips the entitlement state to BYOK.
///
/// Validation flow per DECISIONS row 74:
///
///   1. Format check — regex match. Inline error on miss.
///   2. Live ping `/v1/models`. 401/403 → inline auth error.
///      Network failure → soft warning ("couldn't verify the key
///      — saving anyway") + accept; the user finds out at first
///      chat if the key is actually broken.
///   3. On accept: persist via [SecureApiKeyStorage] + flip
///      `entitlementProvider` to [Entitlement.byok] via
///      `setByokActive(active: true, apiKey:)`. Caller pops the
///      sheet on success.
///
/// Returns `true` on accept, `false` on cancel — callers (Settings
/// toggle) can flip the switch UI off again on cancel.
Future<bool?> showByokKeyEntrySheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
      ),
      child: const _ByokKeyEntrySheet(),
    ),
  );
}

class _ByokKeyEntrySheet extends ConsumerStatefulWidget {
  const _ByokKeyEntrySheet();

  @override
  ConsumerState<_ByokKeyEntrySheet> createState() => _ByokKeyEntrySheetState();
}

class _ByokKeyEntrySheetState extends ConsumerState<_ByokKeyEntrySheet> {
  final _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Paste your Anthropic key first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final validator = ref.read(byokValidatorProvider);
    final result = await validator.validate(key);
    if (!mounted) return;
    switch (result) {
      case ByokAccepted():
        await _commit(key, softWarning: null);
      case ByokRejectedFormat():
        setState(() {
          _saving = false;
          _error = "That doesn't look like an Anthropic key. They start "
              'with sk-ant- and run for around 100 characters.';
        });
      case ByokRejectedAuth():
        setState(() {
          _saving = false;
          _error = "Anthropic didn't accept that key. Check it at "
              'console.anthropic.com → Settings → API Keys.';
        });
      case ByokNetworkError():
        // DECISIONS row 74 — soft warning, store anyway.
        await _commit(
          key,
          softWarning: "Couldn't verify the key — saving anyway. If "
              'chat fails, check the key in Settings.',
        );
    }
  }

  Future<void> _commit(String key, {String? softWarning}) async {
    try {
      await ref.read(entitlementProvider.notifier).setByokActive(
            active: true,
            apiKey: key,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      if (softWarning != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(softWarning)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'BYOK on. Chat now goes direct to Anthropic.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the key: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
            'Bring your own Anthropic key',
            style: theme.textTheme.titleMedium,
          ),
          Gaps.s,
          Text(
            'Paste your key and PetPal will check it with Anthropic. '
            "Chat then goes direct — PetPal's monthly limits don't "
            'apply.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Gaps.l,
          TextField(
            controller: _controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API key',
              hintText: 'sk-ant-…',
              errorText: _error,
              prefixIcon: const Icon(PhosphorIconsRegular.key),
            ),
            onSubmitted: (_) => _save(),
          ),
          Gaps.s,
          Text(
            'Stored encrypted on this phone only. Get a key at '
            'console.anthropic.com → Settings → API Keys.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Gaps.l,
          Row(
            children: [
              TextButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save and verify'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../auth/app_auth_session.dart';
import '../auth/auth_gateway.dart';
import '../auth/auth_session_notifier.dart';
import '../design/design.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_card.dart';

/// Phase 7 task H.1.c — magic-link sign-in screen.
///
/// Flow:
///   1. User enters email, taps "Send sign-in link".
///   2. AuthSessionNotifier.sendMagicLink() forwards to Supabase Auth.
///   3. Screen flips to a "Check your inbox" confirmation card.
///   4. User taps the magic link in their email app on this device.
///   5. supabase_flutter's app_links listener catches the deep-link
///      return; the auth gateway fires onSessionChange; the notifier
///      transitions state to AsyncData(session).
///   6. This screen listens for that transition and pops itself.
///
/// Edge cases handled:
///   - Empty / malformed email: Send button stays disabled; light
///     inline hint when the user tries anyway.
///   - Network / Supabase error: returns to entry state with an
///     error banner; the email + the "Send again" affordance both
///     stay reachable.
///   - User backgrounds the app between send + tap: Android keeps
///     this screen in the back-stack; on resume + signedIn event,
///     pop returns the user to wherever they came from.
///   - User taps the magic link but the app was killed: the deep
///     link goes through `main()`, the auth notifier picks up the
///     session, and the user lands at /home directly. This screen
///     never runs in that case.
///
/// Voice (VOICE.md §6 example 18): passwordless framing, single-
/// device flow named honestly ("Tap it on this device").
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailController = TextEditingController();
  final _emailFocus = FocusNode();
  bool _sending = false;
  bool _sentTo = false;
  String? _errorMessage;
  String _lastSentEmail = '';

  @override
  void initState() {
    super.initState();
    // Refresh the Send button enabled state as the user types.
    _emailController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  bool get _emailIsValid {
    // Forgiving format check — full RFC 5322 compliance is overkill
    // for a UI gate. Supabase handles deeper validation server-side.
    final s = _emailController.text.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
  }

  Future<void> _send() async {
    final email = _emailController.text.trim();
    if (!_emailIsValid) return;

    setState(() {
      _sending = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(authSessionProvider.notifier)
          .sendMagicLink(email: email);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sentTo = true;
        _lastSentEmail = email;
      });
    } on AuthGatewayException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _errorMessage =
            'Could not send the sign-in email. Check your connection and try again.';
      });
    }
  }

  void _backToEntry() {
    setState(() {
      _sentTo = false;
      _errorMessage = null;
    });
    _emailFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    // When the auth session populates (deep-link return arrived),
    // dismiss this screen — the user is signed in.
    ref.listen<AsyncValue<AppAuthSession?>>(authSessionProvider, (prev, next) {
      final wasSignedOut = prev?.value == null;
      final nowSignedIn = next.value != null;
      if (wasSignedOut && nowSignedIn && mounted) {
        Navigator.of(context).maybePop();
      }
    });

    return AppScaffold(
      title: 'Sign in',
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.m),
          child: _sentTo ? _buildConfirmation(context) : _buildEntry(context),
        ),
      ),
    );
  }

  Widget _buildEntry(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Spacing.s),
        Text(
          'Sign in to PetPal',
          style: textTheme.headlineSmall?.copyWith(
            fontVariations: [const FontVariation('wght', 600)],
          ),
        ),
        const SizedBox(height: Spacing.s),
        Text(
          "We'll email you a link. Tap it on this device to sign in — "
          'no password needed.',
          style: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.75),
            height: 1.45,
          ),
        ),
        const SizedBox(height: Spacing.l),
        TextField(
          controller: _emailController,
          focusNode: _emailFocus,
          autofocus: true,
          enabled: !_sending,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _emailIsValid ? _send() : null,
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(PhosphorIconsRegular.envelopeSimple),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: Spacing.s),
          _ErrorBanner(message: _errorMessage!),
        ],
        const SizedBox(height: Spacing.m),
        FilledButton(
          onPressed: _emailIsValid && !_sending ? _send : null,
          child: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send sign-in link'),
        ),
        const SizedBox(height: Spacing.l),
        _PrivacyDisclosure(),
      ],
    );
  }

  Widget _buildConfirmation(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Spacing.l),
        Center(
          child: Icon(
            PhosphorIconsRegular.envelopeOpen,
            size: 56,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: Spacing.m),
        Text(
          'Check your inbox',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(
            fontVariations: [const FontVariation('wght', 600)],
          ),
        ),
        const SizedBox(height: Spacing.s),
        Text(
          'We sent a sign-in link to $_lastSentEmail. Tap it on this '
          'device — PetPal will open signed in.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.75),
            height: 1.45,
          ),
        ),
        const SizedBox(height: Spacing.l),
        PetCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                PhosphorIconsRegular.info,
                size: 18,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: Spacing.s),
              Expanded(
                child: Text(
                  "The link expires in an hour. Didn't get it? Try a "
                  'different email below.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.m),
        TextButton.icon(
          onPressed: _backToEntry,
          icon: const Icon(PhosphorIconsRegular.arrowLeft, size: 16),
          label: const Text('Try a different email'),
        ),
      ],
    );
  }
}

class _PrivacyDisclosure extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return PetCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            PhosphorIconsRegular.shield,
            size: 18,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: Spacing.s),
          Expanded(
            child: Text(
              'Your account links your devices for sync and the free '
              'monthly chat allowance. Your journal stays end-to-end '
              "encrypted — PetPal can't read it.",
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.7),
                height: 1.45,
              ),
            ),
          ),
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

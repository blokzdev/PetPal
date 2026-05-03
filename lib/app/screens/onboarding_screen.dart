import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/design.dart';
import '../welcome/welcome_completed_notifier.dart';

/// First-run onboarding — Phase 7 task F.1 redesign.
///
/// Two pages in a swipe-friendly [PageView]: narrative-led welcome
/// then a sectioned proxy-default privacy disclosure (VOICE.md §6
/// example 15). The pre-Phase-7 third page asking for an Anthropic
/// API key is gone — the proxy-default monetization model
/// (DECISIONS row 36) means a fresh-install user is past
/// onboarding without ever entering a key. BYOK lives in Settings
/// as an opt-in toggle (VOICE.md §6 example 12, DECISIONS row 74).
///
/// Existing users with a stored key from pre-Phase-7 onboarding
/// never see this screen — `WelcomeCompletedNotifier.build()`
/// auto-promotes them on first F.1 launch.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;
  bool _saving = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      await ref.read(welcomeCompletedProvider.notifier).markCompleted();
      // The router's redirect listener routes us to '/'.
      if (mounted) context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't finish setup: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _WelcomePage(onContinue: _next),
                  _PrivacyPage(saving: _saving, onContinue: _finish),
                ],
              ),
            ),
            _PageIndicator(page: _page, count: 2),
            const SizedBox(height: Spacing.m),
          ],
        ),
      ),
    );
  }
}

/// Welcome — narrative-led. The journal-+-paw mark sits above a
/// serif tagline (PetPal's serif is reserved for journal-flavored
/// surfaces; using it on the welcome reinforces the journal-as-moat
/// thesis the app is built around). Body copy lists three concrete
/// memory-types (vet visits, weight, missed food) instead of abstract
/// value props — concrete-over-abstract per VOICE.md §1.
class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.l),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Journal-+-paw mark, centered. The PNG already has the
          // medium stroke weight + leaf/eye silhouette locked in 5.3.
          // Sized at 144 dp on the welcome surface — large enough to
          // read as a brand mark, not so large it dominates and
          // crowds out the tagline.
          Center(
            child: Image.asset(
              'assets/branding/icon-foreground.png',
              width: 144,
              height: 144,
              color: scheme.onSurface,
            ),
          ),
          Gaps.l,
          Text(
            "PetPal remembers your pet's life so you don't have to.",
            textAlign: TextAlign.center,
            style: JournalText.weeklySummaryTitle(color: scheme.onSurface),
          ),
          Gaps.l,
          Text(
            "Vet visits. Weight. The food they didn't eat. PetPal "
            'keeps the thread — and tells you when something looks '
            'serious enough to call the vet.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          Gaps.xl,
          FilledButton(
            onPressed: onContinue,
            child: const Text('Get started'),
          ),
        ],
      ),
    );
  }
}

/// Privacy — VOICE.md §6 example 15 ("How chat works"). Sectioned
/// plain-English under two sub-headers: "Your pet's journal." and
/// "How chat works." with the proxy-default explanation + the
/// Settings BYOK escape valve. The not-a-vet footer survives
/// unchanged; the CTA is "Get started" (forward motion + the verb
/// matches the welcome's CTA so the user has continuity through
/// the flow).
class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage({required this.saving, required this.onContinue});
  final bool saving;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final headlineStyle = theme.textTheme.headlineSmall;
    final sectionLabelStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.4,
    );
    final footerStyle = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      fontStyle: FontStyle.italic,
      height: 1.4,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.l,
        vertical: Spacing.m,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Gaps.m,
            Text('Your data, your device.', style: headlineStyle),
            Gaps.l,
            Text("Your pet's journal.", style: sectionLabelStyle),
            Gaps.s,
            Text(
              "Stays on this phone by default. With Pro and a sign-in, "
              "you can sync an encrypted copy across devices — PetPal "
              "can't read it without your passphrase.",
              style: bodyStyle,
            ),
            Gaps.l,
            // VOICE.md §6 example 15 — proxy-default + BYOK escape
            // valve, locked copy. Frames PetPal as the routing layer
            // for the free 200-msg/mo allowance, and surfaces BYOK
            // as a Settings choice (not a required setup step).
            Text('How chat works.', style: sectionLabelStyle),
            Gaps.s,
            Text(
              'When you ask PetPal something, your message and the '
              "relevant memories about your pet go to Anthropic's "
              'Claude. By default, PetPal routes that through our '
              "servers — this is how the free 200-message-a-month "
              "allowance works, and it's the only thing that "
              'leaves the phone. You can switch to your own '
              'Anthropic API key any time in Settings; with that '
              "on, calls go direct to Anthropic and our servers "
              "don't see them.",
              style: bodyStyle,
            ),
            Gaps.l,
            // Footer: not-a-vet disclaimer. Italic to read as a
            // softer, footer-tone reminder rather than another
            // body-copy bullet.
            Text(
              'PetPal is software, not a vet — if something looks '
              'urgent, PetPal will tell you to call yours.',
              style: footerStyle,
            ),
            Gaps.l,
            Center(
              child: FilledButton(
                onPressed: saving ? null : onContinue,
                child: saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Get started'),
              ),
            ),
            Gaps.m,
          ],
        ),
      ),
    );
  }
}

/// Soft dots indicating progress through the [PageView]. Active
/// dot is wider than inactive and uses the primary color; inactive
/// dots use a muted onSurface tone.
class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.page, required this.count});
  final int page;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == page;
        return AnimatedContainer(
          duration: Motion.short,
          curve: Motion.standardCurve,
          margin: const EdgeInsets.symmetric(horizontal: Spacing.xs),
          width: active ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active
                ? scheme.primary
                : scheme.onSurfaceVariant.withValues(alpha: 0.3),
            borderRadius: Corners.xs,
          ),
        );
      }),
    );
  }
}

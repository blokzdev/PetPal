import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/design.dart';
import '../providers.dart';

/// First-run onboarding — task 5.6 redesign.
///
/// Three pages in a swipe-friendly [PageView]: narrative-led welcome,
/// sectioned plain-English privacy disclosure, then a small
/// "one-last-thing" Anthropic API key step framed as a utility, not as
/// the welcome itself. The directional choices were locked by the user
/// in the task 5.6 design questions; the picks: narrative-led welcome,
/// sectioned plain-English privacy, "One last thing — your Anthropic
/// key" framing.
///
/// Phase 5 reality (DECISIONS row 36 follow-up): the privacy
/// disclosure describes the BYOK-only path because PetPal's
/// LLM-call proxy doesn't ship until Phase 7. When the proxy lands,
/// a Phase 7 task will refresh this copy to match VOICE.md §6
/// example 15's proxy-default narrative — until then, "your API
/// key, direct to Anthropic" is the honest framing.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  final _apiKeyController = TextEditingController();
  int _page = 0;
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    _pageController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Future<void> _saveAndContinue() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() => _saveError = 'Enter a non-empty API key.');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await ref.read(apiKeyProvider.notifier).save(key);
      // The router's redirect listener will route us to '/'.
      if (mounted) context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Could not save key: $e';
      });
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
                  _PrivacyPage(onContinue: _next),
                  _ApiKeyPage(
                    controller: _apiKeyController,
                    error: _saveError,
                    saving: _saving,
                    onSubmit: _saveAndContinue,
                  ),
                ],
              ),
            ),
            _PageIndicator(page: _page, count: 3),
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
          // ColorFiltered isn't needed — the foreground PNG already
          // ships in graphite, which reads correctly on the warm
          // off-white scaffold background.
          //
          // Sized at 144 dp on the welcome surface — large enough to
          // read as a brand mark, not so large it dominates and
          // crowds out the tagline.
          Center(
            child: Image.asset(
              'assets/branding/icon-foreground.png',
              width: 144,
              height: 144,
              // The dark-variant asset exists at icon-foreground-dark.png
              // and gets used by the splash on dark mode; here the mark
              // sits on the surface tone (off-white in light, warm
              // graphite in dark), so we want a theme-aware color
              // filter that maps the graphite-on-transparent source
              // asset to onSurface in either mode.
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

/// Privacy — sectioned plain-English. Two sub-headers ("Your pet's
/// journal." / "When you chat.") with 1-2 sentence prose under each,
/// plus a one-line not-a-vet footer. Scannable AND conversational —
/// closer in spirit to VOICE.md §6 ex 15's voice while preserving
/// enough structure that a privacy-conscious user can skim.
///
/// Phase 5 framing: chat goes direct to Anthropic via the user's
/// API key. This is honest about what ships now (BYOK-only). Phase 7
/// will rewrite this copy when the LLM proxy lands and a free-tier
/// 200-msg/mo path becomes the default; until then, "your key,
/// direct to Anthropic, nothing else leaves" is the truthful story.
class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage({required this.onContinue});
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Gaps.m,
          Text('Your data, your device.', style: headlineStyle),
          Gaps.l,
          Text("Your pet's journal.", style: sectionLabelStyle),
          Gaps.s,
          Text(
            "Stays on this phone. PetPal doesn't copy it to a server.",
            style: bodyStyle,
          ),
          Gaps.l,
          Text('When you chat.', style: sectionLabelStyle),
          Gaps.s,
          Text(
            'Your message and the relevant memories about your pet '
            "go to Anthropic's Claude using your API key. Nothing "
            'else leaves the phone.',
            style: bodyStyle,
          ),
          const Spacer(),
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
              onPressed: onContinue,
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

/// API key — "One last thing" utility framing. The title telegraphs
/// "this is small wiring before we begin", not "welcome to setup".
/// Body explains Anthropic + Claude in two sentences, then the
/// console.anthropic.com path. CTA is "Save and continue" — verb
/// + forward motion, not a brand-name like "Connect to Anthropic".
class _ApiKeyPage extends StatelessWidget {
  const _ApiKeyPage({
    required this.controller,
    required this.error,
    required this.saving,
    required this.onSubmit,
  });
  final TextEditingController controller;
  final String? error;
  final bool saving;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.l,
        vertical: Spacing.m,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gaps.m,
          Text(
            'One last thing — your Anthropic key.',
            style: theme.textTheme.headlineSmall,
          ),
          Gaps.m,
          Text(
            'PetPal runs on Claude, made by Anthropic. You\'ll need '
            'a key from them to chat. Get one at '
            'console.anthropic.com → Settings → API Keys.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          Gaps.l,
          TextField(
            controller: controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API key',
              hintText: 'sk-ant-…',
              errorText: error,
            ),
            onSubmitted: (_) => onSubmit(),
          ),
          Gaps.s,
          Text(
            'Stored encrypted on this phone only. You can change or '
            'remove it later in Settings.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: saving ? null : onSubmit,
            child: saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save and continue'),
          ),
        ],
      ),
    );
  }
}

/// Three soft dots indicating progress through the PageView. Active
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

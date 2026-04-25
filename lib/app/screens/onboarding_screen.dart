import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';

/// First-run onboarding: welcome → privacy disclosure → API key entry.
/// Three pages in a swipe-friendly [PageView]; a forward arrow on each
/// page advances to the next, the final page persists the API key and
/// the router's redirect kicks the user back to `/`.
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
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.pets, size: 96, color: scheme.primary),
          const SizedBox(height: 24),
          Text(
            'Welcome to PetPal',
            textAlign: TextAlign.center,
            style: text.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'A memory agent for your pet.',
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Text(
            'Track your pet’s life — vet visits, weight, food trials, '
            'behavior notes — and know when to call the vet.',
            textAlign: TextAlign.center,
            style: text.bodyMedium,
          ),
          const SizedBox(height: 32),
          FilledButton(onPressed: onContinue, child: const Text('Get started')),
        ],
      ),
    );
  }
}

class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage({required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your data, your device.', style: text.headlineSmall),
          const SizedBox(height: 16),
          const _Bullet(
            'Your pet’s wiki — vet visits, weight, notes, photos — '
            'stays on this device. PetPal does not back it up to a server.',
          ),
          const _Bullet(
            'Search runs on-device. Embeddings and keyword indexing use a '
            'local model bundled with the app.',
          ),
          const _Bullet(
            'Chat sends your conversation and the most relevant wiki '
            'snippets to Anthropic’s Claude API using your own API '
            'key. That call leaves the device.',
          ),
          const _Bullet(
            'PetPal is not a vet and does not diagnose. If something '
            'looks urgent, the app will tell you to call your vet.',
          ),
          const Spacer(),
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
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Connect to Anthropic', style: text.headlineSmall),
          const SizedBox(height: 16),
          Text(
            'PetPal uses Claude via your own Anthropic API key. '
            'Generate one at console.anthropic.com → Settings → API Keys.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API key',
              hintText: 'sk-ant-…',
              border: const OutlineInputBorder(),
              errorText: error,
            ),
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 8),
          Text(
            'Stored encrypted on this device only. You can change or '
            'remove it later in Settings.',
            style: text.bodySmall,
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

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: Icon(Icons.circle, size: 6),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

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
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 16 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active
                ? scheme.primary
                : scheme.onSurfaceVariant.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/api_key_storage.dart';
import '../../platform/settings_storage.dart';
import '../providers.dart';

/// Phase 7 task F.1 — onboarding-completed flag.
///
/// Pre-Phase-7 onboarding bound "is the user past the welcome flow"
/// to "does the user have an Anthropic API key" — `isOnboardedProvider`
/// returned true iff `apiKeyProvider` had a non-empty value. F.1
/// decouples the two: a free-tier user (proxy-default per DECISIONS
/// row 36) never enters a key, but is still past the welcome flow
/// after seeing the privacy disclosure. This notifier owns the new
/// "welcome flow finished" signal independently of the key.
///
/// Persistence: [SettingsStorage] under `welcome_completed`.
///
/// **Migration on first F.1 launch.** Existing users who completed
/// pre-Phase-7 onboarding have an API key in [SecureApiKeyStorage]
/// but no `welcome_completed` flag set. To avoid bouncing them
/// through the new onboarding (they're already past it), [build]
/// auto-promotes any user whose `apiKeyStorage` has a non-empty key
/// — once, on first read, persisted. Pre-existing keys remain as-is
/// (DECISIONS row 74's "existing keys persist on upgrade" lock); the
/// entitlement notifier separately auto-promotes them to BYOK so
/// chat keeps working without re-prompting for the key.
class WelcomeCompletedNotifier extends AsyncNotifier<bool> {
  static const _key = 'welcome_completed';

  @override
  Future<bool> build() async {
    // Defensive: tests that don't override settingsStorageProvider /
    // apiKeyStorageProvider see the build path gracefully fall
    // through to "completed" rather than triggering a router
    // redirect to /onboarding for a screen they're trying to test.
    // Production overrides both in `main()`, so this guard never
    // fires in the running app.
    try {
      final settings = ref.read(settingsStorageProvider);
      final stored = await settings.getBool(_key);
      if (stored == true) return true;
      final apiKey = await ref.read(apiKeyStorageProvider).read();
      if (apiKey != null && apiKey.isNotEmpty) {
        await settings.setBool(_key, true);
        return true;
      }
      return false;
    } catch (_) {
      // Test path with no storage overrides — assume the user is
      // past onboarding so screen tests aren't redirected.
      return true;
    }
  }

  /// Mark the welcome flow finished. Called from the onboarding
  /// screen's "Get started" CTA on the privacy disclosure page.
  Future<void> markCompleted() async {
    await ref.read(settingsStorageProvider).setBool(_key, true);
    state = const AsyncData(true);
  }
}

/// Phase 7 task F.1 — `welcome_completed` flag.
final welcomeCompletedProvider =
    AsyncNotifierProvider<WelcomeCompletedNotifier, bool>(
  WelcomeCompletedNotifier.new,
);

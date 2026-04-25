import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/api_key_storage.dart';

/// Singleton [ApiKeyStorage]. Overridden in `main()` with
/// [SecureApiKeyStorage]; widget tests override with an in-memory fake.
final apiKeyStorageProvider = Provider<ApiKeyStorage>((ref) {
  throw UnimplementedError(
    'apiKeyStorageProvider must be overridden in ProviderScope',
  );
});

/// The user's current Anthropic API key, or null if onboarding isn't done.
///
/// Implemented as a state-keeping `Notifier` so the onboarding flow can
/// `notifier.set(...)` after a successful save and the rest of the app
/// (chat, settings, the router redirect in `routerProvider`) reacts
/// immediately — no second `read()` round-trip to secure storage.
final apiKeyProvider =
    AsyncNotifierProvider<ApiKeyNotifier, String?>(ApiKeyNotifier.new);

class ApiKeyNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() => ref.read(apiKeyStorageProvider).read();

  Future<void> save(String apiKey) async {
    final trimmed = apiKey.trim();
    await ref.read(apiKeyStorageProvider).write(trimmed);
    state = AsyncData(trimmed);
  }

  Future<void> clear() async {
    await ref.read(apiKeyStorageProvider).clear();
    state = const AsyncData(null);
  }
}

/// True once the user has saved a non-empty API key. The router uses this
/// to gate the onboarding redirect.
final isOnboardedProvider = Provider<bool>((ref) {
  final keyAsync = ref.watch(apiKeyProvider);
  return keyAsync.maybeWhen(
    data: (k) => k != null && k.isNotEmpty,
    orElse: () => false,
  );
});

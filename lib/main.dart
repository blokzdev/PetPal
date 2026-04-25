import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'app/routing.dart';
import 'app/theme.dart';
import 'platform/api_key_storage.dart';
import 'platform/settings_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-read the API key so the router's redirect has a synchronous answer
  // on first frame — otherwise the user briefly sees Home before bouncing
  // to /onboarding.
  final storage = SecureApiKeyStorage();
  final initialKey = await storage.read();

  // Open SharedPreferences for app-wide settings (e.g. weekly digest
  // toggle from 3.8). Pre-opened in main() so providers can read it
  // synchronously after the first build.
  final settings = await SharedPrefsSettingsStorage.open();

  runApp(
    ProviderScope(
      overrides: [
        apiKeyStorageProvider.overrideWithValue(storage),
        apiKeyProvider.overrideWith(() => _SeededApiKeyNotifier(initialKey)),
        settingsStorageProvider.overrideWithValue(settings),
      ],
      child: const PetPalApp(),
    ),
  );
}

class PetPalApp extends ConsumerWidget {
  const PetPalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'PetPal',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// [ApiKeyNotifier] variant that returns the pre-read [initialKey]
/// synchronously instead of round-tripping to secure storage on first
/// build. Keeps the router redirect free of a loading state.
class _SeededApiKeyNotifier extends ApiKeyNotifier {
  _SeededApiKeyNotifier(this._initial);
  final String? _initial;

  @override
  Future<String?> build() async => _initial;
}

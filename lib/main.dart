import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'app/routing.dart';
import 'app/theme.dart';
import 'app/welcome/welcome_completed_notifier.dart';
import 'platform/api_key_storage.dart';
import 'platform/notifications_service.dart';
import 'platform/scheduler_bootstrap.dart';
import 'platform/scheduler_bootstrap_registry.dart';
import 'platform/scheduler_log.dart';
import 'platform/settings_storage.dart';
import 'platform/work_scheduler.dart';

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

  // Phase 7 task F.1 — pre-read the welcome flag so the router's
  // redirect has a synchronous answer on first frame. Mirrors the
  // pre-read of the API key above. Pre-Phase-7 users with a stored
  // key are auto-promoted by [WelcomeCompletedNotifier.build] —
  // this pre-read applies the same migration synchronously so the
  // router doesn't briefly bounce them through onboarding.
  final welcomeStored = await settings.getBool('welcome_completed');
  final welcomeCompleted = welcomeStored ??
      (initialKey != null && initialKey.isNotEmpty);
  if (welcomeCompleted && welcomeStored != true) {
    await settings.setBool('welcome_completed', true);
  }

  // Phase 4 scheduling stack init. Order matters:
  //   1. Notifications channel (so the alarm callback's `show()` works
  //      even if the user opens an alarm-fired flow before re-opening
  //      the app).
  //   2. AlarmManager + WorkManager dispatchers — so the alarm/work
  //      callbacks can find their isolate-side bootstrap.
  //   3. Register `bootstrapAndFire` in the bootstrap registry. The
  //      alarm/work callbacks resolve this lazily at fire time.
  await NotificationsService().initialize();
  await AndroidAlarmManager.initialize();
  await WorkScheduler().initialize();
  setSchedulerBootstrap(bootstrapAndFire);
  schedulerLog('app_init', fields: {});

  runApp(
    ProviderScope(
      overrides: [
        apiKeyStorageProvider.overrideWithValue(storage),
        apiKeyProvider.overrideWith(() => _SeededApiKeyNotifier(initialKey)),
        settingsStorageProvider.overrideWithValue(settings),
        welcomeCompletedProvider
            .overrideWith(() => _SeededWelcomeNotifier(welcomeCompleted)),
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

/// Phase 7 task F.1 — [WelcomeCompletedNotifier] variant that
/// returns the pre-read welcome flag synchronously. The migration
/// path was already applied in `main()` above.
class _SeededWelcomeNotifier extends WelcomeCompletedNotifier {
  _SeededWelcomeNotifier(this._initial);
  final bool _initial;

  @override
  Future<bool> build() async => _initial;
}

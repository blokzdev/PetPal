import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'app/auth/auth_gateway.dart';
import 'app/auth/auth_session_notifier.dart';
import 'app/auth/supabase_auth_gateway.dart';
import 'app/providers.dart';
import 'app/routing.dart';
import 'app/sync/supabase_runtime_config.dart';
import 'app/theme.dart';
import 'app/welcome/welcome_completed_notifier.dart';
import 'platform/api_key_storage.dart';
import 'platform/analytics/crash_analytics.dart';
import 'platform/notifications_service.dart';
import 'platform/scheduler_bootstrap.dart';
import 'platform/scheduler_bootstrap_registry.dart';
import 'platform/scheduler_log.dart';
import 'platform/settings_storage.dart';
import 'platform/work_scheduler.dart';

/// Phase 7 task H.1.a — Supabase project URL.
///
/// Supplied at build time via `--dart-define=SUPABASE_URL=...`
/// (see `docs/SETUP.md`). Empty string when unset → main() skips
/// Supabase.initialize() entirely and the app stays on the
/// BYOK / sign-in-coming path.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

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

  // Phase 7 task H.2 — crash analytics opt-in.
  // Hydrate the toggle from persistent storage so the gate is
  // correct from the first error that might fire. v1 uses
  // [NoopCrashAnalytics] regardless of toggle state — the
  // abstraction is in place, the redaction layer is in place,
  // the toggle persists. A concrete provider lands in Phase 8+.
  final crashAnalytics = NoopCrashAnalytics(storage: settings);
  await crashAnalytics.hydrate();

  // Phase 7 task H.1.a/b — Supabase initialization.
  //
  // Both URL + anon key must be supplied via --dart-define for
  // initialization to run. Missing either → silent skip; the
  // authGatewayProvider stays on its InMemoryAuthGateway default,
  // supabaseRuntimeConfigProvider stays null, and the syncBackend
  // / cloudSyncAdapter providers stay on their NoopCloudSyncAdapter
  // / unauthenticated-InMemorySyncBackend fallbacks. This keeps
  // `flutter run` against a dev image without dart-defines viable
  // for non-auth screens.
  SupabaseAuthGateway? supabaseGateway;
  SupabaseRuntimeConfig? supabaseConfig;
  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    await supabase.Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
    supabaseGateway =
        SupabaseAuthGateway(supabase.Supabase.instance.client.auth)
          ..initialize();
    supabaseConfig = const SupabaseRuntimeConfig(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        apiKeyStorageProvider.overrideWithValue(storage),
        apiKeyProvider.overrideWith(() => _SeededApiKeyNotifier(initialKey)),
        settingsStorageProvider.overrideWithValue(settings),
        welcomeCompletedProvider
            .overrideWith(() => _SeededWelcomeNotifier(welcomeCompleted)),
        if (supabaseGateway != null)
          authGatewayProvider.overrideWithValue(supabaseGateway),
        if (supabaseConfig != null)
          supabaseRuntimeConfigProvider.overrideWithValue(supabaseConfig),
        crashAnalyticsProvider.overrideWithValue(crashAnalytics),
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

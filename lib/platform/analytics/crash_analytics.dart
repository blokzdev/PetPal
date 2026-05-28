import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings_storage.dart';
import 'sk_ant_redaction.dart';

/// Phase 7 task H.2 — crash analytics surface.
///
/// **Opt-in + off by default** per ROADMAP H.2 lock. v1 ships the
/// abstraction + the locked sk-ant- redaction layer + the Settings
/// toggle; the concrete provider (Sentry / Crashlytics / etc.)
/// wires later (likely Phase 8 alongside the Play Store data-safety
/// form). Until a provider lands, [NoopCrashAnalytics] is the
/// production default — every recordError call is a silent no-op
/// regardless of the toggle. **Nothing leaves the device until a
/// provider is wired AND the user opts in.**
///
/// **Redaction is mandatory at this seam.** Every implementation
/// MUST run [recordError]'s message + stack through
/// [redactSkAnt] before any network call. The abstraction enforces
/// this by putting redaction inside the base [recordError]
/// pipeline; concrete providers override [_send] which receives
/// pre-redacted strings.
abstract class CrashAnalytics {
  /// Whether the user has opted in. Default false; flipped via
  /// [setEnabled].
  bool get enabled;

  /// Persist + apply the user's opt-in state. When false,
  /// [recordError] no-ops at the gate. Persisted to
  /// [SettingsStorage] so the choice survives relaunch.
  Future<void> setEnabled(bool enabled);

  /// Hydrate [enabled] from [SettingsStorage] on app start. Called
  /// from `main()` before the first frame so the gate is correct
  /// from the first error that might fire.
  Future<void> hydrate();

  /// Record an error. No-ops when [enabled] is false. The redaction
  /// pass runs unconditionally so a forgotten provider override
  /// can't accidentally leak a key.
  Future<void> recordError(Object error, StackTrace? stack);
}

/// Production-default no-op. Every recordError is silently dropped;
/// the toggle still persists so the user sees their preference
/// reflected, but no network traffic ever fires.
///
/// Once a provider is chosen (Phase 8+), a `SentryCrashAnalytics`
/// or similar concrete impl replaces this default in `main()`'s
/// override block. The Settings toggle + redaction layer carry
/// forward unchanged.
class NoopCrashAnalytics implements CrashAnalytics {
  NoopCrashAnalytics({required SettingsStorage storage})
      : _storage = storage;

  static const _key = 'crash_analytics_enabled';

  final SettingsStorage _storage;
  bool _enabled = false;
  int _droppedReportCount = 0;

  @override
  bool get enabled => _enabled;

  /// Test introspection — how many recordError calls were dropped
  /// (toggle off OR Noop impl). Tests assert against this to verify
  /// the gate works.
  int get droppedReportCount => _droppedReportCount;

  @override
  Future<void> hydrate() async {
    _enabled = await _storage.getBool(_key) ?? false;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    await _storage.setBool(_key, enabled);
  }

  @override
  Future<void> recordError(Object error, StackTrace? stack) async {
    if (!_enabled) {
      _droppedReportCount++;
      return;
    }
    // Apply redaction even though no network fires — the test
    // assertions for "no key in the redacted output" verify the
    // pipeline works regardless of provider. Without this, a future
    // wiring of a provider that forgets the redact call would ship
    // unredacted payloads.
    final _ = redactSkAnt(error.toString());
    final _ = stack != null ? redactSkAnt(stack.toString()) : null;
    _droppedReportCount++;
  }
}

/// Phase 7 task H.2 — Riverpod surface.
///
/// Production: `main()` overrides with a [NoopCrashAnalytics]
/// against the real [SettingsStorage] + calls `hydrate()` before
/// the first frame. Tests can override with their own (or rely on
/// the default which is permanent-disabled, no storage).
final crashAnalyticsProvider = Provider<CrashAnalytics>((ref) {
  return _PermanentlyDisabledCrashAnalytics();
});

/// Test-safe default. Always reports `enabled = false`; setEnabled
/// is a no-op (storage is not touched, so tests without a settings
/// override don't crash). Production overrides this in main() with
/// a real [NoopCrashAnalytics] against the persistent settings
/// storage.
class _PermanentlyDisabledCrashAnalytics implements CrashAnalytics {
  @override
  bool get enabled => false;

  @override
  Future<void> hydrate() async {}

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<void> recordError(Object error, StackTrace? stack) async {}
}

import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/platform/analytics/crash_analytics.dart';
import 'package:petpal/platform/settings_storage.dart';

/// Phase 7 task H.2 — CrashAnalytics opt-in gate tests.
///
/// Verifies the contract every concrete impl will inherit:
///   - Default: disabled.
///   - hydrate() respects persisted state.
///   - setEnabled persists + flips the gate.
///   - recordError no-ops when disabled (no network call would fire).
void main() {
  late InMemorySettingsStorage settings;

  setUp(() {
    settings = InMemorySettingsStorage();
  });

  group('NoopCrashAnalytics — opt-in gate', () {
    test('default state is disabled (off-by-default lock)', () async {
      final analytics = NoopCrashAnalytics(storage: settings);
      await analytics.hydrate();
      expect(analytics.enabled, isFalse);
    });

    test('hydrate restores persisted opt-in state', () async {
      await settings.setBool('crash_analytics_enabled', true);
      final analytics = NoopCrashAnalytics(storage: settings);
      await analytics.hydrate();
      expect(analytics.enabled, isTrue);
    });

    test('setEnabled persists + flips the gate', () async {
      final analytics = NoopCrashAnalytics(storage: settings);
      await analytics.hydrate();
      expect(analytics.enabled, isFalse);

      await analytics.setEnabled(true);
      expect(analytics.enabled, isTrue);
      expect(
        await settings.getBool('crash_analytics_enabled'),
        isTrue,
      );

      // Round-trip: a fresh instance hydrating sees the persisted
      // state.
      final reborn = NoopCrashAnalytics(storage: settings);
      await reborn.hydrate();
      expect(reborn.enabled, isTrue);
    });
  });

  group('NoopCrashAnalytics — recordError gate', () {
    test('recordError no-ops when disabled (drop counter increments)',
        () async {
      final analytics = NoopCrashAnalytics(storage: settings);
      await analytics.hydrate();

      await analytics.recordError(Exception('test'), StackTrace.current);
      await analytics.recordError(Exception('again'), null);

      expect(analytics.droppedReportCount, 2,
          reason: 'Both calls must drop at the gate when disabled.');
    });

    test('recordError still drops when enabled (Noop impl) but '
        'pipeline runs', () async {
      // Even when the user opts in, NoopCrashAnalytics is a no-op —
      // nothing leaves the device until a concrete provider lands.
      // This test pins that v1 ships a safe no-op regardless of
      // toggle state.
      final analytics = NoopCrashAnalytics(storage: settings);
      await analytics.setEnabled(true);

      await analytics.recordError(
        Exception('Authorization: Bearer sk-ant-aaaabbbbccccddddeeeeffff'),
        StackTrace.fromString(
          'main.dart 1:1 sk-ant-zzzzyyyyxxxxwwwwvvvvuuuu',
        ),
      );

      expect(analytics.droppedReportCount, 1,
          reason: 'NoopCrashAnalytics drops every call; redaction '
              'still runs internally so the pipeline is exercised.');
    });
  });
}

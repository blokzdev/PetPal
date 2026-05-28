import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/app/welcome/welcome_completed_notifier.dart';
import 'package:petpal/platform/settings_storage.dart';

import '../../_helpers/fake_api_key_storage.dart';

/// Phase 7 task F.1 — welcome-completed notifier tests.
///
/// Pins:
///   - default = false on a clean install
///   - persisted = true survives across rebuilds
///   - migration: existing user with stored API key auto-promoted
///     on first read (and the flag persisted)
///   - markCompleted() persists + emits true
void main() {
  late InMemorySettingsStorage settings;
  late FakeApiKeyStorage keyStorage;
  late ProviderContainer container;

  setUp(() {
    settings = InMemorySettingsStorage();
    keyStorage = FakeApiKeyStorage();
    container = ProviderContainer(
      overrides: [
        settingsStorageProvider.overrideWithValue(settings),
        apiKeyStorageProvider.overrideWithValue(keyStorage),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('clean install with no flag and no key → false', () async {
    final completed = await container.read(welcomeCompletedProvider.future);
    expect(completed, isFalse);
    // No accidental flag write.
    expect(await settings.getBool('welcome_completed'), isNull);
  });

  test('persisted flag = true → returns true without consulting key',
      () async {
    await settings.setBool('welcome_completed', true);
    expect(
      await container.read(welcomeCompletedProvider.future),
      isTrue,
    );
  });

  test('migration: existing key auto-promotes welcomeCompleted on '
      'first read and persists the flag', () async {
    await keyStorage.write('sk-ant-existing-mock-key-1234567890');
    expect(
      await container.read(welcomeCompletedProvider.future),
      isTrue,
    );
    // Migration must persist so subsequent rebuilds skip the
    // apiKey read.
    expect(await settings.getBool('welcome_completed'), isTrue);
  });

  test('migration: empty stored key does NOT promote', () async {
    await keyStorage.write('');
    expect(
      await container.read(welcomeCompletedProvider.future),
      isFalse,
    );
  });

  test('markCompleted() persists + emits true', () async {
    final notifier = container.read(welcomeCompletedProvider.notifier);
    await container.read(welcomeCompletedProvider.future);
    await notifier.markCompleted();
    expect(
      container.read(welcomeCompletedProvider).value,
      isTrue,
    );
    expect(await settings.getBool('welcome_completed'), isTrue);
  });
}

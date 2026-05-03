import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/platform/settings_storage.dart';

import '../../_helpers/fake_api_key_storage.dart';

/// Phase 7 task B.1 + F.1 — entitlementProvider behaviour.
///
/// B.1: returns [Entitlement.freeAnonymous] by default;
/// setOptimistic emits + persists; refresh is a no-op stub.
///
/// F.1: build() reads `byok_enabled` from [SettingsStorage] and
/// auto-promotes pre-Phase-7 users with a stored API key to BYOK
/// (one-time silent migration); setByokActive flips the lane on /
/// off, persisting the key + the flag.
void main() {
  late AppDatabase db;
  late InMemorySettingsStorage settings;
  late FakeApiKeyStorage keyStorage;
  late ProviderContainer container;

  ProviderContainer freshContainer() => ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async {
            ref.onDispose(() async {});
            return db;
          }),
          settingsStorageProvider.overrideWithValue(settings),
          apiKeyStorageProvider.overrideWithValue(keyStorage),
        ],
      );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = InMemorySettingsStorage();
    keyStorage = FakeApiKeyStorage();
    container = freshContainer();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  // ── B.1 invariants ────────────────────────────────────────────────

  test('default state is Entitlement.freeAnonymous on a clean install '
      '(no byok flag, no stored key)', () async {
    final ent = await container.read(entitlementProvider.future);
    expect(ent.state, EntitlementState.freeAnonymous);
    expect(ent.userId, isNull);
  });

  test('refresh is a no-op stub (preserves current state)', () async {
    await container.read(entitlementProvider.future);
    final notifier = container.read(entitlementProvider.notifier);
    final before = container.read(entitlementProvider).value!;

    await notifier.refresh();

    final after = container.read(entitlementProvider).value!;
    expect(after, equals(before));
  });

  test('setOptimistic emits the new entitlement and persists to cache '
      'for non-anonymous states', () async {
    await container.read(entitlementProvider.future);
    final notifier = container.read(entitlementProvider.notifier);

    final pro = Entitlement(
      state: EntitlementState.proMonthly,
      userId: 'user-pro',
      renewalDate: DateTime(2026, 6),
      photoCreditsBalance: 50,
      counterPeriodStart: DateTime(2026, 5),
    );
    await notifier.setOptimistic(pro);

    expect(container.read(entitlementProvider).value, equals(pro));

    final repo = await container.read(entitlementRepoProvider.future);
    final cached = await repo.read('user-pro');
    expect(cached, isNotNull);
    expect(cached!.state, EntitlementState.proMonthly);
  });

  test('setOptimistic for freeAnonymous does NOT persist '
      '(no cache row by design)', () async {
    await container.read(entitlementProvider.future);
    final notifier = container.read(entitlementProvider.notifier);

    await notifier.setOptimistic(Entitlement.freeAnonymous());

    final all = await db.select(db.entitlements).get();
    expect(all, isEmpty);
  });

  // ── F.1 BYOK auto-migration on build() ────────────────────────────

  test('F.1 migration: stored API key auto-promotes to BYOK on first '
      'build and persists the byok_enabled flag', () async {
    // Pre-Phase-7 user: api key in SecureStorage, no byok flag yet.
    await keyStorage.write('sk-ant-existing-mock-key-1234567890');

    final ent = await container.read(entitlementProvider.future);
    expect(ent.state, EntitlementState.byok);
    // Migration persisted the flag so a relaunch picks it up
    // without re-running the apiKey check.
    expect(await settings.getBool('byok_enabled'), isTrue);
  });

  test('F.1: byok_enabled = true → BYOK regardless of api key', () async {
    // Manual flag set (e.g., via setByokActive). Even with no
    // key in storage at this moment (e.g., user is between
    // toggling on / re-entering a key), the cached entitlement
    // state stays BYOK.
    await settings.setBool('byok_enabled', true);
    final ent = await container.read(entitlementProvider.future);
    expect(ent.state, EntitlementState.byok);
  });

  // ── F.1 setByokActive ─────────────────────────────────────────────

  test('setByokActive(active: true) persists key + flag and emits BYOK',
      () async {
    await container.read(entitlementProvider.future);
    final notifier = container.read(entitlementProvider.notifier);
    // apiKeyProvider must be initialized so save() through the
    // notifier path works.
    await container.read(apiKeyProvider.future);

    await notifier.setByokActive(
      active: true,
      apiKey: 'sk-ant-${'a' * 40}',
    );

    expect(
      container.read(entitlementProvider).value!.state,
      EntitlementState.byok,
    );
    expect(await settings.getBool('byok_enabled'), isTrue);
    expect(await keyStorage.read(), 'sk-ant-${'a' * 40}');
  });

  test('setByokActive(active: false) clears the key + flag and emits '
      'freeAnonymous', () async {
    // Start in BYOK with a stored key.
    await keyStorage.write('sk-ant-${'a' * 40}');
    await settings.setBool('byok_enabled', true);
    // Re-create container so build() picks up the BYOK state.
    container.dispose();
    container = freshContainer();
    await container.read(apiKeyProvider.future);
    final notifier = container.read(entitlementProvider.notifier);
    await container.read(entitlementProvider.future);

    await notifier.setByokActive(active: false);

    expect(
      container.read(entitlementProvider).value!.state,
      EntitlementState.freeAnonymous,
    );
    expect(await settings.getBool('byok_enabled'), isFalse);
    expect(await keyStorage.read(), isNull);
  });

  test('setByokActive(active: true) without an apiKey throws ArgumentError',
      () async {
    await container.read(entitlementProvider.future);
    final notifier = container.read(entitlementProvider.notifier);
    expect(
      () => notifier.setByokActive(active: true),
      throwsA(isA<ArgumentError>()),
    );
  });
}

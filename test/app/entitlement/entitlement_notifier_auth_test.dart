import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/auth/app_auth_session.dart';
import 'package:petpal/app/auth/auth_gateway.dart';
import 'package:petpal/app/auth/auth_session_notifier.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/app/entitlement/entitlement_notifier.dart';
import 'package:petpal/app/entitlement/supabase_entitlements_client.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/app/sync/supabase_runtime_config.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/platform/settings_storage.dart';

import '../../_helpers/fake_api_key_storage.dart';

/// Phase 7 task H.1.c.2 — auth-aware EntitlementNotifier.build path.
///
/// Validates the new contract: when signed in + Supabase config
/// available + BYOK off, the notifier fetches the canonical row
/// from `/rest/v1/entitlements`. On failure, falls back to local
/// cache. BYOK precedence + signed-out paths preserved from F.1.
void main() {
  late AppDatabase db;
  late InMemorySettingsStorage settings;
  late FakeApiKeyStorage keyStorage;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = InMemorySettingsStorage();
    keyStorage = FakeApiKeyStorage();
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer makeContainer({
    AppAuthSession? initialSession,
    SupabaseRuntimeConfig? config,
    EntitlementsClient? client,
  }) {
    final gateway = InMemoryAuthGateway(initial: initialSession);
    return ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async {
          ref.onDispose(() async {});
          return db;
        }),
        settingsStorageProvider.overrideWithValue(settings),
        apiKeyStorageProvider.overrideWithValue(keyStorage),
        authGatewayProvider.overrideWithValue(gateway),
        if (config != null)
          supabaseRuntimeConfigProvider.overrideWithValue(config),
        if (client != null)
          entitlementsClientProvider.overrideWithValue(client),
      ],
    );
  }

  AppAuthSession session({String userId = 'u-1'}) => AppAuthSession(
        userId: userId,
        email: 'a@b.com',
        accessToken: 'jwt',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

  group('BYOK precedence', () {
    test('BYOK flag wins over auth — no fetch even when signed in',
        () async {
      await settings.setBool('byok_enabled', true);
      final fake = FakeEntitlementsClient();
      final container = makeContainer(
        initialSession: session(),
        config: _config(),
        client: fake,
      );
      addTearDown(container.dispose);

      final ent = await container.read(entitlementProvider.future);

      expect(ent.state, EntitlementState.byok);
      expect(fake.fetchCount, 0,
          reason: 'BYOK precedence — server fetch must NOT happen.');
    });
  });

  group('Signed out / no config — anonymous default', () {
    test('signed out + config set → freeAnonymous (no fetch)', () async {
      final fake = FakeEntitlementsClient()..scriptRow(_proRow());
      final container = makeContainer(
        config: _config(),
        client: fake,
      );
      addTearDown(container.dispose);

      final ent = await container.read(entitlementProvider.future);

      expect(ent.state, EntitlementState.freeAnonymous);
      expect(fake.fetchCount, 0,
          reason: 'No userId → no fetch. Pro signal in fake row '
              'must be ignored without a session.');
    });

    test('signed in + config absent → freeAnonymous', () async {
      final fake = FakeEntitlementsClient()..scriptRow(_proRow());
      final container = makeContainer(
        initialSession: session(),
        // config: null intentionally
        client: fake,
      );
      addTearDown(container.dispose);

      final ent = await container.read(entitlementProvider.future);
      expect(ent.state, EntitlementState.freeAnonymous);
    });
  });

  group('Signed in + config — auth-aware fetch', () {
    test('happy path — server row becomes the emitted entitlement',
        () async {
      final pro = _proRow();
      final fake = FakeEntitlementsClient()..scriptRow(pro);
      final container = makeContainer(
        initialSession: session(userId: 'u-pro'),
        config: _config(),
        client: fake,
      );
      addTearDown(container.dispose);

      final ent = await container.read(entitlementProvider.future);

      expect(ent.state, EntitlementState.proMonthly);
      expect(ent.userId, 'u-pro');
      expect(fake.fetchCount, 1);
      expect(fake.lastFetchedUserId, 'u-pro');
    });

    test('happy path — fetched row upserts into the local cache',
        () async {
      final pro = _proRow();
      final fake = FakeEntitlementsClient()..scriptRow(pro);
      final container = makeContainer(
        initialSession: session(userId: 'u-cached'),
        config: _config(),
        client: fake,
      );
      addTearDown(container.dispose);

      await container.read(entitlementProvider.future);

      final repo = await container.read(entitlementRepoProvider.future);
      final cached = await repo.read('u-cached');
      expect(cached, isNotNull);
      expect(cached!.state, EntitlementState.proMonthly);
    });

    test('server returns null → free signed-in default (NOT freeAnonymous)',
        () async {
      final fake = FakeEntitlementsClient()..scriptRow(null);
      final container = makeContainer(
        initialSession: session(userId: 'u-newbie'),
        config: _config(),
        client: fake,
      );
      addTearDown(container.dispose);

      final ent = await container.read(entitlementProvider.future);

      expect(ent.state, EntitlementState.free,
          reason: 'New signed-in user pre-webhook → free signed-in '
              'with userId attribution, not anonymous.');
      expect(ent.userId, 'u-newbie');
    });

    test('owned care pack skill IDs from local cache merge into '
        'fetched server row', () async {
      // Server row has no ownership data (server schema v1 lacks
      // the column — play-billing-verify Edge Function will mirror
      // it in a later commit per row 78).
      final fake = FakeEntitlementsClient()
        ..scriptRow(_proRow(userId: 'u-with-pack'));
      final container = makeContainer(
        initialSession: session(userId: 'u-with-pack'),
        config: _config(),
        client: fake,
      );
      addTearDown(container.dispose);

      // Pre-populate the local cache via the repo provider before
      // the notifier reads — same pattern as the canonical
      // entitlement_notifier_test.dart helpers.
      final repo = await container.read(entitlementRepoProvider.future);
      await repo.upsert(Entitlement(
        state: EntitlementState.proMonthly,
        userId: 'u-with-pack',
        counterPeriodStart: DateTime(2026, 5),
        ownedCarePackSkillIds: const {'reactive-dog'},
      ));

      final ent = await container.read(entitlementProvider.future);

      expect(ent.ownedCarePackSkillIds, contains('reactive-dog'),
          reason: 'Local-only care-pack ownership must survive a '
              'server fetch — without the merge, sign-in would '
              'silently drop purchased care packs.');
    });
  });

  group('Failure / fallback semantics', () {
    test('server failure + cache exists → emits cached value', () async {
      // Server fetch fails.
      final fake = FakeEntitlementsClient()
        ..scriptError(const EntitlementsClientException('500'));
      final container = makeContainer(
        initialSession: session(userId: 'u-cached'),
        config: _config(),
        client: fake,
      );
      addTearDown(container.dispose);

      // Pre-populate cache before the notifier reads.
      final repo = await container.read(entitlementRepoProvider.future);
      await repo.upsert(Entitlement(
        state: EntitlementState.proMonthly,
        userId: 'u-cached',
        counterPeriodStart: DateTime(2026, 5),
        photoCreditsBalance: 99,
      ));

      final ent = await container.read(entitlementProvider.future);

      expect(ent.state, EntitlementState.proMonthly,
          reason: 'Cached state must be preserved on server failure '
              '— no entitlement loss on transient backend issues.');
      expect(ent.photoCreditsBalance, 99);
    });

    test('server failure + no cache → free signed-in (NOT freeAnonymous)',
        () async {
      final fake = FakeEntitlementsClient()
        ..scriptError(const EntitlementsClientException('network'));
      final container = makeContainer(
        initialSession: session(userId: 'u-fresh'),
        config: _config(),
        client: fake,
      );
      addTearDown(container.dispose);

      final ent = await container.read(entitlementProvider.future);

      expect(ent.state, EntitlementState.free);
      expect(ent.userId, 'u-fresh');
    });
  });

  group('Auth state transitions trigger refetch', () {
    test('sign-in transition (null → userId) re-runs build + fetches',
        () async {
      final gateway = InMemoryAuthGateway();
      final fake = FakeEntitlementsClient()..scriptRow(_proRow());
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) async {
          ref.onDispose(() async {});
          return db;
        }),
        settingsStorageProvider.overrideWithValue(settings),
        apiKeyStorageProvider.overrideWithValue(keyStorage),
        authGatewayProvider.overrideWithValue(gateway),
        supabaseRuntimeConfigProvider.overrideWithValue(_config()),
        entitlementsClientProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);

      // First read: signed out.
      final ent1 = await container.read(entitlementProvider.future);
      expect(ent1.state, EntitlementState.freeAnonymous);
      expect(fake.fetchCount, 0);

      // Sign in.
      gateway.simulateDeepLinkSignIn(session(userId: 'u-arriving'));
      await Future<void>.delayed(Duration.zero);

      // Second read after auth transition.
      final ent2 = await container.read(entitlementProvider.future);
      expect(ent2.state, EntitlementState.proMonthly);
      expect(fake.fetchCount, 1);
      expect(fake.lastFetchedUserId, 'u-arriving');
    });

    test('sign-out transition (userId → null) returns to freeAnonymous',
        () async {
      final gateway = InMemoryAuthGateway(initial: session());
      final fake = FakeEntitlementsClient()..scriptRow(_proRow());
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) async {
          ref.onDispose(() async {});
          return db;
        }),
        settingsStorageProvider.overrideWithValue(settings),
        apiKeyStorageProvider.overrideWithValue(keyStorage),
        authGatewayProvider.overrideWithValue(gateway),
        supabaseRuntimeConfigProvider.overrideWithValue(_config()),
        entitlementsClientProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);

      final ent1 = await container.read(entitlementProvider.future);
      expect(ent1.state, EntitlementState.proMonthly);

      await gateway.signOut();
      await Future<void>.delayed(Duration.zero);

      final ent2 = await container.read(entitlementProvider.future);
      expect(ent2.state, EntitlementState.freeAnonymous,
          reason: 'Sign-out clears the userId watch + the notifier '
              'rebuilds to anonymous default.');
    });
  });
}

SupabaseRuntimeConfig _config() => const SupabaseRuntimeConfig(
      url: 'https://test.supabase.co',
      anonKey: 'anon-test',
    );

Entitlement _proRow({String userId = 'u-1'}) => Entitlement(
      state: EntitlementState.proMonthly,
      userId: userId,
      renewalDate: DateTime.utc(2026, 6, 15),
      photoCreditsBalance: 0,
      monthlyTextCount: 0,
      monthlyVisionCount: 0,
      counterPeriodStart: DateTime.utc(2026, 5),
      fetchedAt: DateTime.utc(2026, 5, 3),
    );


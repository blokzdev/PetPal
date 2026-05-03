import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/auth/app_auth_session.dart';
import 'package:petpal/app/auth/auth_gateway.dart';
import 'package:petpal/app/auth/auth_session_notifier.dart';
import 'package:petpal/app/sync/supabase_runtime_config.dart';
import 'package:petpal/app/sync/sync_providers.dart';
import 'package:petpal/data/sync/supabase_sync_backend.dart';
import 'package:petpal/data/sync/sync_backend.dart';

/// Phase 7 task H.1.b — provider-graph conditional wiring tests.
///
/// Verifies the load-bearing branching in `syncBackendProvider`:
///   - no Supabase config → InMemorySyncBackend(unauthenticated)
///   - config but no auth session → InMemorySyncBackend(unauthenticated)
///   - config + signed-in session → SupabaseSyncBackend
///
/// The full HTTP wire-format coverage lives in
/// `supabase_sync_backend_test.dart`; these tests only exercise
/// the provider's conditional branching.
void main() {
  group('syncBackendProvider — conditional backend selection', () {
    test('returns InMemorySyncBackend when no Supabase config', () async {
      final container = ProviderContainer(overrides: [
        // No supabaseRuntimeConfigProvider override → default null.
        authGatewayProvider
            .overrideWithValue(InMemoryAuthGateway(initial: _session())),
      ]);
      addTearDown(container.dispose);

      // Drive the auth session into "signed-in" state.
      await container.read(authSessionProvider.future);

      final backend = container.read(syncBackendProvider);
      expect(backend, isA<InMemorySyncBackend>());
      expect(backend.isAuthenticated, isFalse);
    });

    test('returns InMemorySyncBackend when config set but signed out',
        () async {
      final container = ProviderContainer(overrides: [
        supabaseRuntimeConfigProvider.overrideWithValue(_config()),
        authGatewayProvider.overrideWithValue(InMemoryAuthGateway()),
      ]);
      addTearDown(container.dispose);

      await container.read(authSessionProvider.future);

      final backend = container.read(syncBackendProvider);
      expect(backend, isA<InMemorySyncBackend>());
      expect(backend.isAuthenticated, isFalse);
    });

    test('returns SupabaseSyncBackend when config + session both set',
        () async {
      final container = ProviderContainer(overrides: [
        supabaseRuntimeConfigProvider.overrideWithValue(_config()),
        authGatewayProvider
            .overrideWithValue(InMemoryAuthGateway(initial: _session())),
      ]);
      addTearDown(container.dispose);

      await container.read(authSessionProvider.future);

      final backend = container.read(syncBackendProvider);
      expect(backend, isA<SupabaseSyncBackend>());
      expect(backend.isAuthenticated, isTrue,
          reason: 'JWT closure reads accessToken from the auth session, '
              'which is non-empty for the seeded session.');
    });

    test('flips to SupabaseSyncBackend after deep-link sign-in', () async {
      final gateway = InMemoryAuthGateway();
      final container = ProviderContainer(overrides: [
        supabaseRuntimeConfigProvider.overrideWithValue(_config()),
        authGatewayProvider.overrideWithValue(gateway),
      ]);
      addTearDown(container.dispose);

      await container.read(authSessionProvider.future);
      expect(container.read(syncBackendProvider), isA<InMemorySyncBackend>());

      gateway.simulateDeepLinkSignIn(_session());
      await Future<void>.delayed(Duration.zero);

      expect(container.read(syncBackendProvider), isA<SupabaseSyncBackend>(),
          reason: 'Provider must rebuild when authSessionProvider '
              'transitions from null to signed-in.');
    });

    test('flips back to InMemorySyncBackend on sign-out', () async {
      final gateway = InMemoryAuthGateway(initial: _session());
      final container = ProviderContainer(overrides: [
        supabaseRuntimeConfigProvider.overrideWithValue(_config()),
        authGatewayProvider.overrideWithValue(gateway),
      ]);
      addTearDown(container.dispose);

      await container.read(authSessionProvider.future);
      expect(container.read(syncBackendProvider), isA<SupabaseSyncBackend>());

      await gateway.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(syncBackendProvider), isA<InMemorySyncBackend>(),
          reason: 'Sign-out must drop the production backend so the '
              'sync card returns to signedOut UI state.');
    });
  });
}

SupabaseRuntimeConfig _config() => const SupabaseRuntimeConfig(
      url: 'https://abcdef.supabase.co',
      anonKey: 'anon-stub',
    );

AppAuthSession _session() => AppAuthSession(
      userId: '00000000-0000-0000-0000-000000000aaa',
      email: 'a@b.com',
      accessToken: 'jwt-stub',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

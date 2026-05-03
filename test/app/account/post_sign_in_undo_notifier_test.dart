import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/account/account_deletion_client.dart';
import 'package:petpal/app/account/post_sign_in_undo_notifier.dart';
import 'package:petpal/app/auth/app_auth_session.dart';
import 'package:petpal/app/auth/auth_gateway.dart';
import 'package:petpal/app/auth/auth_session_notifier.dart';

/// Phase 7 task H.1.d.undo — post-sign-in undo notifier tests.

void main() {
  AppAuthSession session(String userId) => AppAuthSession(
        userId: userId,
        email: '$userId@example.com',
        accessToken: 'jwt-$userId',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

  ProviderContainer makeContainer({
    required InMemoryAuthGateway gateway,
    required FakeAccountDeletionClient client,
  }) {
    final container = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWithValue(gateway),
        accountDeletionClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('starts idle', () async {
    final gateway = InMemoryAuthGateway();
    final client = FakeAccountDeletionClient();
    final container = makeContainer(gateway: gateway, client: client);

    final state = container.read(postSignInUndoProvider);
    expect(state, isA<PostSignInUndoIdle>());
  });

  test('sign-in with no pending deletion stays idle', () async {
    final gateway = InMemoryAuthGateway();
    final client = FakeAccountDeletionClient();
    final container = makeContainer(gateway: gateway, client: client);

    // Eagerly subscribe so the notifier wires its ref.listen.
    container.read(postSignInUndoProvider);
    // Also need authSessionProvider to materialize so the listener
    // attaches.
    await container.read(authSessionProvider.future);

    gateway.simulateDeepLinkSignIn(session('user-a'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(client.cancelCallCount, 1);
    expect(container.read(postSignInUndoProvider), isA<PostSignInUndoIdle>());
  });

  test('sign-in with pending deletion → state becomes Cancelled', () async {
    final gateway = InMemoryAuthGateway();
    final client = FakeAccountDeletionClient(wasPending: true);
    final container = makeContainer(gateway: gateway, client: client);

    container.read(postSignInUndoProvider);
    await container.read(authSessionProvider.future);

    gateway.simulateDeepLinkSignIn(session('user-a'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(postSignInUndoProvider);
    expect(state, isA<PostSignInUndoCancelled>());
    expect((state as PostSignInUndoCancelled).eventId, 1);
    expect(client.cancelCallCount, 1);
  });

  test('acknowledge() resets back to idle', () async {
    final gateway = InMemoryAuthGateway();
    final client = FakeAccountDeletionClient(wasPending: true);
    final container = makeContainer(gateway: gateway, client: client);

    container.read(postSignInUndoProvider);
    await container.read(authSessionProvider.future);

    gateway.simulateDeepLinkSignIn(session('user-a'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(postSignInUndoProvider),
        isA<PostSignInUndoCancelled>());

    container.read(postSignInUndoProvider.notifier).acknowledge();
    expect(container.read(postSignInUndoProvider), isA<PostSignInUndoIdle>());
  });

  test('same-user re-emit (e.g. token refresh) does NOT refire cancel',
      () async {
    final gateway = InMemoryAuthGateway();
    final client = FakeAccountDeletionClient(wasPending: true);
    final container = makeContainer(gateway: gateway, client: client);

    container.read(postSignInUndoProvider);
    await container.read(authSessionProvider.future);

    gateway.simulateDeepLinkSignIn(session('user-a'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(client.cancelCallCount, 1);

    // Token refresh → same userId emitted again.
    gateway.simulateDeepLinkSignIn(session('user-a'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(client.cancelCallCount, 1, reason: 'must not refire');
  });

  test('signing out then in as a different user fires cancel again',
      () async {
    final gateway = InMemoryAuthGateway();
    final client = FakeAccountDeletionClient(wasPending: true);
    final container = makeContainer(gateway: gateway, client: client);

    container.read(postSignInUndoProvider);
    await container.read(authSessionProvider.future);

    gateway.simulateDeepLinkSignIn(session('user-a'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(client.cancelCallCount, 1);
    container.read(postSignInUndoProvider.notifier).acknowledge();

    gateway.simulateSessionExpired();
    await Future<void>.delayed(Duration.zero);
    expect(client.cancelCallCount, 1);

    gateway.simulateDeepLinkSignIn(session('user-b'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(client.cancelCallCount, 2);
  });

  test('cancel error → state becomes Error (cron-side fallback intact)',
      () async {
    final gateway = InMemoryAuthGateway();
    final client = FakeAccountDeletionClient();
    client.scriptCancelError(const AccountDeletionException('network down'));
    final container = makeContainer(gateway: gateway, client: client);

    container.read(postSignInUndoProvider);
    await container.read(authSessionProvider.future);

    gateway.simulateDeepLinkSignIn(session('user-a'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(postSignInUndoProvider),
        isA<PostSignInUndoError>());
  });

  test('null AccountDeletionClient (Supabase unconfigured) — quiet no-op',
      () async {
    final gateway = InMemoryAuthGateway();
    final container = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWithValue(gateway),
        accountDeletionClientProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);

    container.read(postSignInUndoProvider);
    await container.read(authSessionProvider.future);

    gateway.simulateDeepLinkSignIn(session('user-a'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(postSignInUndoProvider), isA<PostSignInUndoIdle>());
  });
}

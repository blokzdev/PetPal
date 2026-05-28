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
    required AccountDeletionClient client,
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

  // Phase 7 audit fix — cold-start gap.
  // App-restart with a saved session: the auth provider resolves to
  // AsyncData(session) before AppShell mounts and reads the
  // postSignInUndoProvider. With `fireImmediately: true` the listener
  // sees the already-live session on first attach and triggers the
  // cancel call. With the old `fireImmediately: false` this case
  // would silently no-op and the cron-side check would be the only
  // safety net.
  test('cold-start with already-signed-in session + pending deletion → '
      'fires cancel + emits Cancelled', () async {
    final gateway = InMemoryAuthGateway(initial: session('user-a'));
    final client = FakeAccountDeletionClient(wasPending: true);
    final container = makeContainer(gateway: gateway, client: client);

    // Read the provider — this attaches the listener with
    // fireImmediately: true so the existing session is picked up.
    container.read(postSignInUndoProvider);
    // Resolve the auth provider's async build so all microtasks drain.
    await container.read(authSessionProvider.future);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      client.cancelCallCount,
      1,
      reason: 'cold-start session must trigger cancelDeletion',
    );
    expect(
      container.read(postSignInUndoProvider),
      isA<PostSignInUndoCancelled>(),
    );
  });

  // Phase 7 audit fix — disposal safety.
  // The cancel call is async; if the notifier is disposed during the
  // await (test teardown, sign-out cascade, etc.), the post-await
  // `state = ...` would throw "Cannot use 'state' after the Notifier
  // was disposed". The `ref.mounted` guards added in fix 1 short-
  // circuit cleanly instead.
  test('notifier disposed mid-flight → no throw', () async {
    final gateway = InMemoryAuthGateway();
    final completer = Completer<bool>();
    final client = _BlockingDeletionClient(completer);
    final container = makeContainer(gateway: gateway, client: client);

    container.read(postSignInUndoProvider);
    await container.read(authSessionProvider.future);

    // Trigger the sign-in event → cancel call begins + awaits the
    // completer.
    gateway.simulateDeepLinkSignIn(session('user-a'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(client.startedCalls, 1);

    // Dispose the container while the cancel is still in flight.
    container.dispose();

    // Complete the future post-disposal. Without `ref.mounted` guards
    // this would throw — the test passes by simply not throwing.
    completer.complete(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  });
}

/// Fake deletion client whose `cancelDeletion()` blocks on a
/// caller-supplied [Completer]. Used to simulate a cancel call still
/// in flight when the surrounding ProviderContainer is disposed.
class _BlockingDeletionClient implements AccountDeletionClient {
  _BlockingDeletionClient(this._completer);
  final Completer<bool> _completer;
  int startedCalls = 0;

  @override
  Future<DateTime> requestDeletion() async =>
      throw UnimplementedError('not used in disposal-safety test');

  @override
  Future<bool> cancelDeletion() {
    startedCalls++;
    return _completer.future;
  }
}

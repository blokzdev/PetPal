import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/auth/app_auth_session.dart';
import 'package:petpal/app/auth/auth_gateway.dart';
import 'package:petpal/app/auth/auth_session_notifier.dart';

/// Phase 7 task H.1.a — AuthSessionNotifier behaviour tests.
///
/// Validates that the notifier mirrors the gateway's session
/// transitions: deep-link return populates the AsyncData; sign-out
/// emits AsyncData(null); the convenience [isSignedInProvider]
/// derives correctly from both states.
void main() {
  group('AuthSessionNotifier — initial build', () {
    test('returns null when gateway has no session', () async {
      final gateway = InMemoryAuthGateway();
      final container = _container(gateway);
      addTearDown(container.dispose);

      final initial = await container.read(authSessionProvider.future);
      expect(initial, isNull);
      expect(container.read(isSignedInProvider), isFalse);
    });

    test('returns initial session if gateway already has one', () async {
      final session = _session('u-pre');
      final gateway = InMemoryAuthGateway(initial: session);
      final container = _container(gateway);
      addTearDown(container.dispose);

      final initial = await container.read(authSessionProvider.future);
      expect(initial, session);
      expect(container.read(isSignedInProvider), isTrue);
    });
  });

  group('AuthSessionNotifier — gateway stream wiring', () {
    test('deep-link sign-in updates state to AsyncData(session)', () async {
      final gateway = InMemoryAuthGateway();
      final container = _container(gateway);
      addTearDown(container.dispose);

      // Force the notifier to build + subscribe to the stream.
      await container.read(authSessionProvider.future);
      expect(container.read(authSessionProvider).value, isNull);

      final session = _session('u-deeplink', email: 'alice@example.com');
      gateway.simulateDeepLinkSignIn(session);
      // Wait for the broadcast stream to deliver to the notifier.
      await Future<void>.delayed(Duration.zero);

      expect(container.read(authSessionProvider).value, session);
      expect(container.read(isSignedInProvider), isTrue);
    });

    test('signOut transitions state to AsyncData(null)', () async {
      final initial = _session('u-pre');
      final gateway = InMemoryAuthGateway(initial: initial);
      final container = _container(gateway);
      addTearDown(container.dispose);

      await container.read(authSessionProvider.future);
      expect(container.read(authSessionProvider).value, initial);

      await container.read(authSessionProvider.notifier).signOut();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(authSessionProvider).value, isNull);
      expect(container.read(isSignedInProvider), isFalse);
    });
  });

  group('AuthSessionNotifier — sendMagicLink', () {
    test('forwards email + locked redirect URL to the gateway', () async {
      final gateway = InMemoryAuthGateway();
      final container = _container(gateway);
      addTearDown(container.dispose);

      await container.read(authSessionProvider.future);

      await container
          .read(authSessionProvider.notifier)
          .sendMagicLink(email: 'alice@example.com');

      expect(gateway.lastSentEmail, 'alice@example.com');
      expect(
        gateway.lastEmailRedirectTo,
        kMagicLinkRedirectUrl,
        reason: 'Notifier must always pass the locked '
            'petpal://login-callback redirect URL — must match the '
            'AndroidManifest intent filter exactly.',
      );
      expect(gateway.sendMagicLinkCount, 1);
    });

    test('does NOT change session synchronously — waits for deep-link return',
        () async {
      final gateway = InMemoryAuthGateway();
      final container = _container(gateway);
      addTearDown(container.dispose);

      await container.read(authSessionProvider.future);

      await container
          .read(authSessionProvider.notifier)
          .sendMagicLink(email: 'alice@example.com');
      await Future<void>.delayed(Duration.zero);

      expect(container.read(authSessionProvider).value, isNull,
          reason: 'sendMagicLink must NOT optimistically install a '
              'session — only the gateway stream event from deep-link '
              'return drives state change.');
    });

    test('propagates gateway exceptions to the caller', () async {
      final gateway = InMemoryAuthGateway();
      const err = AuthGatewayException('network unreachable');
      gateway.scriptSendError(err);
      final container = _container(gateway);
      addTearDown(container.dispose);

      await container.read(authSessionProvider.future);

      await expectLater(
        () => container
            .read(authSessionProvider.notifier)
            .sendMagicLink(email: 'alice@example.com'),
        throwsA(same(err)),
      );
    });
  });

  group('kMagicLinkRedirectUrl', () {
    test('matches the AndroidManifest intent-filter scheme + host', () {
      // Locked literal — if you change one, you must change the other
      // in the same commit. The android_manifest_test.dart pins the
      // manifest side; this test pins the Dart side.
      expect(kMagicLinkRedirectUrl, 'petpal://login-callback');
    });
  });
}

ProviderContainer _container(InMemoryAuthGateway gateway) {
  return ProviderContainer(
    overrides: [authGatewayProvider.overrideWithValue(gateway)],
  );
}

AppAuthSession _session(String userId, {String? email}) => AppAuthSession(
      userId: userId,
      email: email,
      accessToken: 'tok-$userId',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

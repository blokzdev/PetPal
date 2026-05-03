import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/auth/app_auth_session.dart';
import 'package:petpal/app/auth/auth_gateway.dart';

/// Phase 7 task H.1.a — InMemoryAuthGateway behaviour tests.
///
/// Validates the test fake's contract so screens + the
/// AuthSessionNotifier can rely on the documented semantics:
///   - sendMagicLink without a scripted accept does NOT change the
///     session (matches production: user must tap the link)
///   - sendMagicLink WITH a scripted accept installs the session
///     and fires the stream event in one go (happy-path harness)
///   - simulateDeepLinkSignIn drives an explicit return without
///     going through sendMagicLink (lets tests time the deep-link
///     return precisely)
///   - signOut is idempotent + clears the session + emits null
///   - error scripting throws on the next send call only
void main() {
  group('InMemoryAuthGateway — initial state', () {
    test('no initial session by default', () {
      final gateway = InMemoryAuthGateway();
      expect(gateway.currentSession, isNull);
      gateway.dispose();
    });

    test('honours initial session passed to constructor', () {
      final initial = _session('u-init');
      final gateway = InMemoryAuthGateway(initial: initial);
      expect(gateway.currentSession, initial);
      gateway.dispose();
    });
  });

  group('InMemoryAuthGateway — sendMagicLink', () {
    test('queues the email but does NOT install a session by default',
        () async {
      final gateway = InMemoryAuthGateway();
      await gateway.sendMagicLink(
        email: 'a@b.com',
        emailRedirectTo: 'petpal://login-callback',
      );
      expect(gateway.currentSession, isNull,
          reason: 'No session should appear until the user taps '
              'the link (or scriptMagicLinkAccept is called).');
      expect(gateway.lastSentEmail, 'a@b.com');
      expect(gateway.lastEmailRedirectTo, 'petpal://login-callback');
      expect(gateway.sendMagicLinkCount, 1);
      await gateway.dispose();
    });

    test('installs scripted session + fires onSessionChange', () async {
      final gateway = InMemoryAuthGateway();
      final scripted = _session('u-scripted', email: 'a@b.com');
      gateway.scriptMagicLinkAccept(scripted);

      final emissions = <AppAuthSession?>[];
      final sub = gateway.onSessionChange.listen(emissions.add);

      await gateway.sendMagicLink(
        email: 'a@b.com',
        emailRedirectTo: 'petpal://login-callback',
      );

      // Wait one microtask for the broadcast stream to deliver.
      await Future<void>.delayed(Duration.zero);

      expect(gateway.currentSession, scripted);
      expect(emissions, [scripted]);

      await sub.cancel();
      await gateway.dispose();
    });

    test('scripted accept fires once — second send returns to default',
        () async {
      final gateway = InMemoryAuthGateway();
      gateway.scriptMagicLinkAccept(_session('u-once'));

      await gateway.sendMagicLink(
        email: 'a@b.com',
        emailRedirectTo: 'petpal://login-callback',
      );
      expect(gateway.currentSession?.userId, 'u-once');

      await gateway.signOut();
      await gateway.sendMagicLink(
        email: 'a@b.com',
        emailRedirectTo: 'petpal://login-callback',
      );
      expect(gateway.currentSession, isNull,
          reason: 'Without re-scripting, the second send should not '
              'install a session.');

      await gateway.dispose();
    });

    test('scripted error throws + clears for next call', () async {
      final gateway = InMemoryAuthGateway();
      const err = AuthGatewayException('rate-limited');
      gateway.scriptSendError(err);

      expect(
        () => gateway.sendMagicLink(
          email: 'a@b.com',
          emailRedirectTo: 'petpal://login-callback',
        ),
        throwsA(same(err)),
      );

      // Next call succeeds.
      await gateway.sendMagicLink(
        email: 'a@b.com',
        emailRedirectTo: 'petpal://login-callback',
      );
      expect(gateway.sendMagicLinkCount, 2);
      await gateway.dispose();
    });
  });

  group('InMemoryAuthGateway — simulateDeepLinkSignIn', () {
    test('installs session + fires stream WITHOUT going through send',
        () async {
      final gateway = InMemoryAuthGateway();
      final session = _session('u-deeplink');

      final emissions = <AppAuthSession?>[];
      final sub = gateway.onSessionChange.listen(emissions.add);

      gateway.simulateDeepLinkSignIn(session);
      await Future<void>.delayed(Duration.zero);

      expect(gateway.currentSession, session);
      expect(emissions, [session]);
      expect(gateway.sendMagicLinkCount, 0,
          reason: 'simulateDeepLinkSignIn does not count as a send.');

      await sub.cancel();
      await gateway.dispose();
    });

    test('simulateSessionExpired drops session + emits null', () async {
      final initial = _session('u-init');
      final gateway = InMemoryAuthGateway(initial: initial);

      final emissions = <AppAuthSession?>[];
      final sub = gateway.onSessionChange.listen(emissions.add);

      gateway.simulateSessionExpired();
      await Future<void>.delayed(Duration.zero);

      expect(gateway.currentSession, isNull);
      expect(emissions, [null]);

      await sub.cancel();
      await gateway.dispose();
    });
  });

  group('InMemoryAuthGateway — signOut', () {
    test('clears session + emits null', () async {
      final gateway = InMemoryAuthGateway(initial: _session('u-init'));

      final emissions = <AppAuthSession?>[];
      final sub = gateway.onSessionChange.listen(emissions.add);

      await gateway.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(gateway.currentSession, isNull);
      expect(emissions, [null]);

      await sub.cancel();
      await gateway.dispose();
    });

    test('idempotent — no-op + no extra emission when already signed out',
        () async {
      final gateway = InMemoryAuthGateway();
      final emissions = <AppAuthSession?>[];
      final sub = gateway.onSessionChange.listen(emissions.add);

      await gateway.signOut();
      await gateway.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(emissions, isEmpty,
          reason: 'No emission expected for sign-out from null state.');

      await sub.cancel();
      await gateway.dispose();
    });
  });

  group('AppAuthSession — value semantics', () {
    test('equal when all fields match', () {
      final a = _session('u');
      final b = _session('u');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('unequal when userId differs', () {
      expect(_session('u1'), isNot(_session('u2')));
    });

    test('isExpired reflects clock', () {
      final past = AppAuthSession(
        userId: 'u',
        email: 'a@b.com',
        accessToken: 't',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      final future = AppAuthSession(
        userId: 'u',
        email: 'a@b.com',
        accessToken: 't',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(past.isExpired, isTrue);
      expect(future.isExpired, isFalse);
    });
  });
}

AppAuthSession _session(String userId, {String? email}) => AppAuthSession(
      userId: userId,
      email: email,
      accessToken: 'tok-$userId',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

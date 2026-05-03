import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/auth/app_auth_session.dart';
import 'package:petpal/app/auth/auth_gateway.dart';
import 'package:petpal/app/auth/auth_session_notifier.dart';
import 'package:petpal/app/screens/sign_in_screen.dart';

/// Phase 7 task H.1.c — sign-in screen widget tests.
///
/// Drives the screen through every UX state — entry, send, confirmation,
/// error, deep-link return — using the InMemoryAuthGateway from H.1.a's
/// auth scaffold so no real Supabase is needed.
void main() {
  Widget _harness({required InMemoryAuthGateway gateway}) {
    return ProviderScope(
      overrides: [
        authGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(home: SignInScreen()),
    );
  }

  group('Entry state', () {
    testWidgets('renders email field + disabled Send button initially',
        (tester) async {
      final gateway = InMemoryAuthGateway();
      await tester.pumpWidget(_harness(gateway: gateway));
      await tester.pump();

      expect(find.text('Sign in to PetPal'), findsOneWidget);
      expect(find.text('Send sign-in link'), findsOneWidget);
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason: 'Email field should render in entry state.',
      );

      // Send button starts disabled (no email yet).
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Send sign-in link'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Send button enables for valid email', (tester) async {
      final gateway = InMemoryAuthGateway();
      await tester.pumpWidget(_harness(gateway: gateway));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'alice@example.com');
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Send sign-in link'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('Send button stays disabled for malformed email',
        (tester) async {
      final gateway = InMemoryAuthGateway();
      await tester.pumpWidget(_harness(gateway: gateway));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'not-an-email');
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Send sign-in link'),
      );
      expect(button.onPressed, isNull,
          reason: 'Malformed email should keep Send disabled.');
    });

    testWidgets('renders privacy disclosure on the entry screen',
        (tester) async {
      final gateway = InMemoryAuthGateway();
      await tester.pumpWidget(_harness(gateway: gateway));
      await tester.pump();

      expect(
        find.textContaining('end-to-end encrypted'),
        findsOneWidget,
        reason: 'Privacy disclosure card must surface the E2EE '
            'reassurance — VOICE.md §6 example 18 lock.',
      );
    });
  });

  group('Send → confirmation transition', () {
    testWidgets('Sending forwards to gateway with locked redirect URL',
        (tester) async {
      final gateway = InMemoryAuthGateway();
      await tester.pumpWidget(_harness(gateway: gateway));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'alice@example.com');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Send sign-in link'),
      );
      await tester.pump(); // start
      await tester.pump(); // after-await rebuild

      expect(gateway.lastSentEmail, 'alice@example.com');
      expect(gateway.lastEmailRedirectTo, kMagicLinkRedirectUrl);
    });

    testWidgets('Successful send transitions to confirmation state',
        (tester) async {
      final gateway = InMemoryAuthGateway();
      await tester.pumpWidget(_harness(gateway: gateway));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'alice@example.com');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Send sign-in link'),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Check your inbox'), findsOneWidget);
      expect(
        find.textContaining('alice@example.com'),
        findsWidgets,
        reason: 'Confirmation must echo the address the link went to.',
      );
      expect(
        find.text('Try a different email'),
        findsOneWidget,
        reason: 'Recovery affordance must be reachable from confirmation.',
      );
    });

    testWidgets('Try a different email returns to entry state',
        (tester) async {
      final gateway = InMemoryAuthGateway();
      await tester.pumpWidget(_harness(gateway: gateway));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'alice@example.com');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Send sign-in link'),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Check your inbox'), findsOneWidget);

      await tester.tap(find.text('Try a different email'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Check your inbox'), findsNothing);
      expect(find.text('Send sign-in link'), findsOneWidget,
          reason: 'Should be back on the entry screen.');
    });
  });

  group('Error path', () {
    testWidgets('Gateway exception surfaces an inline error banner',
        (tester) async {
      final gateway = InMemoryAuthGateway();
      gateway.scriptSendError(
        const AuthGatewayException('email rate limit exceeded'),
      );
      await tester.pumpWidget(_harness(gateway: gateway));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'alice@example.com');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Send sign-in link'),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('rate limit'), findsOneWidget);
      // Stays on the entry screen so the user can fix + retry.
      expect(find.text('Send sign-in link'), findsOneWidget);
      expect(find.text('Check your inbox'), findsNothing);
    });
  });

  group('Deep-link return → auto-pop', () {
    testWidgets('Pops itself when authSessionProvider transitions to signed in',
        (tester) async {
      final gateway = InMemoryAuthGateway();
      var didPop = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authGatewayProvider.overrideWithValue(gateway)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SignInScreen(),
                    ),
                  ).then((_) => didPop = true),
                  child: const Text('Open sign-in'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Open the sign-in screen.
      await tester.tap(find.text('Open sign-in'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to PetPal'), findsOneWidget);

      // Simulate the deep-link return — this is what supabase_flutter's
      // app_links integration does in production after the magic-link
      // tap.
      gateway.simulateDeepLinkSignIn(
        AppAuthSession(
          userId: 'u-1',
          email: 'alice@example.com',
          accessToken: 'jwt',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      await tester.pumpAndSettle();

      expect(didPop, isTrue,
          reason: 'Sign-in screen must pop itself once the auth '
              'session populates — otherwise the user lands on a '
              "stale 'Check your inbox' screen after sign-in completes.");
    });
  });
}

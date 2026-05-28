import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/account/account_deletion_client.dart';
import 'package:petpal/app/account/local_data_wipe.dart';
import 'package:petpal/app/auth/app_auth_session.dart';
import 'package:petpal/app/auth/auth_gateway.dart';
import 'package:petpal/app/auth/auth_session_notifier.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/app/screens/delete_account_screen.dart';
import 'package:petpal/data/wiki_io.dart';

/// Phase 7 task H.1.d — DeleteAccountScreen widget tests.
///
/// Drives the disclosure + typed-confirmation gate + cascade
/// transitions using the FakeAccountDeletionClient + InMemoryAuthGateway
/// test fakes, so no network plumbing is needed.
void main() {
  Widget harness({
    required FakeAccountDeletionClient client,
    InMemoryAuthGateway? gateway,
  }) {
    final g = gateway ??
        InMemoryAuthGateway(
          initial: AppAuthSession(
            userId: 'u-1',
            email: 'a@b.com',
            accessToken: 'jwt',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
    return ProviderScope(
      overrides: [
        accountDeletionClientProvider.overrideWithValue(client),
        authGatewayProvider.overrideWithValue(g),
        // The success path wipes local data + reads wikiIo; fake both
        // so it doesn't reach platform channels (path_provider) that
        // hang in the test harness.
        wikiIoProvider.overrideWith((ref) async => _NoopWiki()),
        localDataWipeProvider.overrideWithValue(
          LocalDataWipe(deleteDriftFile: () async {}),
        ),
      ],
      child: const MaterialApp(home: DeleteAccountScreen()),
    );
  }

  group('Disclosure rendering', () {
    testWidgets('renders all five Option (e) disclosure items',
        (tester) async {
      final client = FakeAccountDeletionClient();
      await tester.pumpWidget(harness(client: client));
      await tester.pump();

      // Match keywords from each disclosure item (DECISIONS row 77 +
      // VOICE.md §6 example 20). Don't pin full sentences — copy may
      // tighten in future passes.
      expect(find.textContaining('on this device'), findsOneWidget);
      expect(find.textContaining('servers is deleted within 30 days'),
          findsOneWidget);
      expect(find.textContaining('Google Play'), findsOneWidget);
      expect(find.textContaining('passphrase'), findsOneWidget);
      expect(find.textContaining('AI chat usage'), findsOneWidget);
    });

    testWidgets('exposes the inline export-first affordance',
        (tester) async {
      final client = FakeAccountDeletionClient();
      await tester.pumpWidget(harness(client: client));
      await tester.pump();

      expect(find.text('Export to ZIP'), findsOneWidget,
          reason: 'Export must be inline as a choice, not a forced step.');
    });
  });

  group('Typed-confirmation gate', () {
    testWidgets('Delete button disabled until DELETE is typed',
        (tester) async {
      final client = FakeAccountDeletionClient();
      await tester.pumpWidget(harness(client: client));
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete account'),
      );
      expect(button.onPressed, isNull,
          reason: 'Button must start disabled — typed gate not satisfied.');
    });

    testWidgets('Typing DELETE enables the button', (tester) async {
      final client = FakeAccountDeletionClient();
      await tester.pumpWidget(harness(client: client));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete account'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('lowercase input is uppercased by the formatter',
        (tester) async {
      final client = FakeAccountDeletionClient();
      await tester.pumpWidget(harness(client: client));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'delete');
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete account'),
      );
      expect(button.onPressed, isNotNull,
          reason: 'Caps-lock state must not block the user — formatter '
              'uppercases input as it arrives.');
    });

    testWidgets('partial input keeps the button disabled', (tester) async {
      final client = FakeAccountDeletionClient();
      await tester.pumpWidget(harness(client: client));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'DEL');
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete account'),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('Cascade transitions', () {
    testWidgets('Successful deletion transitions to the success state',
        (tester) async {
      final retention = DateTime.utc(2026, 6, 2);
      final client = FakeAccountDeletionClient(retentionEnd: retention);
      await tester.pumpWidget(harness(client: client));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Delete account'),
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Delete account'),
      );
      await tester.pumpAndSettle();

      expect(client.callCount, 1);
      expect(
        find.text('Your account is scheduled for deletion'),
        findsOneWidget,
      );
      expect(
        find.text('Back to PetPal'),
        findsOneWidget,
        reason: 'Success state must surface a path forward.',
      );
    });

    testWidgets('Server failure surfaces inline error + leaves cascade '
        'reachable for retry', (tester) async {
      final client = FakeAccountDeletionClient()
        ..scriptError(
          const AccountDeletionException('temporary outage'),
        );
      await tester.pumpWidget(harness(client: client));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Delete account'),
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Delete account'),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('temporary outage'), findsOneWidget);
      // User stays on the form, can re-tap Delete after the server
      // recovers.
      expect(
        find.text('Your account is scheduled for deletion'),
        findsNothing,
      );
      expect(
        find.widgetWithText(FilledButton, 'Delete account'),
        findsOneWidget,
      );
    });

    testWidgets('Cancel pops the screen', (tester) async {
      final client = FakeAccountDeletionClient();
      var popped = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountDeletionClientProvider.overrideWithValue(client),
            authGatewayProvider.overrideWithValue(
              InMemoryAuthGateway(
                initial: AppAuthSession(
                  userId: 'u-1',
                  email: 'a@b.com',
                  accessToken: 'jwt',
                  expiresAt:
                      DateTime.now().add(const Duration(hours: 1)),
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DeleteAccountScreen(),
                    ),
                  ).then((_) => popped = true),
                  child: const Text('Open delete'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete your PetPal account'), findsOneWidget);

      await tester.ensureVisible(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(popped, isTrue);
      expect(client.callCount, 0,
          reason: 'Cancel must NOT trigger the deletion call.');
    });

    testWidgets('No-op when client provider is null (Supabase not '
        'configured)', (tester) async {
      // No accountDeletionClientProvider override → null.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authGatewayProvider.overrideWithValue(
              InMemoryAuthGateway(
                initial: AppAuthSession(
                  userId: 'u-1',
                  email: 'a@b.com',
                  accessToken: 'jwt',
                  expiresAt:
                      DateTime.now().add(const Duration(hours: 1)),
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: DeleteAccountScreen()),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Delete account'),
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Delete account'),
      );
      await tester.pump();
      await tester.pump();

      // Surfaces the dev-build error path.
      expect(
        find.textContaining('cannot reach the server'),
        findsOneWidget,
      );
    });
  });
}

class _NoopWiki implements WikiIo {
  @override
  Future<void> writeAtomic(String relPath, String body) async {}
  @override
  Future<String> read(String relPath) async => '';
  @override
  Future<List<String>> listForPet(int petId) async => const [];
  @override
  String petDir(int petId) => 'wiki/$petId';
  @override
  String soulPath(int petId) => 'wiki/$petId/SOUL.md';
  @override
  Future<void> writeBytesAtomic(String relPath, Uint8List bytes) async {}
  @override
  Future<Uint8List> readBytes(String relPath) async => Uint8List(0);
  @override
  Future<void> deleteIfExists(String relPath) async {}
  @override
  Future<int> bytesForPet(int petId) async => 0;
  @override
  Future<void> deleteAll() async {}
}

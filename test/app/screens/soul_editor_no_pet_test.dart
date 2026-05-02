import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/app/widgets/pet_empty_state.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/main.dart';

import '../../_helpers/fake_api_key_storage.dart';
import '../../_helpers/scripted_llm_client.dart';
import '../../_helpers/test_provider_scope.dart';

/// Regression test for the P0 bug surfaced during Phase 6.6 on-device
/// verification: tapping the AppBar pencil on `/soul` (Profile tab)
/// crashed `SoulEditorScreen` into a release-mode gray ErrorWidget
/// when no pet existed in the database.
///
/// Root cause: `activePetIdProvider` throws `StateError` on empty
/// pets. `SoulEditorScreen.build` re-derefed the provider via
/// `_ProfilePhotoCard(petId: ref.read(activePetIdProvider)())` and
/// `_TrendsSection(petId: ref.read(activePetIdProvider)())` AFTER
/// `_load()` had already caught the same throw — the second deref
/// crashed the build.
///
/// Fix: stash `_petId` in widget state during `_load()`; build()
/// renders a graceful `PetEmptyState` with an "Add a pet" CTA when
/// `_petId == null`.
///
/// This file pumps the app with NO pet in the database and routes
/// directly to `/soul/edit` to assert the empty-state path doesn't
/// crash and renders the locked copy.
void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  testWidgets('SoulEditorScreen renders graceful empty-state '
      "(\"Couldn't open this profile\" + Add a pet CTA) when no pet "
      'exists, instead of crashing into a gray ErrorWidget',
      (tester) async {
    // Build the data layer WITHOUT seeding a pet — the path the user
    // hits when they reach /soul/edit before completing add-pet.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final wiki = CapturingWikiIo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          appDatabaseProvider.overrideWith((ref) async => db),
          wikiIoProvider.overrideWith((ref) async => wiki),
          llmClientProvider.overrideWithValue(
            ScriptedLlmClient(scripts: const []),
          ),
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The redirect logic in routing.dart ensures unonboarded users
    // land on /onboarding. A user with an API key but no pet lands
    // on Home (the empty-state Home). They could then tap Profile
    // tab → tap the pencil. We exercise the same destination by
    // forcing the route directly via the same `.go` semantic that
    // a deep-link tap would use.
    final routerCtx = tester.element(find.byType(NavigationBar));
    // Switch to Profile branch + push the editor child.
    // `.push('/soul/edit')` mirrors what the AppBar pencil does.
    final nav = Navigator.of(routerCtx);
    addTearDown(() async {
      while (nav.canPop()) {
        nav.pop();
      }
    });

    // Tap Profile in the bottom nav, then tap the AppBar pencil — the
    // production path. (Driving via GoRouter.of(...).push() would
    // skip the on-screen pencil widget and miss any guard issues
    // there; tap the actual UI for fidelity.)
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Profile'),
    ));
    await tester.pumpAndSettle();
    // The pencil renders unconditionally in the AppBar, even with
    // no pet. Tap it.
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();

    // Pre-fix: the screen crashed into a release-mode ErrorWidget
    // (gray rectangle, no chrome). Post-fix: a clean empty-state
    // renders with the locked copy + Add a pet CTA.
    expect(find.byType(PetEmptyState), findsOneWidget,
        reason: 'no-pet path must render PetEmptyState, not crash');
    expect(find.text("Couldn't open this profile"), findsOneWidget);
    expect(find.text('Add a pet to start their profile.'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add a pet'), findsOneWidget,
        reason: 'CTA must route the user to /pets/add');
  });
}

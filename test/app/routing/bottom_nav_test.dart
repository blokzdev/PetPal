import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/main.dart';

import '../../_helpers/fake_api_key_storage.dart';
import '../../_helpers/scripted_llm_client.dart';
import '../../_helpers/test_provider_scope.dart';

/// Phase 6.6 task 6.6.A.4 — bottom-nav routing invariants.
///
/// Verifies the IA invariants that DECISIONS rows 59 + 65 lock:
///   - 4 tabs render (Home / Journal / Profile / Hub).
///   - Initial tab is Home.
///   - Tapping a tab swaps the active branch.
///   - Deep links to nested routes resolve into the correct branch
///     (the bottom nav reflects the destination tab).
///   - Legacy paths redirect into the new branch-nested locations
///     (`/reminders` → Home branch's `/home/reminders`; `/skills` →
///     Profile branch's `/soul/guides`).
///   - Tab state preservation: switching away and back to a tab
///     keeps the user on the previously-visited route within that
///     branch, not the branch root.
void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  Future<({CapturingWikiIo wiki, AppDatabase db})> pumpAppWithPet(
    WidgetTester tester,
  ) async {
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          ...stack.overrides,
        ],
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();
    return (wiki: stack.wiki, db: stack.db);
  }

  testWidgets('bottom nav renders the 4 locked destinations '
      '(Home / Journal / Profile / Hub)', (tester) async {
    await pumpAppWithPet(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Home'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Journal'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Profile'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Hub'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('initial tab is Home (selectedIndex 0)', (tester) async {
    await pumpAppWithPet(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
  });

  testWidgets('tapping Journal swaps active branch; selectedIndex moves '
      'to 1', (tester) async {
    await pumpAppWithPet(tester);
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Journal'),
    ));
    await tester.pumpAndSettle();
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 1);
  });

  testWidgets('tapping Profile swaps active branch; selectedIndex moves '
      'to 2', (tester) async {
    await pumpAppWithPet(tester);
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Profile'),
    ));
    await tester.pumpAndSettle();
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 2);
  });

  testWidgets('tapping Hub swaps active branch; selectedIndex moves '
      'to 3', (tester) async {
    await pumpAppWithPet(tester);
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Hub'),
    ));
    await tester.pumpAndSettle();
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 3);
  });

  testWidgets('deep-link to /settings resolves into Hub branch '
      '(selectedIndex 3, Settings screen visible)', (tester) async {
    await pumpAppWithPet(tester);
    // `.go()` is the deep-link semantics — system notification taps,
    // share-target intents, app restoration. `.push()` would stack
    // on the current branch (Home) instead of switching to Hub.
    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go('/settings');
    await tester.pumpAndSettle();
    // Settings screen renders.
    expect(find.text('Settings'), findsAtLeastNWidgets(1));
    // Bottom nav reflects Hub as the active branch.
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 3,
        reason: '/settings is in Hub branch; selectedIndex must reflect '
            'the active branch');
  });

  testWidgets('legacy /reminders redirects to /home/reminders '
      '(Home branch)', (tester) async {
    await pumpAppWithPet(tester);
    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go('/reminders');
    await tester.pumpAndSettle();
    // Reminders screen renders. The bottom nav reflects Home branch
    // since /reminders redirects into /home/reminders (Home-nested).
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0,
        reason: '/reminders → /home/reminders is in Home branch; '
            'selectedIndex must reflect Home');
  });

  testWidgets('legacy /skills redirects to /soul/guides '
      '(Profile branch)', (tester) async {
    await pumpAppWithPet(tester);
    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .go('/skills');
    await tester.pumpAndSettle();
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 2,
        reason: '/skills → /soul/guides is in Profile branch; '
            'selectedIndex must reflect Profile');
  });

  testWidgets('tab state preservation — Journal sub-route survives a '
      'tab switch and back (StatefulShellRoute branch state)',
      (tester) async {
    final pumped = await pumpAppWithPet(tester);

    // Seed an entry so the journal browser has navigable content.
    await pumped.db.into(pumped.db.entries).insert(
          EntriesCompanion.insert(
            petId: 1,
            path: 'wiki/1/food/2026-04-25-carrot-trial.md',
            type: 'food',
            ts: DateTime(2026, 4, 25),
            title: 'Carrot trial',
            bodyHash: 'h1',
          ),
        );
    await pumped.wiki.writeAtomic(
      'wiki/1/food/2026-04-25-carrot-trial.md',
      'Loved the frozen carrots.',
    );
    // Invalidate so the wiki browser sees the entry.
    final ctx = tester.element(find.byType(NavigationBar));
    final container = ProviderScope.containerOf(ctx);
    container.invalidate(wikiEntriesProvider);

    // Switch to Journal tab.
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Journal'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Carrot trial'), findsOneWidget);

    // Drill into the entry (push a sub-route onto the Journal branch).
    await tester.tap(find.text('Carrot trial'));
    await tester.pumpAndSettle();
    // Body of the entry shows.
    expect(find.text('Loved the frozen carrots.'), findsOneWidget);

    // Switch to Hub tab.
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Hub'),
    ));
    await tester.pumpAndSettle();
    // Hub destination renders (Settings ListTile is one easy marker).
    expect(find.widgetWithText(ListTile, 'Settings'), findsOneWidget);
    // Entry-detail body is gone from the visible tree (Journal branch
    // suspended, not disposed).
    expect(find.text('Loved the frozen carrots.'), findsNothing);

    // Switch back to Journal tab.
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Journal'),
    ));
    await tester.pumpAndSettle();
    // The entry detail page is restored (state preservation —
    // StatefulShellRoute kept the Journal branch's Navigator stack
    // intact across the tab swap).
    expect(find.text('Loved the frozen carrots.'), findsOneWidget,
        reason: 'tab state preservation: Journal branch kept the entry-'
            'detail route on its stack across the Hub-tab side trip');
  });
}

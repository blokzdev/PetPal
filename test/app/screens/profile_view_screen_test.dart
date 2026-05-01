import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/app/screens/soul_editor_screen.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/main.dart';

import '../../_helpers/fake_api_key_storage.dart';
import '../../_helpers/scripted_llm_client.dart';
import '../../_helpers/test_provider_scope.dart';

/// Phase 6.6 task 6.6.C.4 — `ProfileViewScreen` widget invariants.
///
/// The Phase-6.6 layered restructure (DECISIONS row 63) made `/soul`
/// the read-only sectioned landing surface; the form-driven editor
/// moved to `/soul/edit` reachable via the AppBar pencil. This file
/// pins the structural invariants the integration test in
/// `test/app/routing/bottom_nav_test.dart` doesn't assert: the 5
/// section headers, the AppBar pet-name interpolation, and the
/// edit-pencil → `/soul/edit` routing.
///
/// Mounted via `buildChatTestStack` + `PetPalApp` so the screen
/// resolves the real provider graph (petsProvider, wikiIoProvider,
/// weightHistoryProvider, etc.) without test-fake plumbing. Tap
/// Profile in the bottom nav to land on the screen.
void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  Future<void> pumpProfileScreen(
    WidgetTester tester, {
    String petName = 'Loki',
    String soulBody = '',
  }) async {
    // Tall viewport so the ListView renders all 5 sections in one
    // frame — without this, sections below the fold aren't in the
    // widget tree and `find.text('GUIDES & SKILLS')` returns 0.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
      petName: petName,
    );
    if (soulBody.isNotEmpty) {
      await stack.wiki.writeAtomic(stack.wiki.soulPath(stack.petId), soulBody);
    }
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

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Profile'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders all 5 sectioned headers per DECISIONS row 63 '
      '(About / Details / Health summary / Recent memories / '
      'Guides & skills)', (tester) async {
    await pumpProfileScreen(tester);

    // PetSectionHeader uppercases the title internally; the rendered
    // Text node carries the all-caps form. Match the uppercase form
    // directly — these strings are unique to this screen so a flat
    // `find.text` is precise enough.
    expect(find.text('ABOUT'), findsOneWidget,
        reason: 'About section header must render');
    expect(find.text('DETAILS'), findsOneWidget);
    expect(find.text('HEALTH SUMMARY'), findsOneWidget);
    expect(find.text('RECENT MEMORIES'), findsOneWidget);
    expect(find.text('GUIDES & SKILLS'), findsOneWidget);
  });

  testWidgets("AppBar interpolates the active pet's name "
      "(\"{name}'s profile\" per VOICE.md §5)", (tester) async {
    await pumpProfileScreen(tester);
    expect(find.text("Loki's profile"), findsAtLeastNWidgets(1));
  });

  testWidgets('edit pencil in the AppBar pushes /soul/edit '
      '(layered restructure preserves the existing editor unchanged)',
      (tester) async {
    await pumpProfileScreen(tester);

    // ProfileViewScreen is the active landing surface; SoulEditorScreen
    // is not yet mounted.
    expect(find.byType(SoulEditorScreen), findsNothing,
        reason: '/soul should be the read-only sectioned view');

    final pencil = find.byIcon(PhosphorIconsRegular.pencilSimple);
    expect(pencil, findsOneWidget,
        reason: 'AppBar pencil action is the only entry to /soul/edit');

    await tester.tap(pencil);
    await tester.pumpAndSettle();

    // After tap, /soul/edit is on top of the stack and the existing
    // editor mounts. The unchanged-editor lock from DECISIONS row 63
    // is satisfied by reusing SoulEditorScreen verbatim.
    expect(find.byType(SoulEditorScreen), findsOneWidget,
        reason: 'edit pencil must push the existing SoulEditorScreen at /soul/edit');
  });

  testWidgets('empty SOUL renders the "Tap the edit pencil to fill in '
      'this profile." placeholder in the About card', (tester) async {
    // Default `buildChatTestStack` SOUL is "category: dog\n" + empty
    // body — no other frontmatter rows. The AboutCard's empty-state
    // branch fires when both rows and body are empty; that requires
    // overwriting the seeded SOUL to drop `category` (which the card
    // doesn't render in its row set anyway, since category alone
    // doesn't qualify as "About content"). Seed a literally empty
    // SOUL to hit the empty-state branch deterministically.
    await pumpProfileScreen(
      tester,
      soulBody: '---\n---\n\n',
    );
    expect(
      find.text('Tap the edit pencil to fill in this profile.'),
      findsOneWidget,
    );
  });
}

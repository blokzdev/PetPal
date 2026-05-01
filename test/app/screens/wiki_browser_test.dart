import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/app/widgets/pet_card.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/main.dart';

import '../../_helpers/fake_api_key_storage.dart';
import '../../_helpers/scripted_llm_client.dart';
import '../../_helpers/test_provider_scope.dart';

void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  testWidgets('wiki browser shows entries grouped by type and opens an '
      'entry on tap', (tester) async {
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );

    // Seed three entries spanning two types so grouping is exercised.
    await stack.db.into(stack.db.entries).insert(
          EntriesCompanion.insert(
            petId: stack.petId,
            path: 'wiki/${stack.petId}/food/2026-04-25-carrot-trial.md',
            type: 'food',
            ts: DateTime(2026, 4, 25),
            title: 'Carrot trial',
            bodyHash: 'h1',
          ),
        );
    await stack.db.into(stack.db.entries).insert(
          EntriesCompanion.insert(
            petId: stack.petId,
            path: 'wiki/${stack.petId}/vet/2026-04-26-checkup.md',
            type: 'vet',
            ts: DateTime(2026, 4, 26),
            title: 'Annual checkup',
            bodyHash: 'h2',
          ),
        );
    await stack.wiki.writeAtomic(
      'wiki/${stack.petId}/food/2026-04-25-carrot-trial.md',
      'Milo loved the frozen carrots.',
    );
    await stack.wiki.writeAtomic(
      'wiki/${stack.petId}/vet/2026-04-26-checkup.md',
      'Vitals normal at the vet.',
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

    // Land on Home → Open journal.
    await tester.tap(find.widgetWithText(PetCardButton, 'Journal'));
    await tester.pumpAndSettle();

    // Group headers + entry titles.
    expect(find.text('Food · 1'), findsOneWidget);
    expect(find.text('Vet visits · 1'), findsOneWidget);
    expect(find.text('Carrot trial'), findsOneWidget);
    expect(find.text('Annual checkup'), findsOneWidget);

    // Tap the food entry.
    await tester.tap(find.text('Carrot trial'));
    await tester.pumpAndSettle();

    // Entry screen renders the body.
    expect(find.text('Milo loved the frozen carrots.'), findsOneWidget);
  });

  testWidgets('wiki browser shows the empty state when no entries exist',
      (tester) async {
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

    await tester.tap(find.widgetWithText(PetCardButton, 'Journal'));
    await tester.pumpAndSettle();

    // Empty state — task 5.7 redesign. Narrative invitation framing:
    // heading states the empty fact, body frames the journal as the
    // place where the pet's life accumulates, CTA opens chat.
    // VOICE.md §5: per-pet destination → name interpolation.
    expect(find.text('No memories about Milo yet.'), findsOneWidget);
    expect(
      find.textContaining("Milo's life will accumulate"),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Open chat'), findsOneWidget);
  });

  // ----------------------------------------------------------------
  // Task 5.11 — weekly digest entries get the editorial card
  // treatment in the journal browser. User-locked register: editorial
  // / magazine-spread (Source Serif 4 title, uppercase kicker, date
  // range). User-locked copy: "{pet}'s week" — possessive, terse.
  // ----------------------------------------------------------------
  testWidgets('weekly digest entries render as the editorial card '
      '(kicker + serif title + date range), distinct from regular '
      'ListTile entries', (tester) async {
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );

    // Seed one regular entry + one digest. Digest ts = end-of-week
    // (Sun 2026-04-26); WeeklyDigestRunner writes the entry with
    // ts = asOf, so the start of the window is 6 days earlier
    // (Mon 2026-04-20). The card renders the abbreviated range
    // "Apr 20–26" because both endpoints are in the same month.
    await stack.db.into(stack.db.entries).insert(
          EntriesCompanion.insert(
            petId: stack.petId,
            path: 'wiki/${stack.petId}/vet/2026-04-26-checkup.md',
            type: 'vet',
            ts: DateTime(2026, 4, 26),
            title: 'Annual checkup',
            bodyHash: 'h1',
          ),
        );
    await stack.db.into(stack.db.entries).insert(
          EntriesCompanion.insert(
            petId: stack.petId,
            path: 'wiki/${stack.petId}/digest/2026-04-26-weekly.md',
            type: 'digest',
            ts: DateTime(2026, 4, 26),
            title: 'Weekly digest 2026-04-26',
            bodyHash: 'h2',
          ),
        );
    await stack.wiki.writeAtomic(
      'wiki/${stack.petId}/digest/2026-04-26-weekly.md',
      '## This week\nMilo logged one vet visit and gained 0.2 kg.',
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

    await tester.tap(find.widgetWithText(PetCardButton, 'Journal'));
    await tester.pumpAndSettle();

    // Group headers stay — both 'digest' and 'vet' clusters render.
    expect(find.text('Weekly summary · 1'), findsOneWidget);
    expect(find.text('Vet visits · 1'), findsOneWidget);

    // Editorial register: kicker + name-interpolated possessive
    // title + date range. The literal entry.title ("Weekly digest
    // 2026-04-26") is NOT shown — the editorial card surfaces the
    // magazine-style copy instead. Magazine-style hierarchy.
    expect(find.text('WEEKLY SUMMARY'), findsOneWidget);
    expect(find.text("Milo's week"), findsOneWidget);
    expect(find.text('Apr 20–26'), findsOneWidget);
    expect(find.text('Weekly digest 2026-04-26'), findsNothing);

    // Regular vet entry still renders as a ListTile (with its
    // ISO-date subtitle), proving the dispatch is type-driven.
    expect(find.text('Annual checkup'), findsOneWidget);
    expect(find.text('2026-04-26'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Annual checkup'),
        matching: find.byType(ListTile),
      ),
      findsOneWidget,
      reason: 'non-digest entries keep the ListTile treatment',
    );
    expect(
      find.ancestor(
        of: find.text("Milo's week"),
        matching: find.byType(ListTile),
      ),
      findsNothing,
      reason: 'digest cards are NOT ListTiles — they\'re the '
          'editorial Material card with InkWell',
    );

    // Tapping the editorial card navigates to /wiki/entry with the
    // digest path. Validates the InkWell wiring on the new card.
    await tester.tap(find.text("Milo's week"));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Milo logged one vet visit'),
      findsOneWidget,
    );

    // Task 5.13 — wiki entry screen renders the user-facing title
    // ("Weekly summary"), not the file-system slug or the literal
    // entry.title ("Weekly digest 2026-04-26"). VOICE.md §3 + §4
    // forbid 'digest' in user-facing strings.
    expect(
      find.widgetWithText(AppBar, 'Weekly summary'),
      findsOneWidget,
      reason: 'AppBar title must use the VOICE.md vocab "Weekly '
          'summary", not the raw filename or "Weekly digest …"',
    );
    expect(find.textContaining('weekly.md'), findsNothing,
        reason: 'filename must not leak into the AppBar title');
  });

  testWidgets('digest card date range spans months when the window '
      'crosses a month boundary', (tester) async {
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );

    // Digest ts = Sun 2026-05-03; window start = Mon 2026-04-27.
    // Cross-month range must render with both abbreviations.
    await stack.db.into(stack.db.entries).insert(
          EntriesCompanion.insert(
            petId: stack.petId,
            path: 'wiki/${stack.petId}/digest/2026-05-03-weekly.md',
            type: 'digest',
            ts: DateTime(2026, 5, 3),
            title: 'Weekly digest 2026-05-03',
            bodyHash: 'h1',
          ),
        );
    await stack.wiki.writeAtomic(
      'wiki/${stack.petId}/digest/2026-05-03-weekly.md',
      '## Cross-month\nMonth-boundary digest.',
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
    await tester.tap(find.widgetWithText(PetCardButton, 'Journal'));
    await tester.pumpAndSettle();

    expect(find.text('Apr 27 – May 3'), findsOneWidget);
  });
}

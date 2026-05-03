import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/app/widgets/journal_bloom.dart';
import 'package:petpal/data/db/database.dart';
import 'dart:io';

import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/data/wiki_io.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';
import 'package:petpal/harness/agent/tool_dispatcher.dart';
import 'package:petpal/harness/retrieval/stub_embedding_provider.dart';
import 'package:petpal/harness/skills/empty_skill_source.dart';
import 'package:petpal/main.dart';

import '../../_helpers/fake_api_key_storage.dart';
import '../../_helpers/scripted_llm_client.dart';
import '../../_helpers/test_provider_scope.dart';

class _NoopWiki implements WikiIo {
  // Returns a minimal SOUL.md for any read so SessionBuilder can compose
  // a turn without throwing.
  @override
  Future<void> writeAtomic(String relPath, String body) async {}
  @override
  Future<String> read(String relPath) async =>
      '---\ncategory: dog\n---\n\n# Milo\n';
  @override
  Future<List<String>> listForPet(int petId) async => const [];
  @override
  String petDir(int petId) => 'wiki/$petId';
  @override
  String soulPath(int petId) => 'wiki/$petId/SOUL.md';
  @override
  Future<void> writeBytesAtomic(String relPath, Uint8List bytes) =>
      throw UnimplementedError('photo write not used in this test');
  @override
  Future<Uint8List> readBytes(String relPath) =>
      throw UnimplementedError('photo read not used in this test');
  @override
  Future<void> deleteIfExists(String relPath) async {}
  @override
  Future<int> bytesForPet(int petId) async => 0;
  @override
  Future<void> deleteAll() async {}
}

List<Override> _commonOverrides({required ScriptedLlmClient llm}) => [
      apiKeyStorageProvider.overrideWithValue(
        FakeApiKeyStorage(initial: 'sk-ant-test'),
      ),
      appDatabaseProvider.overrideWith((ref) async {
        final db = AppDatabase(NativeDatabase.memory());
        // Pre-populate with a pet so /chat can show "Milo" in the AppBar.
        await db.into(db.pets).insert(
              PetsCompanion.insert(
                name: 'Milo',
                createdAt: DateTime(2026, 4, 25),
              ),
            );
        ref.onDispose(() async => db.close());
        return db;
      }),
      wikiIoProvider.overrideWith((ref) async => _NoopWiki()),
      embeddingProviderProvider.overrideWith(
        (ref) async => const StubEmbeddingProvider(dim: 16),
      ),
      // No asset bundle in `flutter test` — fall back to an empty
      // skill source so SessionBuilder doesn't try AssetSkillSource.
      skillSourceProvider.overrideWithValue(const EmptySkillSource()),
      llmClientProvider.overrideWithValue(llm),
      // Empty tool dispatcher — text-only streaming, no tool calls.
      toolDispatcherProvider.overrideWith(
        (ref) async => ToolDispatcher(),
      ),
    ];

void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  testWidgets(
      'tapping send shows the user bubble and the streaming assistant '
      'text, then finalises', (tester) async {
    final llm = ScriptedLlmClient(
      scripts: [
        [
          const StreamMessageStart(),
          const StreamTextDelta('Got it. '),
          const StreamTextDelta('Logging Milo’s carrot trial.'),
          const StreamContentBlockStop(index: 0),
          const StreamMessageStop(),
        ],
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(llm: llm),
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Home greets Milo and shows the chat CTA.
    expect(find.text('Milo'), findsOneWidget);
    await tester.tap(find.text('Chat with Milo'));
    await tester.pumpAndSettle();

    // Empty-state heading — Phase 6.6 task 6.6.C.6 "Keep
    // Chronicling" register. Per VOICE.md §5 the heading
    // interpolates the pet name. Three suggestion chips lower
    // activation energy on first use.
    expect(find.text('Keep chronicling Milo.'), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(3));

    // Type and send.
    await tester.enterText(
      find.byType(TextField),
      'Milo loves frozen carrots',
    );
    await tester.tap(find.byIcon(PhosphorIconsRegular.paperPlaneTilt));
    await tester.pumpAndSettle();

    // User bubble + finalised assistant text.
    expect(find.text('Milo loves frozen carrots'), findsOneWidget);
    expect(find.text('Got it. Logging Milo’s carrot trial.'), findsOneWidget);

    // Non-flagged turn → no escalation badge.
    expect(find.text('PetPal flagged this as urgent'), findsNothing);
    expect(find.byIcon(PhosphorIconsRegular.warningOctagon), findsNothing);

    // Task 5.12 — composer has the visual lift: a Material slab in
    // surfaceContainer wrapping the TextField + send IconButton,
    // with a hairline Divider on its top edge separating it from
    // the chat thread above. Asserted via a widget-predicate
    // match (the IconButton.filled has its own primary-tinted
    // Material, so walking up from PhosphorIcons.paperPlaneTilt finds that one
    // first; the composer's slab is the one painted in
    // surfaceContainer).
    final scheme = Theme.of(tester.element(find.byType(Scaffold).last))
        .colorScheme;
    expect(
      find.byWidgetPredicate(
        (w) => w is Material && w.color == scheme.surfaceContainer,
      ),
      findsOneWidget,
      reason: 'composer slab uses surfaceContainer (5.12 lift)',
    );
    // Divider must exist between chat list and composer (sits as
    // the first child of the composer's Column).
    expect(find.byType(Divider), findsWidgets,
        reason: 'hairline divider separates composer from thread');
  });

  testWidgets(
      'flagged user turn renders the vet-escalation badge on the assistant '
      'bubble and persists in scrollback (VOICE.md §6, DECISIONS row 29)',
      (tester) async {
    final llm = ScriptedLlmClient(
      scripts: [
        [
          const StreamMessageStart(),
          const StreamTextDelta(
              'This sounds urgent — please call your vet now.'),
          const StreamContentBlockStop(index: 0),
          const StreamMessageStop(),
        ],
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(llm: llm),
        child: const PetPalApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chat with Milo'));
    await tester.pumpAndSettle();

    // Type a phrase that the screener flags as blood_in_stool.
    await tester.enterText(
      find.byType(TextField),
      'I noticed blood in his stool this morning',
    );
    await tester.tap(find.byIcon(PhosphorIconsRegular.paperPlaneTilt));
    await tester.pumpAndSettle();

    // Both the muted scrollback marker text and the warning icon must
    // attach to the assistant bubble.
    expect(find.text('PetPal flagged this as urgent'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.warningOctagon), findsOneWidget);
  });

  // ------------------------------------------------------------------
  // Task 5.9 — memory-saved hero choreography. End-to-end: scripted
  // LLM issues write_wiki_entry → real wiki tools register the entry
  // → chat notifier emits a MemorySavedEvent → chat surface fires the
  // bloom + snackbar. Asserts: snackbar copy is "Saved to Milo's
  // journal" (locked phrasing); JournalBloom widget mounts; the
  // snackbar's View action navigates to /wiki/entry.
  // ------------------------------------------------------------------
  testWidgets(
      'successful write_wiki_entry runs the 5.9 hero — JournalBloom '
      'mounts and the snackbar reads "Saved to Milo\'s journal"',
      (tester) async {
    final llm = ScriptedLlmClient(scripts: [
      [
        const StreamMessageStart(),
        const StreamToolUseStart(
          index: 0,
          id: 'tu_w',
          name: 'write_wiki_entry',
        ),
        const StreamToolUseInputDelta(
          index: 0,
          partialJson: '{"type":"food","title":"Carrot trial",'
              '"body":"Milo loves frozen carrots.","date":"2026-04-25"}',
        ),
        const StreamContentBlockStop(index: 0),
        const StreamMessageStop(stopReason: 'tool_use'),
      ],
      [
        const StreamMessageStart(),
        const StreamTextDelta('Logged the carrot trial.'),
        const StreamContentBlockStop(index: 0),
        const StreamMessageStop(),
      ],
    ]);

    // buildChatTestStack leaves toolDispatcherProvider unoverridden,
    // so the production registration runs (write_wiki_entry → real
    // CapturingWikiIo). The pet "Milo" is seeded with species=dog.
    final stack = await buildChatTestStack(llm: llm);

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

    await tester.tap(find.text('Chat with Milo'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Milo loves frozen carrots — please log it.',
    );
    await tester.tap(find.byIcon(PhosphorIconsRegular.paperPlaneTilt));
    // Don't pumpAndSettle past the bloom's 500ms animation — assert
    // the snackbar + bloom are visible mid-animation. One pump moves
    // through the tool round-trip; a couple more pumps catch the
    // post-frame snackbar showing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // Snackbar copy — locked phrasing per the task-5.9 user pick.
    expect(find.text("Saved to Milo's journal"), findsOneWidget);
    // Bloom widget mounted on top of the chat thread.
    expect(find.byType(JournalBloom), findsOneWidget);
    // Snackbar's deep-link action.
    expect(find.widgetWithText(SnackBarAction, 'View'), findsOneWidget);

    // Wait the bloom out so the test doesn't tear down with an
    // active animation controller.
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // Bloom dismounts itself when the controller hits AnimationStatus.completed.
    expect(find.byType(JournalBloom), findsNothing);
  });
}

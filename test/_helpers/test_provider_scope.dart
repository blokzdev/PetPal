import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/wiki_io.dart';
import 'package:petpal/harness/agent/llm_client.dart';
import 'package:petpal/harness/agent/tool_dispatcher.dart';
import 'package:petpal/harness/retrieval/stub_embedding_provider.dart';
import 'package:petpal/harness/skills/empty_skill_source.dart';
import 'package:petpal/harness/skills/skill_source.dart';

/// In-memory wiki for tests. Records writes; reads return what was written
/// or '' for SOUL.md-on-first-read so SessionBuilder doesn't blow up before
/// the user creates the pet via PetRepo.
class CapturingWikiIo implements WikiIo {
  final Map<String, String> writes = {};

  @override
  Future<void> writeAtomic(String relPath, String body) async {
    writes[relPath] = body;
  }

  @override
  Future<String> read(String relPath) async {
    final body = writes[relPath];
    if (body == null) {
      throw StateError('not written: $relPath');
    }
    return body;
  }

  @override
  Future<List<String>> listForPet(int petId) async {
    final prefix = '${petDir(petId)}/';
    return writes.keys.where((k) => k.startsWith(prefix)).toList();
  }

  @override
  String petDir(int petId) => 'wiki/$petId';

  @override
  String soulPath(int petId) => 'wiki/$petId/SOUL.md';
}

/// Build the minimal data-layer + retrieval-layer overrides chat tests
/// need to exercise the real SessionBuilder / AgentLoop wiring without
/// touching path_provider or the on-device ONNX model.
///
/// The `db`, `wiki`, and `petId` are returned so the test can also poke
/// the underlying state directly when asserting end-state.
Future<({
  AppDatabase db,
  CapturingWikiIo wiki,
  int petId,
  List<Override> overrides,
})> buildChatTestStack({
  required LlmClient llm,
  ToolDispatcher? tools,
  String petName = 'Milo',
  SkillSource? skillSource,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  final wiki = CapturingWikiIo();

  final petId = await db.into(db.pets).insert(
        PetsCompanion.insert(
          name: petName,
          createdAt: DateTime(2026, 4, 25),
        ),
      );
  // Seed a SOUL.md so SessionBuilder.compose can read it. Pet creation
  // through PetRepo would do this; tests skip that step for speed.
  await wiki.writeAtomic(
    wiki.soulPath(petId),
    '---\nspecies: dog\n---\n\n# $petName\n',
  );

  final overrides = <Override>[
    appDatabaseProvider.overrideWith((ref) async {
      ref.onDispose(() async {});
      return db;
    }),
    wikiIoProvider.overrideWith((ref) async => wiki),
    embeddingProviderProvider.overrideWith(
      (ref) async => const StubEmbeddingProvider(dim: 16),
    ),
    llmClientProvider.overrideWithValue(llm),
    // Skip the asset-backed skill source — `flutter test` has no asset
    // bundle to scan. Tests that want to exercise specific skills
    // pass `skillSource:` to this helper.
    skillSourceProvider.overrideWithValue(
      skillSource ?? const EmptySkillSource(),
    ),
    if (tools != null)
      toolDispatcherProvider.overrideWith((ref) async => tools),
  ];

  return (db: db, wiki: wiki, petId: petId, overrides: overrides);
}

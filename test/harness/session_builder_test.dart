import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/data/repos/pet_repo.dart';
import 'package:petpal/data/repos/wiki_repo.dart';
import 'package:petpal/data/wiki_io_fs.dart';
import 'package:petpal/harness/agent/messages.dart';
import 'package:petpal/harness/retrieval/embedding_worker.dart';
import 'package:petpal/harness/retrieval/hybrid_retriever.dart';
import 'package:petpal/harness/retrieval/stub_embedding_provider.dart';
import 'package:petpal/harness/session_builder.dart';
import 'package:petpal/harness/skills/empty_skill_source.dart';
import 'package:petpal/harness/skills/skill_loader.dart';
import 'package:petpal/harness/skills/skill_manifest.dart';
import 'package:petpal/harness/skills/skill_source.dart';

void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late SessionBuilder builder;
  late WikiIoFs wiki;
  late StubEmbeddingProvider provider;
  late PetRepo petRepo;
  late WikiRepo wikiRepo;

  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  // Helper: build a SessionBuilder with optional SkillLoader override.
  SessionBuilder makeBuilder({SkillLoader? skills}) => SessionBuilder(
        wiki: wiki,
        retriever: HybridRetriever(db: db),
        embeddings: provider,
        skills: skills ?? SkillLoader(source: const EmptySkillSource()),
      );

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('petpal_session_');
    db = AppDatabase(NativeDatabase.memory());
    wiki = WikiIoFs(tempRoot);
    provider = const StubEmbeddingProvider(dim: 16);
    final worker = EmbeddingWorker(db: db, provider: provider);
    wikiRepo = WikiRepo(db: db, wiki: wiki, embeddings: worker);
    petRepo = PetRepo(db: db, wiki: wiki);
    builder = makeBuilder();
  });

  tearDown(() async {
    await db.close();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('system prompt contains identity, SOUL.md, output contract',
      () async {
    final id = await petRepo.createPet(
      name: 'Milo',
      species: 'dog',
      dob: DateTime(2022, 6, 12),
    );
    final pet = (await petRepo.getPet(id))!;

    final turn = await builder.compose(pet: pet, userInput: 'Hi');

    expect(turn.systemPrompt, contains('PetPal'));
    expect(turn.systemPrompt, contains('memory-first companion for Milo'));
    expect(turn.systemPrompt, contains('never diagnose'));
    expect(turn.systemPrompt, contains("Milo's identity"));
    expect(turn.systemPrompt, contains('species: dog'));
    expect(turn.systemPrompt, contains('dob: 2022-06-12'));
    expect(turn.systemPrompt, contains('# Output contract'));
    expect(turn.systemPrompt, contains('wiki/$id/'));
  });

  test('system prompt is byte-stable across turns with same inputs '
      '(necessary for prompt caching)', () async {
    final id = await petRepo.createPet(name: 'Milo');
    final pet = (await petRepo.getPet(id))!;

    final a = await builder.compose(pet: pet, userInput: 'first turn');
    final b = await builder.compose(pet: pet, userInput: 'totally different');

    expect(a.systemPrompt, b.systemPrompt);
  });

  test('augmentedUserInput includes retrieved hits when entries exist',
      () async {
    final id = await petRepo.createPet(name: 'Milo');
    final pet = (await petRepo.getPet(id))!;
    await wikiRepo.writeEntry(
      petId: id,
      type: 'food',
      title: 'Carrot trial',
      body: 'Milo loves frozen carrots and naps after.',
      ts: DateTime(2026, 4, 25),
    );

    final turn = await builder.compose(
      pet: pet,
      userInput: 'What treats does Milo like?',
    );

    expect(turn.augmentedUserInput, contains('<context>'));
    expect(turn.augmentedUserInput, contains('wiki/$id/food/'));
    expect(turn.augmentedUserInput, contains('Carrot trial'));
    expect(turn.augmentedUserInput, contains('What treats does Milo like?'));
  });

  test('augmentedUserInput is just the raw input when retrieval is empty',
      () async {
    final id = await petRepo.createPet(name: 'Milo');
    final pet = (await petRepo.getPet(id))!;

    final turn = await builder.compose(pet: pet, userInput: 'Hi');
    expect(turn.augmentedUserInput, 'Hi');
    expect(turn.augmentedUserInput, isNot(contains('<context>')));
  });

  test('skill fragments matched by SkillLoader are injected into the '
      'system prompt under "Active skills"', () async {
    final id = await petRepo.createPet(name: 'Milo', species: 'dog');
    final pet = (await petRepo.getPet(id))!;

    final puppyBuilder = makeBuilder(
      skills: SkillLoader(
        source: _StaticSkillSource(
          manifest: const SkillManifest(
            id: 'puppy',
            name: 'Puppy Care',
            version: 1,
            species: ['dog'],
            triggers: ['house training', 'puppy'],
            loads: ['overview.md'],
            requiresPro: false,
          ),
          fragments: const {
            'overview.md': '# Puppy Care\nCrate train; reward calmness; etc.',
          },
        ),
      ),
    );

    final turn = await puppyBuilder.compose(
      pet: pet,
      userInput: 'house training tips?',
    );

    expect(turn.systemPrompt, contains('# Active skills'));
    expect(turn.systemPrompt, contains('Puppy Care'));
    expect(turn.systemPrompt, contains('Crate train'));
    expect(turn.matchedSkills, ['puppy']);
  });

  test('skills with non-matching species are filtered out of the system '
      'prompt (CLAUDE.md §3 — only species-aware code path)', () async {
    final id = await petRepo.createPet(name: 'Whiskers', species: 'cat');
    final pet = (await petRepo.getPet(id))!;

    final dogOnlyBuilder = makeBuilder(
      skills: SkillLoader(
        source: _StaticSkillSource(
          manifest: const SkillManifest(
            id: 'puppy',
            name: 'Puppy Care',
            version: 1,
            species: ['dog'],
            triggers: ['puppy'],
            loads: ['overview.md'],
            requiresPro: false,
          ),
          fragments: const {'overview.md': 'puppy advice'},
        ),
      ),
    );

    final turn = await dogOnlyBuilder.compose(
      pet: pet,
      userInput: 'tell me about my puppy',
    );

    expect(turn.systemPrompt, isNot(contains('# Active skills')));
    expect(turn.systemPrompt, isNot(contains('puppy advice')));
    expect(turn.matchedSkills, isEmpty);
  });

  test('tools pass through unchanged for ToolDispatcher to consume',
      () async {
    final id = await petRepo.createPet(name: 'Milo');
    final pet = (await petRepo.getPet(id))!;

    const tools = [
      ToolDefinition(
        name: 'read_wiki',
        description: 'Read wiki.',
        inputSchema: {'type': 'object'},
      ),
    ];

    final turn = await builder.compose(
      pet: pet,
      userInput: 'Hi',
      tools: tools,
    );
    expect(turn.tools, tools);
  });

  test('missing SOUL.md does not crash; system prompt still has identity',
      () async {
    // Insert a pet directly into the DB without going through PetRepo, so
    // no SOUL.md is seeded.
    final id = await db.into(db.pets).insert(
          PetsCompanion.insert(
            name: 'Ghost',
            createdAt: DateTime(2026, 4, 25),
          ),
        );
    final pet = await (db.select(db.pets)..where((p) => p.id.equals(id)))
        .getSingle();

    final turn = await builder.compose(pet: pet, userInput: 'Hi');
    expect(turn.systemPrompt, contains('memory-first companion for Ghost'));
    expect(turn.systemPrompt, isNot(contains("Ghost's identity")));
  });

  group('red-flag screener integration (CLAUDE.md §10)', () {
    test('non-urgent input → no escalation directive, ComposedTurn.redFlag is null',
        () async {
      final id = await petRepo.createPet(name: 'Milo', species: 'dog');
      final pet = (await petRepo.getPet(id))!;
      final turn = await builder.compose(
        pet: pet,
        userInput: 'Milo had a great walk today.',
      );
      expect(turn.redFlag, isNull);
      expect(turn.systemPrompt, isNot(contains('Escalation directive')));
      expect(
        turn.systemPrompt,
        isNot(contains('please call your vet or an emergency animal hospital')),
      );
    });

    test(
        'flagged input → directive appears in system prompt and ComposedTurn '
        'carries the match', () async {
      final id = await petRepo.createPet(name: 'Milo', species: 'dog');
      final pet = (await petRepo.getPet(id))!;
      final turn = await builder.compose(
        pet: pet,
        userInput: 'I noticed blood in his stool this morning.',
      );

      expect(turn.redFlag, isNotNull);
      expect(turn.redFlag!.category.id, 'blood_in_stool');

      // Directive heading is present.
      expect(turn.systemPrompt, contains('# Escalation directive (this turn only)'));
      // Verbatim escalation copy from VOICE.md §6 example 10 / CLAUDE.md §10.
      expect(
        turn.systemPrompt,
        contains(
          'This sounds urgent — please call your vet or an emergency animal '
          'hospital now. PetPal is software, not a vet. I can help you write '
          "down what's happening so it's ready when you call.",
        ),
      );
      // Category id in the directive for audit-trail purposes.
      expect(turn.systemPrompt, contains('category: blood_in_stool'));
    });

    test(
        'output contract always includes the screener-backup instruction so '
        'the model catches misses even when the regex table did not fire',
        () async {
      final id = await petRepo.createPet(name: 'Milo', species: 'dog');
      final pet = (await petRepo.getPet(id))!;
      final turn = await builder.compose(
        pet: pet,
        userInput: 'just a normal question',
      );
      expect(turn.redFlag, isNull);
      // Backup instruction is part of the canonical Output contract.
      expect(
        turn.systemPrompt,
        contains(
          'open with the vet-escalation preamble',
        ),
      );
    });
  });
}

class _StaticSkillSource implements SkillSource {
  _StaticSkillSource({required this.manifest, required this.fragments});
  final SkillManifest manifest;
  final Map<String, String> fragments;

  @override
  Future<List<SkillSourceEntry>> list() async => [
        SkillSourceEntry(
          manifest: manifest,
          readFragment: (name) async => fragments[name]!,
        ),
      ];
}

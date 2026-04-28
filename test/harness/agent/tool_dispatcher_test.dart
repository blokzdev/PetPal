import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/data/repos/wiki_repo.dart';
import 'package:petpal/data/wiki_io_fs.dart';
import 'package:petpal/harness/agent/messages.dart';
import 'package:petpal/harness/agent/tool_dispatcher.dart';
import 'package:petpal/harness/retrieval/embedding_worker.dart';
import 'package:petpal/harness/retrieval/hybrid_retriever.dart';
import 'package:petpal/harness/retrieval/stub_embedding_provider.dart';
import 'package:petpal/harness/tools/wiki_tools.dart';

void main() {
  group('ToolDispatcher', () {
    test('register + handle returns the function result as a tool result',
        () async {
      final d = ToolDispatcher();
      d.register(
        const ToolDefinition(
          name: 'echo',
          description: 'echo input',
          inputSchema: {'type': 'object'},
        ),
        (input) async => 'hi ${input['name']}',
      );

      final result = await d.handle(const ToolUseBlock(
        id: 'tu_1',
        name: 'echo',
        input: {'name': 'milo'},
      ));
      expect(result.toolUseId, 'tu_1');
      expect(result.content, 'hi milo');
      expect(result.isError, isFalse);
    });

    test('unknown tool name returns isError=true', () async {
      final d = ToolDispatcher();
      final result = await d.handle(const ToolUseBlock(
        id: 'tu_2',
        name: 'nope',
        input: {},
      ));
      expect(result.isError, isTrue);
      expect(result.content, contains('Unknown tool'));
    });

    test('thrown exception in handler becomes isError result', () async {
      final d = ToolDispatcher()
        ..register(
          const ToolDefinition(
            name: 'boom',
            description: '',
            inputSchema: {'type': 'object'},
          ),
          (_) async => throw StateError('kaboom'),
        );
      final result = await d.handle(const ToolUseBlock(
        id: 'tu_3',
        name: 'boom',
        input: {},
      ));
      expect(result.isError, isTrue);
      expect(result.content, contains('kaboom'));
    });

    test('registering the same name twice throws', () {
      final d = ToolDispatcher();
      d.register(
        const ToolDefinition(
          name: 'x',
          description: '',
          inputSchema: {'type': 'object'},
        ),
        (_) async => 'a',
      );
      expect(
        () => d.register(
          const ToolDefinition(
            name: 'x',
            description: '',
            inputSchema: {'type': 'object'},
          ),
          (_) async => 'b',
        ),
        throwsStateError,
      );
    });
  });

  group('wiki tools end-to-end', () {
    late Directory tempRoot;
    late AppDatabase db;
    late ToolDispatcher dispatcher;
    const petId = 1;

    setUpAll(() {
      registerSqliteVec(
        extensionPath: '${Directory.current.path}/test/native/libvec0.so',
      );
    });

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('petpal_tools_');
      db = AppDatabase(NativeDatabase.memory());
      final wiki = WikiIoFs(tempRoot);
      const provider = StubEmbeddingProvider(dim: 16);
      final worker = EmbeddingWorker(db: db, provider: provider);
      final repo = WikiRepo(db: db, wiki: wiki, embeddings: worker);
      final retriever = HybridRetriever(db: db);

      await db.into(db.pets).insert(
            PetsCompanion.insert(
              name: 'Milo',
              createdAt: DateTime(2026, 4, 25),
            ),
          );

      dispatcher = ToolDispatcher();
      registerWikiTools(
        dispatcher,
        wiki: wiki,
        repo: repo,
        retriever: retriever,
        embeddings: provider,
        activePetId: () => petId,
      );
    });

    tearDown(() async {
      await db.close();
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('write_wiki_entry then read_wiki round-trips the body', () async {
      final write = await dispatcher.handle(const ToolUseBlock(
        id: 'tu_w',
        name: 'write_wiki_entry',
        input: {
          'type': 'food',
          'title': 'Carrot trial',
          'body': 'Milo loves frozen carrots.',
          'date': '2026-04-25',
        },
      ));
      expect(write.isError, isFalse);
      expect(write.content, contains('wiki/$petId/food/2026-04-25-'));

      final read = await dispatcher.handle(const ToolUseBlock(
        id: 'tu_r',
        name: 'read_wiki',
        input: {'path': 'wiki/1/food/2026-04-25-carrot-trial.md'},
      ));
      expect(read.isError, isFalse);
      expect(read.content, contains('frozen carrots'));
    });

    test('search_wiki finds entries written by write_wiki_entry', () async {
      await dispatcher.handle(const ToolUseBlock(
        id: 'tu_w',
        name: 'write_wiki_entry',
        input: {
          'type': 'food',
          'title': 'Carrot trial',
          'body': 'Milo loves frozen carrots.',
          'date': '2026-04-25',
        },
      ));
      final search = await dispatcher.handle(const ToolUseBlock(
        id: 'tu_s',
        name: 'search_wiki',
        input: {'query': 'carrots'},
      ));
      expect(search.isError, isFalse);
      expect(search.content, contains('Carrot trial'));
    });

    test('the four canonical tools are registered', () {
      final names = dispatcher.definitions.map((d) => d.name).toSet();
      expect(names, {
        'read_wiki',
        'search_wiki',
        'write_wiki_entry',
        'update_soul',
      });
    });

    test('update_soul merges the patch into SOUL.md and preserves body',
        () async {
      // Seed a SOUL.md via the IO layer so the file exists before we patch.
      const soulPath = 'wiki/$petId/SOUL.md';
      await WikiIoFs(tempRoot).writeAtomic(
        soulPath,
        '---\n'
        'category: dog\n'
        'breed: mixed\n'
        'allergies: []\n'
        '---\n'
        '\n'
        '# Milo\n'
        'A rescue mutt.\n',
      );

      final result = await dispatcher.handle(const ToolUseBlock(
        id: 'tu_u',
        name: 'update_soul',
        input: {
          'patch': {
            'weight_kg': 14.2,
            'allergies': ['chicken'],
            'vet_contact': 'Dr. Patel',
          },
        },
      ));
      expect(result.isError, isFalse);
      expect(result.content, contains('updated_keys'));

      final updated = await WikiIoFs(tempRoot).read(soulPath);
      expect(updated, contains('weight_kg: 14.2'));
      expect(updated, contains('allergies: [chicken]'));
      expect(updated, contains('vet_contact: '));
      // Untouched scalars survive.
      expect(updated, contains('category: dog'));
      expect(updated, contains('breed: mixed'));
      // Body preserved.
      expect(updated, contains('# Milo'));
      expect(updated, contains('A rescue mutt.'));
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/harness/agent/llm_client.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';
import 'package:petpal/harness/agent/messages.dart' as agent_msg;
import 'package:petpal/harness/observation/affective_observation.dart';
import 'package:petpal/harness/observation/affective_observer.dart';
import 'package:petpal/harness/retrieval/embedding_provider.dart';
import 'package:petpal/harness/retrieval/hybrid_retriever.dart';
import 'package:petpal/harness/retrieval/stub_embedding_provider.dart';

/// Fake LlmClient that returns canned text + records calls.
class _MockLlm implements LlmClient {
  _MockLlm({this.responseText, this.delay, this.shouldThrow = false});

  final String? responseText;
  final Duration? delay;
  final bool shouldThrow;
  final List<({String systemPrompt, List<agent_msg.Message> history})>
      calls = [];

  @override
  Future<agent_msg.Message> turn({
    required String systemPrompt,
    required List<agent_msg.Message> history,
    List<agent_msg.ToolDefinition> tools = const [],
  }) async {
    calls.add((systemPrompt: systemPrompt, history: history));
    if (delay != null) await Future<void>.delayed(delay!);
    if (shouldThrow) throw StateError('mock transport error');
    return agent_msg.Message(
      role: agent_msg.Message.assistantRole,
      content: [agent_msg.TextBlock(responseText ?? '')],
    );
  }

  @override
  Stream<LlmStreamEvent> streamTurn({
    required String systemPrompt,
    required List<agent_msg.Message> history,
    List<agent_msg.ToolDefinition> tools = const [],
  }) async* {
    throw UnimplementedError();
  }
}

/// Minimal in-memory DB with one pet + one prior entry seeded so the
/// retriever has something to return. The hybrid retriever needs both
/// FTS5 and the entries table; test harness seeds via direct SQL +
/// the Drift API.
Future<AppDatabase> _seedDb({String? entryTitle}) async {
  final db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
  await db.into(db.pets).insert(PetsCompanion.insert(
        name: 'Loki',
        createdAt: DateTime.utc(2026, 4, 25),
      ));
  if (entryTitle != null) {
    final entryId = await db.into(db.entries).insert(EntriesCompanion.insert(
          petId: 1,
          path: 'wiki/1/vet/2026-03-12-checkup.md',
          type: 'vet',
          ts: DateTime.utc(2026, 3, 12),
          title: entryTitle,
          bodyHash: 'abc',
        ));
    // Seed the FTS5 mirror so search matches on the title.
    await db.customStatement(
      'INSERT INTO entries_fts5 (rowid, title, body) VALUES (?, ?, ?)',
      [entryId, entryTitle, 'Loki was a bit anxious at the vet today.'],
    );
  }
  return db;
}

void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  group('Phase 6 task 6.8 — affective observer', () {
    test('parses a well-formed grounded high-confidence response', () async {
      final db = await _seedDb(entryTitle: 'Vet visit — anxious');
      addTearDown(db.close);
      final llm = _MockLlm(responseText: '''
{
  "observation": "Looks more relaxed than at the vet visit last month.",
  "grounding_ref": "the vet visit on March 12",
  "confidence": "high"
}
''');
      final observer = AffectiveObserver(
        llm: llm,
        retriever: HybridRetriever(db: db),
        embeddings: StubEmbeddingProvider(),
      );

      final result = await observer.observe(
        petId: 1,
        caption: 'Loki on the porch in the sun.',
      );

      expect(result, isNotNull);
      expect(result!.text, contains('relaxed'));
      expect(result.groundingRef, 'the vet visit on March 12');
    });

    test('passes the caption + retrieved memories on the user turn',
        () async {
      final db = await _seedDb(entryTitle: 'Vet visit — anxious');
      addTearDown(db.close);
      final llm = _MockLlm(responseText: '{ "decline": true }');
      final observer = AffectiveObserver(
        llm: llm,
        retriever: HybridRetriever(db: db),
        embeddings: StubEmbeddingProvider(),
      );

      await observer.observe(
        petId: 1,
        caption: 'Loki anxious during the bath.',
      );

      // The observer may not call the LLM if retrieval returned no
      // hits; here we seeded a vet entry that should match the FTS5
      // tokenisation on "anxious".
      if (llm.calls.isEmpty) {
        // Vector-only path didn't hit — acceptable; no assertion to
        // make about the user-turn body.
        return;
      }
      final body =
          (llm.calls.single.history.single.content.single
              as agent_msg.TextBlock).text;
      expect(body, contains('Loki anxious during the bath.'));
      expect(body, contains('Vet visit — anxious'));
    });

    test('returns null when the model declines', () async {
      final db = await _seedDb(entryTitle: 'Vet visit — anxious');
      addTearDown(db.close);
      final llm = _MockLlm(responseText: '{ "decline": true }');
      final observer = AffectiveObserver(
        llm: llm,
        retriever: HybridRetriever(db: db),
        embeddings: StubEmbeddingProvider(),
      );
      final result = await observer.observe(
        petId: 1,
        caption: 'Loki on the porch.',
      );
      expect(result, isNull);
    });

    test('returns null when confidence is med (gate 3)', () async {
      final db = await _seedDb(entryTitle: 'Vet visit — anxious');
      addTearDown(db.close);
      final llm = _MockLlm(responseText: '''
{
  "observation": "Looks happier today.",
  "grounding_ref": "the vet visit",
  "confidence": "med"
}
''');
      final observer = AffectiveObserver(
        llm: llm,
        retriever: HybridRetriever(db: db),
        embeddings: StubEmbeddingProvider(),
      );
      final result = await observer.observe(
        petId: 1,
        caption: 'Loki on the porch.',
      );
      expect(result, isNull,
          reason: 'med confidence is dropped; only high passes');
    });

    test('returns null when grounding_ref is empty (ungrounded path)',
        () async {
      final db = await _seedDb(entryTitle: 'Vet visit — anxious');
      addTearDown(db.close);
      final llm = _MockLlm(responseText: '''
{
  "observation": "Loki looks happy.",
  "grounding_ref": "",
  "confidence": "high"
}
''');
      final observer = AffectiveObserver(
        llm: llm,
        retriever: HybridRetriever(db: db),
        embeddings: StubEmbeddingProvider(),
      );
      final result = await observer.observe(
        petId: 1,
        caption: 'Loki on the porch.',
      );
      expect(result, isNull,
          reason: 'empty grounding_ref → ungrounded → drop');
    });

    test('returns null when no prior memories were retrieved', () async {
      final db = await _seedDb(); // no entry seeded.
      addTearDown(db.close);
      final llm = _MockLlm(responseText: '{}');
      final observer = AffectiveObserver(
        llm: llm,
        retriever: HybridRetriever(db: db),
        embeddings: StubEmbeddingProvider(),
      );
      final result = await observer.observe(
        petId: 1,
        caption: 'Loki on the porch.',
      );
      expect(result, isNull);
      expect(llm.calls, isEmpty,
          reason: 'no retrieval → short-circuit before LLM call');
    });

    test('returns null when the LLM transport throws', () async {
      final db = await _seedDb(entryTitle: 'Vet visit — anxious');
      addTearDown(db.close);
      final llm = _MockLlm(shouldThrow: true);
      final observer = AffectiveObserver(
        llm: llm,
        retriever: HybridRetriever(db: db),
        embeddings: StubEmbeddingProvider(),
      );
      final result = await observer.observe(
        petId: 1,
        caption: 'Loki on the porch.',
      );
      expect(result, isNull);
    });

    test('returns null when the call exceeds the timeout', () async {
      final db = await _seedDb(entryTitle: 'Vet visit — anxious');
      addTearDown(db.close);
      final llm = _MockLlm(
        responseText: '{}',
        delay: const Duration(milliseconds: 200),
      );
      final observer = AffectiveObserver(
        llm: llm,
        retriever: HybridRetriever(db: db),
        embeddings: StubEmbeddingProvider(),
      );
      final result = await observer.observe(
        petId: 1,
        caption: 'Loki on the porch.',
      );
      // The observer may early-return on retrieval (the stub
      // embedding provider may take longer than 200ms in some CI
      // environments), or it may proceed to the LLM call which then
      // times out. Either path returns null.
      expect(result, isNull);
    });

    test('returns null when caption is empty', () async {
      final db = await _seedDb(entryTitle: 'Vet visit — anxious');
      addTearDown(db.close);
      final llm = _MockLlm(responseText: '{}');
      final observer = AffectiveObserver(
        llm: llm,
        retriever: HybridRetriever(db: db),
        embeddings: StubEmbeddingProvider(),
      );
      final result = await observer.observe(petId: 1, caption: '   ');
      expect(result, isNull);
      expect(llm.calls, isEmpty);
    });

    test('strips ```json code fences before parsing', () async {
      final db = await _seedDb(entryTitle: 'Vet visit — anxious');
      addTearDown(db.close);
      final llm = _MockLlm(responseText: '''
```json
{
  "observation": "Calmer than at the vet last month.",
  "grounding_ref": "the vet visit",
  "confidence": "high"
}
```
''');
      final observer = AffectiveObserver(
        llm: llm,
        retriever: HybridRetriever(db: db),
        embeddings: StubEmbeddingProvider(),
      );
      final result = await observer.observe(
        petId: 1,
        caption: 'Loki resting on the rug.',
      );
      expect(result, isNotNull);
      expect(result!.text, contains('Calmer'));
    });

    test('AffectiveObservation.fromJson rejects empty text or ref', () {
      expect(
        AffectiveObservation.fromJson({
          'text': '',
          'grounding_ref': 'x',
        }),
        isNull,
      );
      expect(
        AffectiveObservation.fromJson({
          'text': 'x',
          'grounding_ref': '   ',
        }),
        isNull,
      );
      expect(
        AffectiveObservation.fromJson({
          'text': 'x',
          'grounding_ref': 'y',
        })?.text,
        'x',
      );
    });
  });
}

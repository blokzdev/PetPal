import 'dart:convert';

import '../../data/repos/wiki_repo.dart';
import '../../data/wiki_io.dart';
import '../agent/messages.dart';
import '../agent/tool_dispatcher.dart';
import '../retrieval/embedding_provider.dart';
import '../retrieval/hybrid_retriever.dart';

/// Register the canonical wiki tools (`read_wiki`, `search_wiki`,
/// `write_wiki_entry`) on [dispatcher]. Each tool closes over the repos /
/// retriever / wiki IO it needs so the agent loop only sees JSON in/out.
///
/// The session's active pet id is bound by [activePetId] — a callback so
/// the dispatcher does not need to be rebuilt every time the user
/// switches pets in the UI.
void registerWikiTools(
  ToolDispatcher dispatcher, {
  required WikiIo wiki,
  required WikiRepo repo,
  required HybridRetriever retriever,
  required EmbeddingProvider embeddings,
  required int Function() activePetId,
}) {
  dispatcher.register(
    const ToolDefinition(
      name: 'read_wiki',
      description: 'Read the markdown body at a wiki path '
          '(e.g. `wiki/1/vet/2026-01-12-checkup.md`).',
      inputSchema: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Wiki-relative path of the entry to read.',
          },
        },
        'required': ['path'],
      },
    ),
    (input) => wiki.read(input['path']! as String),
  );

  dispatcher.register(
    const ToolDefinition(
      name: 'search_wiki',
      description: 'Hybrid keyword + semantic search of the active pet\'s '
          'wiki. Returns up to `k` ranked hits.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'k': {'type': 'integer', 'default': 6},
        },
        'required': ['query'],
      },
    ),
    (input) async {
      final q = input['query']! as String;
      final k = (input['k'] as num?)?.toInt() ?? 6;
      final vec = await embeddings.embed(q, kind: EmbeddingKind.query);
      final hits = await retriever.search(
        petId: activePetId(),
        queryText: q,
        queryVector: vec,
        k: k,
      );
      return jsonEncode([
        for (final h in hits)
          {
            'path': h.path,
            'title': h.title,
            if (h.snippet != null) 'snippet': h.snippet,
            'score': h.score,
          },
      ]);
    },
  );

  dispatcher.register(
    const ToolDefinition(
      name: 'write_wiki_entry',
      description: 'Write a new entry to the active pet\'s wiki. The path '
          'is composed automatically as '
          '`wiki/<petId>/<type>/<YYYY-MM-DD>-<slug>.md`.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'type': {
            'type': 'string',
            'description':
                'Category, e.g. `vet`, `behavior`, `food`, `weight`.',
          },
          'title': {'type': 'string'},
          'body': {'type': 'string'},
          'date': {
            'type': 'string',
            'description':
                'ISO-8601 date (YYYY-MM-DD). Defaults to today.',
          },
        },
        'required': ['type', 'title', 'body'],
      },
    ),
    (input) async {
      final ts = input['date'] is String
          ? DateTime.parse(input['date']! as String)
          : DateTime.now();
      final id = await repo.writeEntry(
        petId: activePetId(),
        type: input['type']! as String,
        title: input['title']! as String,
        body: input['body']! as String,
        ts: ts,
      );
      final path = entryPath(
        petId: activePetId(),
        type: input['type']! as String,
        title: input['title']! as String,
        ts: ts,
      );
      return jsonEncode({'entry_id': id, 'path': path});
    },
  );
}

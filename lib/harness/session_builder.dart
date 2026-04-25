import '../data/db/database.dart';
import '../data/wiki_io.dart';
import 'agent/messages.dart';
import 'retrieval/embedding_provider.dart';
import 'retrieval/hybrid_retriever.dart';

/// One turn's worth of input, ready for [AgentLoop.run]. The system prompt
/// is the cache-stable half; the augmented user input is the per-turn,
/// retrieval-augmented half.
class ComposedTurn {
  ComposedTurn({
    required this.systemPrompt,
    required this.augmentedUserInput,
    required this.tools,
  });

  /// Identity + SOUL.md + active skill fragments + output contract. Stable
  /// across turns for the same pet+skills, so [AnthropicClient]'s
  /// `cache_control: ephemeral` marker on this block accrues hits.
  final String systemPrompt;

  /// The user's message with retrieved wiki snippets prepended as context.
  /// Volatile per-turn — must NOT live in the system prompt or it would
  /// invalidate the cached prefix on every turn.
  final String augmentedUserInput;

  final List<ToolDefinition> tools;
}

/// Composes the per-turn inputs to [AgentLoop.run] from durable state
/// (SOUL.md, skills) and live retrieval (FTS5 + vector kNN over the pet's
/// wiki).
///
/// The split between `systemPrompt` and `augmentedUserInput` is deliberate
/// — see DECISIONS row 19.
class SessionBuilder {
  SessionBuilder({
    required WikiIo wiki,
    required HybridRetriever retriever,
    required EmbeddingProvider embeddings,
  })  : _wiki = wiki,
        _retriever = retriever,
        _embeddings = embeddings;

  final WikiIo _wiki;
  final HybridRetriever _retriever;
  final EmbeddingProvider _embeddings;

  Future<ComposedTurn> compose({
    required Pet pet,
    required String userInput,
    int retrievalK = 6,
    List<String> activeSkillFragments = const [],
    List<ToolDefinition> tools = const [],
  }) async {
    final soul = await _readSoulOrEmpty(pet.id);
    final systemPrompt = _buildSystemPrompt(
      pet: pet,
      soul: soul,
      skillFragments: activeSkillFragments,
    );

    final queryVector = await _embeddings.embed(userInput);
    final hits = await _retriever.search(
      petId: pet.id,
      queryText: userInput,
      queryVector: queryVector,
      k: retrievalK,
    );

    final augmented = hits.isEmpty
        ? userInput
        : _augmentWithContext(userInput: userInput, hits: hits);

    return ComposedTurn(
      systemPrompt: systemPrompt,
      augmentedUserInput: augmented,
      tools: tools,
    );
  }

  Future<String> _readSoulOrEmpty(int petId) async {
    try {
      return await _wiki.read(_wiki.soulPath(petId));
    } catch (_) {
      // First turn after pet creation: SOUL.md exists. If it doesn't, the
      // harness still composes a valid prompt; PetRepo seeds SOUL.md on
      // creation so this path is rare.
      return '';
    }
  }

  String _buildSystemPrompt({
    required Pet pet,
    required String soul,
    required List<String> skillFragments,
  }) {
    final buf = StringBuffer()
      ..writeln(
        'You are PetPal, a memory-first companion for ${pet.name}. '
        "You help the owner track their pet's life and know when to call "
        "the vet. You never diagnose. You ground every answer in the pet's "
        'wiki.',
      )
      ..writeln();

    if (soul.isNotEmpty) {
      buf
        ..writeln("# ${pet.name}'s identity")
        ..writeln()
        ..writeln(soul.trimRight())
        ..writeln();
    }

    if (skillFragments.isNotEmpty) {
      buf
        ..writeln('# Active skills')
        ..writeln();
      for (final fragment in skillFragments) {
        buf
          ..writeln(fragment.trimRight())
          ..writeln();
      }
    }

    buf
      ..writeln('# Output contract')
      ..writeln(
        '- Use tool calls for state changes (write_wiki_entry, update_soul, '
        'schedule_reminder).',
      )
      ..writeln(
        '- Cite entry paths like `wiki/${pet.id}/...` when referencing facts.',
      );
    return buf.toString();
  }

  String _augmentWithContext({
    required String userInput,
    required List<Hit> hits,
  }) {
    final buf = StringBuffer()
      ..writeln('<context>')
      ..writeln("Relevant entries from the pet's wiki:")
      ..writeln();
    for (final hit in hits) {
      buf.writeln('- `${hit.path}` — ${hit.title}');
      final snippet = hit.snippet;
      if (snippet != null && snippet.isNotEmpty) {
        buf.writeln('  > $snippet');
      }
    }
    buf
      ..writeln('</context>')
      ..writeln()
      ..write(userInput);
    return buf.toString();
  }
}

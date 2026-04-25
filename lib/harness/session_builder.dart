import '../data/db/database.dart';
import '../data/soul_file.dart';
import '../data/wiki_io.dart';
import 'agent/messages.dart';
import 'retrieval/embedding_provider.dart';
import 'retrieval/hybrid_retriever.dart';
import 'skills/skill_loader.dart';

/// One turn's worth of input, ready for [AgentLoop.run]. The system prompt
/// is the cache-stable half; the augmented user input is the per-turn,
/// retrieval-augmented half.
class ComposedTurn {
  ComposedTurn({
    required this.systemPrompt,
    required this.augmentedUserInput,
    required this.tools,
    required this.matchedSkills,
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

  /// Skill ids whose fragments contributed to [systemPrompt]. Surface
  /// for the chat UI ("informed by the Puppy skill") and for tests
  /// asserting that the right skills fired.
  final List<String> matchedSkills;
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
    required SkillLoader skills,
  })  : _wiki = wiki,
        _retriever = retriever,
        _embeddings = embeddings,
        _skills = skills;

  final WikiIo _wiki;
  final HybridRetriever _retriever;
  final EmbeddingProvider _embeddings;
  final SkillLoader _skills;

  Future<ComposedTurn> compose({
    required Pet pet,
    required String userInput,
    int retrievalK = 6,
    List<ToolDefinition> tools = const [],
  }) async {
    final soul = await _readSoulOrEmpty(pet.id);
    // Species lives in SOUL.md frontmatter (CLAUDE.md §3 — the only
    // species-aware code path). Empty string when SOUL is missing or
    // the user hasn't filled species in yet; that surfaces only
    // universal skills (those with empty species lists).
    final petSpecies =
        parseSoul(soul).frontmatter['species']?.toString().trim() ?? '';

    final matched = await _skills.match(
      petSpecies: petSpecies,
      userInput: userInput,
    );

    final systemPrompt = _buildSystemPrompt(
      pet: pet,
      soul: soul,
      skillFragments: [for (final m in matched) m.text],
    );

    final queryVector =
        await _embeddings.embed(userInput, kind: EmbeddingKind.query);
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
      matchedSkills: <String>{
        for (final m in matched) m.skillId,
      }.toList(),
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

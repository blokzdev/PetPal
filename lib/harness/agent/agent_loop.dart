import 'llm_client.dart';
import 'messages.dart';

/// The core agent harness loop.
///
/// Each call to [run] takes a user input plus prior history, asks the LLM
/// for an assistant turn, dispatches any tool calls the model makes,
/// appends the tool results to the history as a synthetic user message,
/// and repeats until the assistant produces a turn with no tool uses.
///
/// [maxToolHops] caps the number of LLM round-trips per [run] call so a
/// runaway tool loop can never hang the chat.
class AgentLoop {
  AgentLoop({
    required LlmClient llm,
    required ToolHandler tools,
    this.maxToolHops = 6,
  })  : _llm = llm,
        _tools = tools;

  final LlmClient _llm;
  final ToolHandler _tools;
  final int maxToolHops;

  /// Run the loop. Returns the full history including the new user message,
  /// every assistant turn, and any tool-result echoes. Throws
  /// [AgentLoopHopLimitExceeded] if the assistant keeps calling tools past
  /// [maxToolHops].
  Future<List<Message>> run({
    required String systemPrompt,
    required String userInput,
    required List<Message> priorHistory,
    List<ToolDefinition> tools = const [],
  }) async {
    final history = <Message>[
      ...priorHistory,
      Message.userText(userInput),
    ];

    for (var hop = 0; hop < maxToolHops; hop++) {
      final assistant = await _llm.turn(
        systemPrompt: systemPrompt,
        history: history,
        tools: tools,
      );
      history.add(assistant);

      final toolCalls = assistant.toolUses.toList();
      if (toolCalls.isEmpty) return history;

      final results = <ContentBlock>[];
      for (final use in toolCalls) {
        results.add(await _tools.handle(use));
      }
      history.add(Message(role: Message.userRole, content: results));
    }

    throw AgentLoopHopLimitExceeded(maxToolHops);
  }
}

class AgentLoopHopLimitExceeded implements Exception {
  AgentLoopHopLimitExceeded(this.limit);
  final int limit;

  @override
  String toString() =>
      'AgentLoopHopLimitExceeded: assistant called tools more than $limit '
      'times in a single run';
}

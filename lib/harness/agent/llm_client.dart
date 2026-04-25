import 'messages.dart';

/// Minimal contract the agent loop expects from the underlying LLM. The
/// real Anthropic-backed implementation lands in 1.10; tests inject a
/// canned-response fake.
abstract class LlmClient {
  /// Generate the next assistant message given a system prompt, the
  /// running conversation, and the tool catalog. Returns an
  /// [Message] with `role == assistant` containing one or more
  /// [ContentBlock]s — typically text, optionally one or more
  /// [ToolUseBlock]s when the model decides to call tools.
  Future<Message> turn({
    required String systemPrompt,
    required List<Message> history,
    List<ToolDefinition> tools = const [],
  });
}

/// What the agent loop calls when the assistant emits a [ToolUseBlock].
/// Implemented by [ToolDispatcher] in 1.9.
abstract class ToolHandler {
  Future<ToolResultBlock> handle(ToolUseBlock use);
}

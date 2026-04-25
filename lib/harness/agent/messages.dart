/// Anthropic-style content blocks. A message is an ordered list of blocks
/// rather than a flat string so the assistant can interleave text and
/// tool-use, and tool results can be associated to their originating call.
sealed class ContentBlock {
  const ContentBlock();
}

class TextBlock extends ContentBlock {
  const TextBlock(this.text);
  final String text;
}

class ToolUseBlock extends ContentBlock {
  const ToolUseBlock({
    required this.id,
    required this.name,
    required this.input,
  });

  /// Server-assigned id; echoed back as `toolUseId` in the matching
  /// [ToolResultBlock] so the model can pair calls and results.
  final String id;

  /// Tool name (must match a registered tool's name).
  final String name;

  /// JSON-shaped tool input.
  final Map<String, Object?> input;
}

class ToolResultBlock extends ContentBlock {
  const ToolResultBlock({
    required this.toolUseId,
    required this.content,
    this.isError = false,
  });

  final String toolUseId;
  final String content;
  final bool isError;
}

class Message {
  const Message({required this.role, required this.content});

  /// Convenience for the common case of a plain-text user message.
  factory Message.userText(String text) =>
      Message(role: userRole, content: [TextBlock(text)]);

  static const userRole = 'user';
  static const assistantRole = 'assistant';

  /// Either `'user'` or `'assistant'`. Tool results are sent as user
  /// messages whose content is one or more [ToolResultBlock]s.
  final String role;
  final List<ContentBlock> content;

  /// All tool-use blocks in this message, in order.
  Iterable<ToolUseBlock> get toolUses => content.whereType<ToolUseBlock>();

  /// Concatenated text from all [TextBlock]s.
  String get text => content.whereType<TextBlock>().map((b) => b.text).join();
}

/// Tool definition shape that the LLM client passes to the model so it knows
/// which tools it can call. Mirrors Anthropic's `tools` parameter.
class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;

  /// JSON-Schema describing the `input` shape the model should produce.
  final Map<String, Object?> inputSchema;
}

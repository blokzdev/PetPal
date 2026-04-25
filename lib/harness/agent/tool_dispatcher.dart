import 'llm_client.dart';
import 'messages.dart';

/// Signature of a registered tool: takes the model's JSON-shaped input,
/// returns a string the model will see as the tool result.
typedef ToolFn = Future<String> Function(Map<String, Object?> input);

/// Routes [ToolUseBlock]s to registered handlers. Unknown tool names and
/// thrown exceptions become error-flagged [ToolResultBlock]s so the
/// assistant can react and the agent loop never crashes.
class ToolDispatcher implements ToolHandler {
  ToolDispatcher();

  final Map<String, ToolFn> _handlers = {};
  final List<ToolDefinition> _definitions = [];

  /// All registered tool definitions, in registration order — pass to
  /// [LlmClient.turn]'s `tools` parameter.
  List<ToolDefinition> get definitions => List.unmodifiable(_definitions);

  /// Register a tool. Throws [StateError] if [definition.name] already exists.
  void register(ToolDefinition definition, ToolFn fn) {
    if (_handlers.containsKey(definition.name)) {
      throw StateError('tool already registered: ${definition.name}');
    }
    _handlers[definition.name] = fn;
    _definitions.add(definition);
  }

  @override
  Future<ToolResultBlock> handle(ToolUseBlock use) async {
    final fn = _handlers[use.name];
    if (fn == null) {
      return ToolResultBlock(
        toolUseId: use.id,
        content: 'Unknown tool: ${use.name}',
        isError: true,
      );
    }
    try {
      final result = await fn(use.input);
      return ToolResultBlock(toolUseId: use.id, content: result);
    } catch (e) {
      return ToolResultBlock(
        toolUseId: use.id,
        content: 'Error in ${use.name}: $e',
        isError: true,
      );
    }
  }
}

/// Events emitted by [LlmClient.streamTurn] as a single LLM turn unfolds.
///
/// Phase 2.3 surfaced text deltas only. Phase 2.4 adds tool-use deltas
/// so the streaming agent loop can detect and dispatch tool calls inside
/// a streamed turn — the chat UI surfaces tool invocations to the user
/// as the model decides on them.
sealed class LlmStreamEvent {
  const LlmStreamEvent();
}

/// Server confirmed a new assistant message is starting. Mostly used to
/// reset any UI buffer for the new turn.
class StreamMessageStart extends LlmStreamEvent {
  const StreamMessageStart();
}

/// Incremental text from the current assistant message. Append to the UI
/// buffer in arrival order.
class StreamTextDelta extends LlmStreamEvent {
  const StreamTextDelta(this.text);
  final String text;
}

/// Server began streaming a `tool_use` content block. The tool's [name]
/// and [id] are known up front; the JSON input arrives in subsequent
/// [StreamToolUseInputDelta]s.
class StreamToolUseStart extends LlmStreamEvent {
  const StreamToolUseStart({
    required this.index,
    required this.id,
    required this.name,
  });
  final int index;
  final String id;
  final String name;
}

/// A fragment of the JSON-encoded `input` for a tool call. Concatenate the
/// [partialJson] of every delta with the same [index] to recover the full
/// JSON object once the tool block stops.
class StreamToolUseInputDelta extends LlmStreamEvent {
  const StreamToolUseInputDelta({
    required this.index,
    required this.partialJson,
  });
  final int index;
  final String partialJson;
}

/// A content block (text or tool_use) finished streaming.
class StreamContentBlockStop extends LlmStreamEvent {
  const StreamContentBlockStop({required this.index});
  final int index;
}

/// Server finalised the assistant message. Carries final token usage
/// and the stop reason.
class StreamMessageStop extends LlmStreamEvent {
  const StreamMessageStop({
    this.stopReason,
    this.outputTokens,
  });
  final String? stopReason;
  final int? outputTokens;
}

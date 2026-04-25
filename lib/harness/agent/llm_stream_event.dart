/// Events emitted by [LlmClient.streamTurn]. Phase 2.3 only consumes
/// [StreamTextDelta] (chat token rendering) and [StreamMessageStop] (turn
/// finalisation); tool-use deltas land in 2.4 alongside the multi-turn
/// AgentLoop.
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

/// Server finalised the assistant message. Carries final token usage
/// when the API includes it on `message_delta` / `message_stop`.
class StreamMessageStop extends LlmStreamEvent {
  const StreamMessageStop({
    this.stopReason,
    this.outputTokens,
  });
  final String? stopReason;
  final int? outputTokens;
}

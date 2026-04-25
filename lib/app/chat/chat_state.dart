import '../../harness/agent/messages.dart' as llm;
import 'chat_error.dart';

final _contextPrefix = RegExp(
  r'^<context>.*?</context>\s*',
  dotAll: true,
);

String _stripContext(String text) {
  final m = _contextPrefix.firstMatch(text);
  return m == null ? text : text.substring(m.end);
}

enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({required this.role, required this.text});
  const ChatMessage.user(this.text) : role = ChatRole.user;
  const ChatMessage.assistant(this.text) : role = ChatRole.assistant;

  final ChatRole role;
  final String text;
}

/// Transient pill rendered while a tool call is in flight. Cleared on the
/// matching tool result.
class ToolPill {
  const ToolPill({
    required this.id,
    required this.name,
    required this.input,
  });
  final String id;
  final String name;
  final Map<String, Object?> input;
}

/// State surface the chat screen reads.
///
/// [history] is the canonical LLM-shape conversation (the AgentLoop's
/// final history). [streamingAssistant] holds the in-flight assistant
/// text while tokens arrive. [activeTools] tracks tool calls between
/// `tool_use` and `tool_result`.
///
/// The UI renders [uiMessages] (text-only projection of [history]) plus
/// the streaming buffer and any active tool pills.
class ChatState {
  const ChatState({
    this.history = const [],
    this.streamingAssistant,
    this.activeTools = const [],
    this.sending = false,
    this.error,
    this.lastFailedInput,
  });

  final List<llm.Message> history;
  final String? streamingAssistant;
  final List<ToolPill> activeTools;
  final bool sending;
  final ChatError? error;

  /// The user input that triggered the last failed turn — populated when
  /// [error] is non-null, cleared on the next successful send. The
  /// retry button on the chat surface uses this.
  final String? lastFailedInput;

  /// Project the LLM-shape [history] to the user-visible chat messages —
  /// flatten text content per turn, drop tool-only turns. SessionBuilder
  /// wraps the user's typed input in `<context>…</context>` tags before
  /// it's sent to the model; strip those for display so the user sees
  /// what they typed.
  Iterable<ChatMessage> get uiMessages sync* {
    for (final m in history) {
      final text = m.content
          .whereType<llm.TextBlock>()
          .map((b) => b.text)
          .join();
      if (text.isEmpty) continue;
      final isUser = m.role == llm.Message.userRole;
      yield ChatMessage(
        role: isUser ? ChatRole.user : ChatRole.assistant,
        text: isUser ? _stripContext(text) : text,
      );
    }
  }

  ChatState copyWith({
    List<llm.Message>? history,
    String? streamingAssistant,
    List<ToolPill>? activeTools,
    bool? sending,
    ChatError? error,
    String? lastFailedInput,
    bool clearStreamingAssistant = false,
    bool clearError = false,
    bool clearLastFailedInput = false,
  }) {
    return ChatState(
      history: history ?? this.history,
      streamingAssistant: clearStreamingAssistant
          ? null
          : (streamingAssistant ?? this.streamingAssistant),
      activeTools: activeTools ?? this.activeTools,
      sending: sending ?? this.sending,
      error: clearError ? null : (error ?? this.error),
      lastFailedInput: clearLastFailedInput
          ? null
          : (lastFailedInput ?? this.lastFailedInput),
    );
  }
}

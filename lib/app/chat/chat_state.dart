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
  const ChatMessage({
    required this.role,
    required this.text,
    this.escalatedCategory,
  });
  const ChatMessage.user(this.text)
      : role = ChatRole.user,
        escalatedCategory = null;
  const ChatMessage.assistant(this.text, {this.escalatedCategory})
      : role = ChatRole.assistant;

  final ChatRole role;
  final String text;

  /// Non-null when this assistant message was produced under a flagged
  /// user turn. Carries the red-flag category id (e.g. `blood_in_stool`)
  /// so the chat surface can attach the vet-escalation badge per
  /// VOICE.md §6. Persists forever — see DECISIONS row 29.
  final String? escalatedCategory;
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
    this.escalatedTurns = const {},
    this.streamingEscalation,
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

  /// History indices (of text-bearing user messages) that the red-flag
  /// screener flagged → category id. Persistent across the session;
  /// every assistant message produced under a flagged user turn renders
  /// the vet-escalation badge in scrollback.
  final Map<int, String> escalatedTurns;

  /// Category id of the in-flight turn, when that turn was flagged.
  /// Drives the badge on the streaming-assistant bubble (so the badge
  /// shows up live, not only after the turn commits). Cleared when the
  /// stream finishes.
  final String? streamingEscalation;

  /// Project the LLM-shape [history] to the user-visible chat messages —
  /// flatten text content per turn, drop tool-only turns. SessionBuilder
  /// wraps the user's typed input in `<context>…</context>` tags before
  /// it's sent to the model; strip those for display so the user sees
  /// what they typed.
  Iterable<ChatMessage> get uiMessages sync* {
    String? currentEscalation;
    for (var i = 0; i < history.length; i++) {
      final m = history[i];
      final text = m.content
          .whereType<llm.TextBlock>()
          .map((b) => b.text)
          .join();
      final isUser = m.role == llm.Message.userRole;
      // Only text-bearing user messages start a new turn for badge
      // purposes; tool-result userRole messages have no TextBlock and
      // must not reset the escalation flag mid-turn.
      if (isUser && text.isNotEmpty) {
        currentEscalation = escalatedTurns[i];
      }
      if (text.isEmpty) continue;
      yield ChatMessage(
        role: isUser ? ChatRole.user : ChatRole.assistant,
        text: isUser ? _stripContext(text) : text,
        escalatedCategory: !isUser ? currentEscalation : null,
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
    Map<int, String>? escalatedTurns,
    String? streamingEscalation,
    bool clearStreamingAssistant = false,
    bool clearError = false,
    bool clearLastFailedInput = false,
    bool clearStreamingEscalation = false,
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
      escalatedTurns: escalatedTurns ?? this.escalatedTurns,
      streamingEscalation: clearStreamingEscalation
          ? null
          : (streamingEscalation ?? this.streamingEscalation),
    );
  }
}

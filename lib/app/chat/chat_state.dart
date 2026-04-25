enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({required this.role, required this.text});
  const ChatMessage.user(this.text) : role = ChatRole.user;
  const ChatMessage.assistant(this.text) : role = ChatRole.assistant;

  final ChatRole role;
  final String text;
}

/// State surface the chat screen reads.
///
/// [messages] is the committed history (each turn finalises into one
/// entry). [streamingAssistant] is non-null while a response is
/// arriving; the UI renders it as a trailing pending bubble until
/// `message_stop` flips it back to null and pushes the finished text
/// onto [messages].
class ChatState {
  const ChatState({
    this.messages = const [],
    this.streamingAssistant,
    this.sending = false,
    this.error,
  });

  final List<ChatMessage> messages;
  final String? streamingAssistant;
  final bool sending;
  final String? error;

  ChatState copyWith({
    List<ChatMessage>? messages,
    String? streamingAssistant,
    bool? sending,
    String? error,
    bool clearStreamingAssistant = false,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      streamingAssistant: clearStreamingAssistant
          ? null
          : (streamingAssistant ?? this.streamingAssistant),
      sending: sending ?? this.sending,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

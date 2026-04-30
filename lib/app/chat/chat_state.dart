import 'dart:typed_data';

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
    this.attachedImageBytes,
    this.attachedImageMediaType,
  });
  const ChatMessage.user(
    this.text, {
    this.attachedImageBytes,
    this.attachedImageMediaType,
  })  : role = ChatRole.user,
        escalatedCategory = null;
  const ChatMessage.assistant(this.text, {this.escalatedCategory})
      : attachedImageBytes = null,
        attachedImageMediaType = null,
        role = ChatRole.assistant;

  final ChatRole role;
  final String text;

  /// Non-null when this assistant message was produced under a flagged
  /// user turn. Carries the red-flag category id (e.g. `blood_in_stool`)
  /// so the chat surface can attach the vet-escalation badge per
  /// VOICE.md §6. Persists forever — see DECISIONS row 29.
  final String? escalatedCategory;

  /// Phase 6 task 6.9 — bytes of an image the user attached to this
  /// turn. Only populated on user messages. Lives in the LLM history's
  /// ImageBlock; the projector below extracts it. The chat-bubble
  /// renderer shows a thumbnail + a "Save as memory" affordance on
  /// the assistant bubble that follows.
  final Uint8List? attachedImageBytes;

  /// Mime type for [attachedImageBytes] — typically `image/jpeg`.
  final String? attachedImageMediaType;
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

/// Signal payload emitted when `write_wiki_entry` completes successfully.
/// The chat surface reads transitions of this field (via Riverpod
/// `ref.listen`) to fire the 5.9 hero choreography — bloom over the
/// last assistant bubble + "Saved to {pet}'s journal" snackbar that
/// taps to the entry. The monotonic [id] lets listeners distinguish
/// successive saves within one session even when [path] repeats
/// (re-saves of the same entry would otherwise look state-equivalent).
class MemorySavedEvent {
  const MemorySavedEvent({
    required this.id,
    required this.path,
    required this.title,
  });

  /// Monotonic per-session counter. Increments by one on each emit.
  final int id;

  /// Wiki entry path (`wiki/<pet>/<type>/<slug>.md`) — used as the
  /// snackbar action's destination via go_router's `/wiki/entry`.
  final String path;

  /// Title block from the tool input. Used for the snackbar's
  /// implicit semantic context (read-aloud / a11y).
  final String title;
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
    this.recentMemorySave,
    this.pendingAttachedImage,
    this.pendingAttachedImageMediaType,
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

  /// Most recent successful `write_wiki_entry` result, monotonically
  /// versioned. Listeners on [chatProvider] detect transitions of
  /// `recentMemorySave?.id` to drive the 5.9 hero moment (bubble bloom
  /// + snackbar). Null until the first save lands; never cleared
  /// thereafter (the field is a signal of "the most recent thing,"
  /// not a current-state flag).
  final MemorySavedEvent? recentMemorySave;

  /// Phase 6 task 6.9 — pre-send composer attachment. Populated when
  /// the user picks a photo via the composer's photo button; cleared
  /// on send (the bytes move into the next user message). One photo
  /// per turn in v1; multi-photo deferred to v1.2.
  final Uint8List? pendingAttachedImage;
  final String? pendingAttachedImageMediaType;

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
      // Phase 6 task 6.9 — surface attached image bytes if present so
      // the bubble renderer can show a thumbnail + the save-as-memory
      // affordance on the assistant turn that follows. Only the first
      // ImageBlock is read; v1 caps photos at one per turn.
      Uint8List? imageBytes;
      String? imageMediaType;
      if (isUser) {
        for (final b in m.content) {
          if (b is llm.ImageBlock) {
            imageBytes = b.bytes;
            imageMediaType = b.mediaType;
            break;
          }
        }
      }
      yield ChatMessage(
        role: isUser ? ChatRole.user : ChatRole.assistant,
        text: isUser ? _stripContext(text) : text,
        escalatedCategory: !isUser ? currentEscalation : null,
        attachedImageBytes: imageBytes,
        attachedImageMediaType: imageMediaType,
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
    MemorySavedEvent? recentMemorySave,
    Uint8List? pendingAttachedImage,
    String? pendingAttachedImageMediaType,
    bool clearStreamingAssistant = false,
    bool clearError = false,
    bool clearLastFailedInput = false,
    bool clearStreamingEscalation = false,
    bool clearPendingAttachedImage = false,
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
      recentMemorySave: recentMemorySave ?? this.recentMemorySave,
      pendingAttachedImage: clearPendingAttachedImage
          ? null
          : (pendingAttachedImage ?? this.pendingAttachedImage),
      pendingAttachedImageMediaType: clearPendingAttachedImage
          ? null
          : (pendingAttachedImageMediaType ??
              this.pendingAttachedImageMediaType),
    );
  }
}

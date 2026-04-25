import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../harness/agent/llm_client.dart';
import '../../harness/agent/llm_stream_event.dart';
import '../../harness/agent/messages.dart' as llm;
import '../providers.dart';
import 'chat_state.dart';

/// Drives one chat session: appends the user turn, streams the assistant
/// response, and finalises it on `message_stop`.
///
/// 2.3 scope: text-only streaming with a placeholder system prompt. Tool
/// calls and SessionBuilder integration land in 2.4 and 2.6.
class ChatNotifier extends Notifier<ChatState> {
  // Placeholder until SessionBuilder lands in 2.6. The real prompt will
  // include identity + SOUL.md (cached) and the per-turn user message
  // will carry retrieved snippets in <context> tags (DECISIONS row 19).
  static const _placeholderSystemPrompt =
      'You are PetPal, a memory-first companion for the user’s pet. '
      'You help the owner track their pet’s life and know when to call '
      'the vet. You never diagnose. Keep replies conversational and '
      'concise.';

  @override
  ChatState build() => const ChatState();

  Future<void> send(String userText) async {
    final trimmed = userText.trim();
    if (trimmed.isEmpty || state.sending) return;

    final userMessages = [
      ...state.messages,
      ChatMessage.user(trimmed),
    ];
    state = state.copyWith(
      messages: userMessages,
      streamingAssistant: '',
      sending: true,
      clearError: true,
    );

    LlmClient client;
    try {
      client = ref.read(llmClientProvider);
    } catch (e) {
      state = state.copyWith(
        sending: false,
        clearStreamingAssistant: true,
        error: 'No API key configured.',
      );
      return;
    }

    try {
      final history = [
        for (final m in userMessages) _toLlmMessage(m),
      ];
      final stream = client.streamTurn(
        systemPrompt: _placeholderSystemPrompt,
        history: history,
      );

      var done = false;
      await for (final event in stream) {
        switch (event) {
          case StreamMessageStart():
            // Already in streaming state from `send`; nothing to do.
            break;
          case StreamTextDelta(:final text):
            state = state.copyWith(
              streamingAssistant: (state.streamingAssistant ?? '') + text,
            );
          case StreamMessageStop():
            _finalize();
            done = true;
        }
      }
      if (!done) _finalize();
    } catch (e) {
      state = state.copyWith(
        sending: false,
        clearStreamingAssistant: true,
        error: _humanError(e),
      );
    }
  }

  void _finalize() {
    final draft = state.streamingAssistant ?? '';
    final finalMessages = draft.isEmpty
        ? state.messages
        : [...state.messages, ChatMessage.assistant(draft)];
    state = state.copyWith(
      messages: finalMessages,
      sending: false,
      clearStreamingAssistant: true,
    );
  }

  llm.Message _toLlmMessage(ChatMessage m) => llm.Message(
        role: m.role == ChatRole.user
            ? llm.Message.userRole
            : llm.Message.assistantRole,
        content: [llm.TextBlock(m.text)],
      );

  String _humanError(Object e) {
    final s = e.toString();
    return s.length > 240 ? '${s.substring(0, 240)}…' : s;
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../harness/agent/agent_loop.dart';
import '../../harness/agent/tool_dispatcher.dart';
import '../providers.dart';
import 'chat_state.dart';

/// Drives one chat session through the full agent harness:
/// - appends the user turn to the LLM-shape history
/// - opens [AgentLoop.streamRun]
/// - accumulates text deltas into the in-flight buffer
/// - tracks active tool calls between `tool_use` and `tool_result`
/// - finalises history on `AgentLoopDone`
///
/// SessionBuilder integration (real system prompt with SOUL.md +
/// retrieved snippets) lands in 2.6 — for now, we use a placeholder
/// system prompt and pass tool definitions straight through.
class ChatNotifier extends Notifier<ChatState> {
  static const _placeholderSystemPrompt =
      'You are PetPal, a memory-first companion for the user’s pet. '
      'You help the owner track their pet’s life and know when to call '
      'the vet. You never diagnose. Use the wiki tools to record what '
      'the user tells you (write_wiki_entry, update_soul) and to look '
      'things up (search_wiki, read_wiki). Cite entry paths when you '
      'reference facts. Keep replies conversational and concise.';

  @override
  ChatState build() => const ChatState();

  Future<void> send(String userText) async {
    final trimmed = userText.trim();
    if (trimmed.isEmpty || state.sending) return;

    state = state.copyWith(
      sending: true,
      streamingAssistant: '',
      activeTools: const [],
      clearError: true,
    );

    AgentLoop loop;
    ToolDispatcher tools;
    try {
      loop = await ref.read(agentLoopProvider.future);
      tools = await ref.read(toolDispatcherProvider.future);
    } catch (e) {
      state = state.copyWith(
        sending: false,
        clearStreamingAssistant: true,
        error: 'Setup failed: ${_humanError(e)}',
      );
      return;
    }

    try {
      await for (final event in loop.streamRun(
        systemPrompt: _placeholderSystemPrompt,
        userInput: trimmed,
        priorHistory: state.history,
        tools: tools.definitions.toList(),
      )) {
        switch (event) {
          case AgentTextDelta(:final text):
            state = state.copyWith(
              streamingAssistant: (state.streamingAssistant ?? '') + text,
            );
          case AgentToolUse(:final id, :final name, :final input):
            state = state.copyWith(
              activeTools: [
                ...state.activeTools,
                ToolPill(id: id, name: name, input: input),
              ],
            );
          case AgentToolResult(:final toolUseId):
            state = state.copyWith(
              activeTools: state.activeTools
                  .where((p) => p.id != toolUseId)
                  .toList(),
            );
          case AgentLoopDone(:final history):
            state = state.copyWith(
              history: history,
              clearStreamingAssistant: true,
              activeTools: const [],
              sending: false,
            );
            return;
        }
      }
      // Stream ended without a Done event (shouldn't happen, but be
      // defensive).
      state = state.copyWith(
        sending: false,
        clearStreamingAssistant: true,
        activeTools: const [],
      );
    } catch (e) {
      state = state.copyWith(
        sending: false,
        clearStreamingAssistant: true,
        activeTools: const [],
        error: _humanError(e),
      );
    }
  }

  String _humanError(Object e) {
    final s = e.toString();
    return s.length > 240 ? '${s.substring(0, 240)}…' : s;
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);

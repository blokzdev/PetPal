import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../harness/agent/agent_loop.dart';
import '../../harness/agent/tool_dispatcher.dart';
import '../../harness/session_builder.dart';
import '../providers.dart';
import 'chat_state.dart';

/// Drives one chat session through the full agent harness:
/// - resolves the active pet from [activePetIdProvider] / [petRepoProvider]
/// - asks [SessionBuilder] for a cache-stable system prompt + retrieval-
///   augmented user input (DECISIONS row 19)
/// - opens [AgentLoop.streamRun] with that composed turn
/// - accumulates text deltas into the in-flight buffer
/// - tracks active tool calls between `tool_use` and `tool_result`
/// - finalises history on `AgentLoopDone`
class ChatNotifier extends Notifier<ChatState> {
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
    SessionBuilder sessionBuilder;
    Pet pet;
    try {
      loop = await ref.read(agentLoopProvider.future);
      tools = await ref.read(toolDispatcherProvider.future);
      sessionBuilder = await ref.read(sessionBuilderProvider.future);
      final petRepo = await ref.read(petRepoProvider.future);
      final activePetId = ref.read(activePetIdProvider);
      final fetched = await petRepo.getPet(activePetId());
      if (fetched == null) {
        state = state.copyWith(
          sending: false,
          clearStreamingAssistant: true,
          error: 'Active pet not found.',
        );
        return;
      }
      pet = fetched;
    } catch (e) {
      state = state.copyWith(
        sending: false,
        clearStreamingAssistant: true,
        error: 'Setup failed: ${_humanError(e)}',
      );
      return;
    }

    try {
      final composed = await sessionBuilder.compose(
        pet: pet,
        userInput: trimmed,
        tools: tools.definitions.toList(),
      );

      await for (final event in loop.streamRun(
        systemPrompt: composed.systemPrompt,
        userInput: composed.augmentedUserInput,
        priorHistory: state.history,
        tools: composed.tools,
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
            // Tools may have written entries / mutated SOUL.md; bust the
            // wiki browser's cache so the next view fetches fresh.
            ref.invalidate(wikiEntriesProvider);
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

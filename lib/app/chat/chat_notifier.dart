import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../harness/agent/agent_loop.dart';
import '../../harness/agent/tool_dispatcher.dart';
import '../../harness/session_builder.dart';
import '../platform/haptics.dart';
import '../providers.dart';
import 'chat_error.dart';
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
      clearLastFailedInput: true,
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
          error: const ChatError(
            category: ChatErrorCategory.generic,
            message: 'Active pet not found.',
          ),
          lastFailedInput: trimmed,
        );
        return;
      }
      pet = fetched;
    } catch (e) {
      state = state.copyWith(
        sending: false,
        clearStreamingAssistant: true,
        error: ChatError(
          category: ChatErrorCategory.generic,
          message: 'Setup failed: ${_truncate(e.toString())}',
        ),
        lastFailedInput: trimmed,
      );
      return;
    }

    try {
      final composed = await sessionBuilder.compose(
        pet: pet,
        userInput: trimmed,
        tools: tools.definitions.toList(),
      );

      // The user message we're about to send lands at this index in the
      // committed history (AgentLoop appends prior history + new user
      // message). When the screener flags this turn, that index goes
      // into escalatedTurns so all assistant messages produced by this
      // turn render the badge in scrollback.
      final newUserMessageIndex = state.history.length;

      // Surface the escalation on the streaming bubble immediately so
      // the badge renders live, not just after AgentLoopDone commits.
      if (composed.redFlag != null) {
        state = state.copyWith(
          streamingEscalation: composed.redFlag!.category.id,
        );
      }

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
          case AgentToolResult(:final toolUseId, :final isError):
            // Capture the originating pill BEFORE removing it so we
            // know which tool just completed (the result event itself
            // carries only the use-id, not the tool name — see
            // AgentToolResult in agent_loop.dart).
            final completedPill = state.activeTools.firstWhere(
              (p) => p.id == toolUseId,
              orElse: () => const ToolPill(id: '', name: '', input: {}),
            );
            state = state.copyWith(
              activeTools: state.activeTools
                  .where((p) => p.id != toolUseId)
                  .toList(),
            );
            // Tools may have written entries / mutated SOUL.md; bust the
            // wiki browser's cache so the next view fetches fresh.
            ref.invalidate(wikiEntriesProvider);
            // Task 5.8 — light haptic on save-memory commit. Fires only
            // for a successful write_wiki_entry; the visual hero moment
            // (snackbar + tool-pill settle animation) lands in 5.9.
            if (!isError && completedPill.name == 'write_wiki_entry') {
              ref.read(hapticsProvider).light();
            }
          case AgentLoopDone(:final history):
            final escalations = composed.redFlag != null
                ? {
                    ...state.escalatedTurns,
                    newUserMessageIndex: composed.redFlag!.category.id,
                  }
                : state.escalatedTurns;
            state = state.copyWith(
              history: history,
              clearStreamingAssistant: true,
              clearStreamingEscalation: true,
              activeTools: const [],
              sending: false,
              escalatedTurns: escalations,
            );
            return;
        }
      }
      // Stream ended without a Done event (shouldn't happen, but be
      // defensive).
      state = state.copyWith(
        sending: false,
        clearStreamingAssistant: true,
        clearStreamingEscalation: true,
        activeTools: const [],
      );
    } catch (e) {
      state = state.copyWith(
        sending: false,
        clearStreamingAssistant: true,
        clearStreamingEscalation: true,
        activeTools: const [],
        error: categorizeChatError(e),
        lastFailedInput: trimmed,
      );
    }
  }

  /// Re-run the last failed turn. Pops the user message that the failed
  /// send appended to history (so it isn't duplicated), then calls
  /// [send] with the same text. No-op if there's nothing to retry.
  Future<void> retry() async {
    final input = state.lastFailedInput;
    if (input == null || state.sending) return;
    // The failed turn already appended the user message via AgentLoop's
    // internal history construction — but only inside the loop's local
    // copy. Our [history] is updated only on AgentLoopDone, so on a
    // failure path it's still pre-failure. No popping needed.
    await send(input);
  }

  String _truncate(String s) =>
      s.length > 200 ? '${s.substring(0, 200)}…' : s;
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);

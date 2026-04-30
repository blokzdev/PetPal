import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../harness/agent/agent_loop.dart';
import '../../harness/agent/messages.dart' as llm;
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

  /// Phase 6 task 6.9 — composer hook to set/clear an attached photo
  /// before send. The bytes ride along on the next user turn.
  void attachImage({
    required Uint8List bytes,
    String mediaType = 'image/jpeg',
  }) {
    state = state.copyWith(
      pendingAttachedImage: bytes,
      pendingAttachedImageMediaType: mediaType,
    );
  }

  void clearAttachedImage() {
    state = state.copyWith(clearPendingAttachedImage: true);
  }

  Future<void> send(String userText) async {
    final trimmed = userText.trim();
    // Phase 6 task 6.9 — allow send when text is empty IFF a photo
    // is attached. The photo + an implicit "what is this?" intent
    // is a valid turn.
    final attachedImage = state.pendingAttachedImage;
    if ((trimmed.isEmpty && attachedImage == null) || state.sending) return;
    final attachedMediaType = state.pendingAttachedImageMediaType ??
        'image/jpeg';

    state = state.copyWith(
      sending: true,
      streamingAssistant: '',
      activeTools: const [],
      clearError: true,
      clearLastFailedInput: true,
      clearPendingAttachedImage: true,
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
        hasAttachedImage: attachedImage != null,
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
        attachedImage: attachedImage,
        attachedImageMediaType: attachedMediaType,
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
          case AgentToolResult(:final toolUseId, :final content, :final isError):
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
              // Task 5.9 — emit the memory-saved signal. The chat
              // surface reads transitions of `recentMemorySave?.id`
              // via `ref.listen` and runs the bubble→journal bloom +
              // snackbar choreography. The id increments per save so
              // a re-save of the same path still re-fires.
              //
              // The path lives in the tool result content (JSON-
              // encoded `{entry_id, path}` per wiki_tools.dart) — not
              // in the user-facing input — so we parse it from there.
              final title = completedPill.input['title'] as String? ?? 'memory';
              String? path;
              try {
                final decoded = jsonDecode(content);
                if (decoded is Map<String, Object?>) {
                  path = decoded['path'] as String?;
                }
              } on FormatException {
                // Tool result wasn't JSON (older fixtures or future
                // tools that return plain text). Skip the signal —
                // haptic still fires above; we just can't deep-link.
              }
              if (path != null) {
                final nextId = (state.recentMemorySave?.id ?? 0) + 1;
                state = state.copyWith(
                  recentMemorySave: MemorySavedEvent(
                    id: nextId,
                    path: path,
                    title: title,
                  ),
                );
              }
            }
          case AgentLoopDone(:final history):
            // Phase 6 task 6.9 — chat-attached photos run a post-stream
            // screenWithVision pass on the assistant's reply text. The
            // AI's natural-language description IS the vision payload
            // (single round-trip — the extractor isn't invoked here,
            // saving the second Sonnet call). When a chat-typed
            // pre-screen already flagged the turn, we keep the
            // existing flag (chat-side wins per row 55's priority).
            String? photoFlagCategory;
            if (attachedImage != null && composed.redFlag == null) {
              final assistantText = _lastAssistantText(history);
              if (assistantText.isNotEmpty) {
                final screener = ref.read(redFlagScreenerProvider);
                final match = screener.screenWithVision(
                  chatInput: trimmed.isEmpty ? null : trimmed,
                  visionExtracted: assistantText,
                );
                photoFlagCategory = match?.category.id;
              }
            }
            final escalations = composed.redFlag != null
                ? {
                    ...state.escalatedTurns,
                    newUserMessageIndex: composed.redFlag!.category.id,
                  }
                : (photoFlagCategory != null
                    ? {
                        ...state.escalatedTurns,
                        newUserMessageIndex: photoFlagCategory,
                      }
                    : state.escalatedTurns);
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

  /// Last assistant message's flat text (concatenation of TextBlocks).
  /// Empty when the most recent message isn't an assistant turn or
  /// has no text content (tool-only turns).
  String _lastAssistantText(List<llm.Message> history) {
    for (var i = history.length - 1; i >= 0; i--) {
      final m = history[i];
      if (m.role != llm.Message.assistantRole) continue;
      final text = m.content
          .whereType<llm.TextBlock>()
          .map((b) => b.text)
          .join('\n');
      return text;
    }
    return '';
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);

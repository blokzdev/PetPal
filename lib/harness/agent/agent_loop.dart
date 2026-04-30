import 'dart:convert';
import 'dart:typed_data';

import 'llm_client.dart';
import 'llm_stream_event.dart';
import 'messages.dart';

/// The core agent harness loop.
///
/// Each call to [run] takes a user input plus prior history, asks the LLM
/// for an assistant turn, dispatches any tool calls the model makes,
/// appends the tool results to the history as a synthetic user message,
/// and repeats until the assistant produces a turn with no tool uses.
///
/// [maxToolHops] caps the number of LLM round-trips per [run] call so a
/// runaway tool loop can never hang the chat.
class AgentLoop {
  AgentLoop({
    required LlmClient llm,
    required ToolHandler tools,
    this.maxToolHops = 6,
  })  : _llm = llm,
        _tools = tools;

  final LlmClient _llm;
  final ToolHandler _tools;
  final int maxToolHops;

  /// Run the loop. Returns the full history including the new user message,
  /// every assistant turn, and any tool-result echoes. Throws
  /// [AgentLoopHopLimitExceeded] if the assistant keeps calling tools past
  /// [maxToolHops].
  ///
  /// Phase 6 task 6.9 — pass [attachedImage] (+ [attachedImageMediaType])
  /// to attach a single image to the new user turn alongside [userInput].
  /// One image per turn in v1; multi-photo deferred to v1.2.
  Future<List<Message>> run({
    required String systemPrompt,
    required String userInput,
    required List<Message> priorHistory,
    List<ToolDefinition> tools = const [],
    Uint8List? attachedImage,
    String attachedImageMediaType = 'image/jpeg',
  }) async {
    final history = <Message>[
      ...priorHistory,
      _buildUserMessage(userInput, attachedImage, attachedImageMediaType),
    ];

    for (var hop = 0; hop < maxToolHops; hop++) {
      final assistant = await _llm.turn(
        systemPrompt: systemPrompt,
        history: history,
        tools: tools,
      );
      history.add(assistant);

      final toolCalls = assistant.toolUses.toList();
      if (toolCalls.isEmpty) return history;

      final results = <ContentBlock>[];
      for (final use in toolCalls) {
        results.add(await _tools.handle(use));
      }
      history.add(Message(role: Message.userRole, content: results));
    }

    throw AgentLoopHopLimitExceeded(maxToolHops);
  }

  /// Streaming variant of [run]. Yields a unified event stream as the
  /// turn unfolds: text deltas as the assistant types, tool-use events
  /// when it decides to call tools, tool-result echoes after dispatch,
  /// and a terminal [AgentLoopDone] carrying the final history.
  ///
  /// The chat surface in 2.5+ consumes [AgentTextDelta] for live
  /// rendering, [AgentToolUse] / [AgentToolResult] as transient status
  /// pills, and [AgentLoopDone] to commit the final assistant message.
  Stream<AgentLoopEvent> streamRun({
    required String systemPrompt,
    required String userInput,
    required List<Message> priorHistory,
    List<ToolDefinition> tools = const [],
    Uint8List? attachedImage,
    String attachedImageMediaType = 'image/jpeg',
  }) async* {
    final history = <Message>[
      ...priorHistory,
      _buildUserMessage(userInput, attachedImage, attachedImageMediaType),
    ];

    for (var hop = 0; hop < maxToolHops; hop++) {
      final assistant = await _streamOneTurn(
        systemPrompt: systemPrompt,
        history: history,
        tools: tools,
        emit: (e) => _streamSink.add(e),
      );

      // Drain the queued events that accumulated during the turn.
      // (Workaround for not being able to yield* across an async helper.)
      while (_streamSink.queue.isNotEmpty) {
        yield _streamSink.queue.removeAt(0);
      }

      history.add(assistant);

      final toolCalls = assistant.toolUses.toList();
      if (toolCalls.isEmpty) {
        yield AgentLoopDone(history: List.unmodifiable(history));
        return;
      }

      // Echo each tool use to the consumer before dispatching, so the UI
      // can show "calling search_wiki…" pills while the tool runs.
      for (final use in toolCalls) {
        yield AgentToolUse(id: use.id, name: use.name, input: use.input);
      }

      final results = <ContentBlock>[];
      for (final use in toolCalls) {
        final result = await _tools.handle(use);
        results.add(result);
        yield AgentToolResult(
          toolUseId: result.toolUseId,
          content: result.content,
          isError: result.isError,
        );
      }
      history.add(Message(role: Message.userRole, content: results));
    }

    throw AgentLoopHopLimitExceeded(maxToolHops);
  }

  // Per-call event sink the streamed-turn helper writes through. Reset on
  // each turn so leftover events from a prior turn can't leak.
  final _StreamSink _streamSink = _StreamSink();

  /// Build the new-turn user [Message]. Plain text when no image is
  /// attached; TextBlock + ImageBlock multimodal otherwise. The image
  /// block follows the LLM client encoder (Anthropic shape with
  /// optional `cache_control: ephemeral` for prompt-cache eligibility
  /// across follow-up turns referencing the same image).
  Message _buildUserMessage(
    String text,
    Uint8List? image,
    String mediaType,
  ) {
    if (image == null) return Message.userText(text);
    return Message(
      role: Message.userRole,
      content: [
        TextBlock(text),
        ImageBlock(bytes: image, mediaType: mediaType),
      ],
    );
  }

  /// Drive one streamed LLM turn end-to-end. Forwards text deltas,
  /// tool-use start, and emit events through [emit] (consumed by the
  /// outer streamRun). Returns the assembled assistant [Message] so the
  /// loop can append it to history and dispatch tool calls.
  Future<Message> _streamOneTurn({
    required String systemPrompt,
    required List<Message> history,
    required List<ToolDefinition> tools,
    required void Function(AgentLoopEvent) emit,
  }) async {
    _streamSink.queue.clear();
    final blocks = <ContentBlock>[];
    final toolBuffers = <int, _ToolUseBuilder>{};
    String? textBuffer;

    await for (final event in _llm.streamTurn(
      systemPrompt: systemPrompt,
      history: history,
      tools: tools,
    )) {
      switch (event) {
        case StreamMessageStart():
          textBuffer = null;

        case StreamTextDelta(:final text):
          textBuffer = (textBuffer ?? '') + text;
          emit(AgentTextDelta(text));

        case StreamToolUseStart(:final index, :final id, :final name):
          // If we'd been collecting text, that block is closing now.
          // (Anthropic emits content_block_stop, but the model also
          // separates blocks with a new start — finalise here defensively.)
          if (textBuffer != null) {
            blocks.add(TextBlock(textBuffer));
            textBuffer = null;
          }
          toolBuffers[index] =
              _ToolUseBuilder(id: id, name: name, jsonBuffer: StringBuffer());

        case StreamToolUseInputDelta(:final index, :final partialJson):
          toolBuffers[index]?.jsonBuffer.write(partialJson);

        case StreamContentBlockStop(:final index):
          final tool = toolBuffers.remove(index);
          if (tool != null) {
            blocks.add(tool.build());
          } else if (textBuffer != null) {
            blocks.add(TextBlock(textBuffer));
            textBuffer = null;
          }

        case StreamMessageStop():
          // If neither content_block_stop nor a subsequent block
          // closed the trailing text, finalise it now.
          if (textBuffer != null && textBuffer.isNotEmpty) {
            blocks.add(TextBlock(textBuffer));
            textBuffer = null;
          }
      }
    }

    return Message(role: Message.assistantRole, content: blocks);
  }
}

class AgentLoopHopLimitExceeded implements Exception {
  AgentLoopHopLimitExceeded(this.limit);
  final int limit;

  @override
  String toString() =>
      'AgentLoopHopLimitExceeded: assistant called tools more than $limit '
      'times in a single run';
}

/// Events emitted by [AgentLoop.streamRun].
sealed class AgentLoopEvent {
  const AgentLoopEvent();
}

class AgentTextDelta extends AgentLoopEvent {
  const AgentTextDelta(this.text);
  final String text;
}

class AgentToolUse extends AgentLoopEvent {
  const AgentToolUse({
    required this.id,
    required this.name,
    required this.input,
  });
  final String id;
  final String name;
  final Map<String, Object?> input;
}

class AgentToolResult extends AgentLoopEvent {
  const AgentToolResult({
    required this.toolUseId,
    required this.content,
    required this.isError,
  });
  final String toolUseId;
  final String content;
  final bool isError;
}

class AgentLoopDone extends AgentLoopEvent {
  const AgentLoopDone({required this.history});
  final List<Message> history;
}

class _ToolUseBuilder {
  _ToolUseBuilder({
    required this.id,
    required this.name,
    required this.jsonBuffer,
  });
  final String id;
  final String name;
  final StringBuffer jsonBuffer;

  ToolUseBlock build() {
    final raw = jsonBuffer.toString();
    Map<String, Object?> input = const {};
    if (raw.trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map<String, Object?>) {
          input = parsed;
        }
      } catch (_) {
        // Empty / partial JSON — leave input empty rather than failing
        // the whole turn. The tool dispatcher will report a structured
        // error if the input doesn't match its schema.
      }
    }
    return ToolUseBlock(id: id, name: name, input: input);
  }
}

class _StreamSink {
  final List<AgentLoopEvent> queue = [];
  void add(AgentLoopEvent event) => queue.add(event);
}

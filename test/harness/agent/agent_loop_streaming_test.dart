import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/agent/agent_loop.dart';
import 'package:petpal/harness/agent/llm_client.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';
import 'package:petpal/harness/agent/messages.dart';

import '../../_helpers/scripted_llm_client.dart';

class _ScriptedTools implements ToolHandler {
  _ScriptedTools(this.responses);
  final Map<String, String> responses;
  final List<ToolUseBlock> calls = [];

  @override
  Future<ToolResultBlock> handle(ToolUseBlock use) async {
    calls.add(use);
    return ToolResultBlock(
      toolUseId: use.id,
      content: responses[use.name] ?? 'ok',
    );
  }
}

void main() {
  test('streamRun yields text deltas, then a Done with the full history '
      'when the assistant calls no tools', () async {
    final llm = ScriptedLlmClient(
      scripts: [
        [
          const StreamMessageStart(),
          const StreamTextDelta('Hi '),
          const StreamTextDelta('there.'),
          const StreamContentBlockStop(index: 0),
          const StreamMessageStop(stopReason: 'end_turn'),
        ],
      ],
    );
    final tools = _ScriptedTools(const {});
    final loop = AgentLoop(llm: llm, tools: tools);

    final events = await loop
        .streamRun(
          systemPrompt: 'sys',
          userInput: 'hi',
          priorHistory: const [],
        )
        .toList();

    // Two text deltas, then Done.
    final deltas = events.whereType<AgentTextDelta>().map((e) => e.text);
    expect(deltas, ['Hi ', 'there.']);

    final done = events.whereType<AgentLoopDone>().single;
    // History: user message + assistant message.
    expect(done.history, hasLength(2));
    expect(done.history.first.role, Message.userRole);
    expect(done.history.last.role, Message.assistantRole);
    expect(done.history.last.content.whereType<TextBlock>().single.text,
        'Hi there.');

    expect(tools.calls, isEmpty);
  });

  test('streamRun dispatches tool calls produced mid-stream and continues '
      'until the assistant stops calling tools', () async {
    final llm = ScriptedLlmClient(
      scripts: [
        // First turn: emits a tool_use for search_wiki.
        [
          const StreamMessageStart(),
          const StreamToolUseStart(
            index: 0,
            id: 'tu_1',
            name: 'search_wiki',
          ),
          const StreamToolUseInputDelta(
            index: 0,
            partialJson: '{"query":"frozen carrots"}',
          ),
          const StreamContentBlockStop(index: 0),
          const StreamMessageStop(stopReason: 'tool_use'),
        ],
        // Second turn: text-only response after seeing tool result.
        [
          const StreamMessageStart(),
          const StreamTextDelta('Found 1 entry. '),
          const StreamTextDelta('Milo loves frozen carrots.'),
          const StreamContentBlockStop(index: 0),
          const StreamMessageStop(stopReason: 'end_turn'),
        ],
      ],
    );
    final tools = _ScriptedTools(const {
      'search_wiki': '[{"path":"wiki/1/food/...","snippet":"loves carrots"}]',
    });
    final loop = AgentLoop(llm: llm, tools: tools);

    final events = await loop
        .streamRun(
          systemPrompt: 'sys',
          userInput: 'what does Milo like?',
          priorHistory: const [],
          tools: const [
            ToolDefinition(
              name: 'search_wiki',
              description: 'search',
              inputSchema: {'type': 'object'},
            ),
          ],
        )
        .toList();

    // Sequence: tool-use echoed → tool-result echoed → text deltas → done.
    final toolUse = events.whereType<AgentToolUse>().single;
    expect(toolUse.id, 'tu_1');
    expect(toolUse.name, 'search_wiki');
    expect(toolUse.input, {'query': 'frozen carrots'});

    final toolResult = events.whereType<AgentToolResult>().single;
    expect(toolResult.toolUseId, 'tu_1');
    expect(toolResult.isError, isFalse);
    expect(toolResult.content, contains('loves carrots'));

    final deltas = events.whereType<AgentTextDelta>().map((e) => e.text);
    expect(deltas, ['Found 1 entry. ', 'Milo loves frozen carrots.']);

    final done = events.whereType<AgentLoopDone>().single;
    // History: user, assistant(tool_use), user(tool_result), assistant(text).
    expect(done.history, hasLength(4));
    expect(done.history[1].toolUses.single.name, 'search_wiki');
    expect(done.history[3].content.whereType<TextBlock>().single.text,
        'Found 1 entry. Milo loves frozen carrots.');

    expect(tools.calls, hasLength(1));
  });

  test('streamRun bubbles AgentLoopHopLimitExceeded if the assistant '
      'never stops calling tools', () async {
    final scripts = List.generate(
      8,
      (i) => [
        const StreamMessageStart(),
        StreamToolUseStart(index: 0, id: 'tu_$i', name: 'search_wiki'),
        const StreamToolUseInputDelta(
          index: 0,
          partialJson: '{"query":"x"}',
        ),
        const StreamContentBlockStop(index: 0),
        const StreamMessageStop(stopReason: 'tool_use'),
      ],
    );
    final llm = ScriptedLlmClient(scripts: scripts);
    final tools = _ScriptedTools(const {});
    final loop = AgentLoop(llm: llm, tools: tools, maxToolHops: 3);

    expect(
      () async => loop
          .streamRun(
            systemPrompt: 'sys',
            userInput: 'hi',
            priorHistory: const [],
            tools: const [
              ToolDefinition(
                name: 'search_wiki',
                description: 'search',
                inputSchema: {'type': 'object'},
              ),
            ],
          )
          .toList(),
      throwsA(isA<AgentLoopHopLimitExceeded>()),
    );
  });
}

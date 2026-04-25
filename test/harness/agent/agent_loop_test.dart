import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/agent/agent_loop.dart';
import 'package:petpal/harness/agent/llm_client.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';
import 'package:petpal/harness/agent/messages.dart';

class _ScriptedClient implements LlmClient {
  _ScriptedClient(this._turns);

  final List<Message> _turns;
  final List<List<Message>> historiesSeen = [];

  @override
  Future<Message> turn({
    required String systemPrompt,
    required List<Message> history,
    List<ToolDefinition> tools = const [],
  }) async {
    historiesSeen.add(List.of(history));
    return _turns.removeAt(0);
  }

  // streamTurn isn't exercised by AgentLoop tests, but the LlmClient
  // contract requires it. Yield deltas reconstructed from the next scripted
  // text block so streaming smoke tests against this fake still work.
  @override
  Stream<LlmStreamEvent> streamTurn({
    required String systemPrompt,
    required List<Message> history,
    List<ToolDefinition> tools = const [],
  }) async* {
    final next = _turns.removeAt(0);
    historiesSeen.add(List.of(history));
    yield const StreamMessageStart();
    for (final block in next.content) {
      if (block is TextBlock) {
        yield StreamTextDelta(block.text);
      }
    }
    yield const StreamMessageStop(stopReason: 'end_turn');
  }
}

class _RecordingTools implements ToolHandler {
  final List<ToolUseBlock> calls = [];
  Map<String, String> responses = const {};

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
  test('terminates after the first tool-free assistant turn', () async {
    final client = _ScriptedClient([
      const Message(
        role: Message.assistantRole,
        content: [TextBlock('Hello!')],
      ),
    ]);
    final loop = AgentLoop(llm: client, tools: _RecordingTools());

    final history = await loop.run(
      systemPrompt: 'You are PetPal.',
      userInput: 'Hi',
      priorHistory: const [],
    );

    expect(history, hasLength(2));
    expect(history.first.role, Message.userRole);
    expect(history.first.text, 'Hi');
    expect(history.last.role, Message.assistantRole);
    expect(history.last.text, 'Hello!');
  });

  test('dispatches tool uses, feeds results back, then continues', () async {
    final client = _ScriptedClient([
      const Message(
        role: Message.assistantRole,
        content: [
          TextBlock("Let me check Milo's wiki."),
          ToolUseBlock(
            id: 'tu_1',
            name: 'search_wiki',
            input: {'query': 'carrot'},
          ),
        ],
      ),
      const Message(
        role: Message.assistantRole,
        content: [TextBlock('Milo loves frozen carrots.')],
      ),
    ]);
    final tools = _RecordingTools()..responses = {'search_wiki': 'CARROT_HIT'};
    final loop = AgentLoop(llm: client, tools: tools);

    final history = await loop.run(
      systemPrompt: 'sys',
      userInput: 'What treats does Milo like?',
      priorHistory: const [],
    );

    // user → asst (with tool_use) → user (tool_result) → asst (final).
    expect(history, hasLength(4));
    expect(history[1].toolUses, hasLength(1));
    expect(history[2].role, Message.userRole);
    expect(history[2].content.single, isA<ToolResultBlock>());
    final result = history[2].content.single as ToolResultBlock;
    expect(result.toolUseId, 'tu_1');
    expect(result.content, 'CARROT_HIT');
    expect(history[3].text, 'Milo loves frozen carrots.');

    expect(tools.calls.single.name, 'search_wiki');
  });

  test('throws when the model exceeds maxToolHops', () async {
    Message looper() => const Message(
          role: Message.assistantRole,
          content: [
            ToolUseBlock(id: 'tu_x', name: 'noop', input: {}),
          ],
        );
    final client = _ScriptedClient([looper(), looper(), looper()]);
    final loop = AgentLoop(
      llm: client,
      tools: _RecordingTools(),
      maxToolHops: 2,
    );

    await expectLater(
      loop.run(systemPrompt: 's', userInput: 'go', priorHistory: const []),
      throwsA(isA<AgentLoopHopLimitExceeded>()),
    );
  });

  test('parallel tool calls in one turn produce one result block per call',
      () async {
    final client = _ScriptedClient([
      const Message(
        role: Message.assistantRole,
        content: [
          ToolUseBlock(id: 'a', name: 'read_wiki', input: {'path': 'A'}),
          ToolUseBlock(id: 'b', name: 'read_wiki', input: {'path': 'B'}),
        ],
      ),
      const Message(
        role: Message.assistantRole,
        content: [TextBlock('done')],
      ),
    ]);
    final tools = _RecordingTools();
    final loop = AgentLoop(llm: client, tools: tools);

    final history = await loop.run(
      systemPrompt: 's',
      userInput: 'go',
      priorHistory: const [],
    );

    final resultMsg = history[2];
    expect(resultMsg.content, hasLength(2));
    expect(
      resultMsg.content.map((b) => (b as ToolResultBlock).toolUseId),
      ['a', 'b'],
    );
    expect(tools.calls.map((c) => c.id).toList(), ['a', 'b']);
  });
}

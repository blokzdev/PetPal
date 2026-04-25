import 'package:petpal/harness/agent/llm_client.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';
import 'package:petpal/harness/agent/messages.dart';

/// Fake [LlmClient] for chat-side widget tests. Each call to [streamTurn]
/// pulls the next *script* — a list of [LlmStreamEvent]s — and emits them
/// in order. Optionally awaits [pacingDelay] between events so tests can
/// pump frames mid-stream and observe partial UI states.
class ScriptedLlmClient implements LlmClient {
  ScriptedLlmClient({
    required this.scripts,
    this.pacingDelay,
  });

  final List<List<LlmStreamEvent>> scripts;
  final Duration? pacingDelay;
  final List<List<Message>> historiesSeen = [];

  @override
  Future<Message> turn({
    required String systemPrompt,
    required List<Message> history,
    List<ToolDefinition> tools = const [],
  }) {
    throw UnimplementedError('non-streaming not exercised by chat tests');
  }

  @override
  Stream<LlmStreamEvent> streamTurn({
    required String systemPrompt,
    required List<Message> history,
    List<ToolDefinition> tools = const [],
  }) async* {
    historiesSeen.add(List.of(history));
    if (scripts.isEmpty) {
      throw StateError('ScriptedLlmClient: no more scripts');
    }
    final script = scripts.removeAt(0);
    for (final e in script) {
      if (pacingDelay != null) {
        await Future<void>.delayed(pacingDelay!);
      }
      yield e;
    }
  }
}

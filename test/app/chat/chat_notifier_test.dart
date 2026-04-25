import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/chat/chat_notifier.dart';
import 'package:petpal/app/chat/chat_state.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';
import 'package:petpal/harness/agent/tool_dispatcher.dart';

import '../../_helpers/scripted_llm_client.dart';

ProviderContainer _container({
  required ScriptedLlmClient llm,
  ToolDispatcher? tools,
}) {
  return ProviderContainer(
    overrides: [
      llmClientProvider.overrideWithValue(llm),
      toolDispatcherProvider.overrideWith(
        (ref) async => tools ?? ToolDispatcher(),
      ),
    ],
  );
}

void main() {
  test('send appends user turn, accumulates deltas, finalises history',
      () async {
    final llm = ScriptedLlmClient(
      scripts: [
        [
          const StreamMessageStart(),
          const StreamTextDelta('Hello, '),
          const StreamTextDelta('Milo!'),
          const StreamContentBlockStop(index: 0),
          const StreamMessageStop(stopReason: 'end_turn'),
        ],
      ],
    );

    final container = _container(llm: llm);
    addTearDown(container.dispose);

    expect(container.read(chatProvider).history, isEmpty);

    await container.read(chatProvider.notifier).send('hi');
    final state = container.read(chatProvider);

    expect(state.sending, isFalse);
    expect(state.streamingAssistant, isNull);
    expect(state.activeTools, isEmpty);

    final ui = state.uiMessages.toList();
    expect(ui, hasLength(2));
    expect(ui[0].role, ChatRole.user);
    expect(ui[0].text, 'hi');
    expect(ui[1].role, ChatRole.assistant);
    expect(ui[1].text, 'Hello, Milo!');
  });

  test('error during stream surfaces error and clears the streaming draft',
      () async {
    final llm = ScriptedLlmClient(scripts: const []);
    final container = _container(llm: llm);
    addTearDown(container.dispose);

    // Empty scripts → streamTurn throws StateError.
    await container.read(chatProvider.notifier).send('hi');
    final state = container.read(chatProvider);

    expect(state.error, isNotNull);
    expect(state.streamingAssistant, isNull);
    expect(state.sending, isFalse);
    expect(state.activeTools, isEmpty);
  });

  test('blank or whitespace-only input is a no-op', () async {
    final llm = ScriptedLlmClient(scripts: const []);
    final container = _container(llm: llm);
    addTearDown(container.dispose);

    await container.read(chatProvider.notifier).send('   ');
    expect(container.read(chatProvider).history, isEmpty);
    expect(llm.historiesSeen, isEmpty);
  });

  test('streaming buffer is observable mid-flight', () async {
    final llm = ScriptedLlmClient(
      scripts: [
        [
          const StreamMessageStart(),
          const StreamTextDelta('part 1 '),
          const StreamTextDelta('part 2'),
          const StreamContentBlockStop(index: 0),
          const StreamMessageStop(),
        ],
      ],
      pacingDelay: const Duration(milliseconds: 1),
    );

    final container = _container(llm: llm);
    addTearDown(container.dispose);

    final snapshots = <String?>[];
    final sub = container.listen<ChatState>(
      chatProvider,
      (_, next) => snapshots.add(next.streamingAssistant),
    );
    addTearDown(sub.close);

    await container.read(chatProvider.notifier).send('hi');

    expect(snapshots.where((s) => s == 'part 1 ').isNotEmpty, isTrue);
    expect(snapshots.last, isNull);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/chat/chat_notifier.dart';
import 'package:petpal/app/chat/chat_state.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';

import '../../_helpers/scripted_llm_client.dart';

void main() {
  test('send appends user message, accumulates assistant deltas, finalises '
      'on message_stop', () async {
    final llm = ScriptedLlmClient(
      scripts: [
        [
          const StreamMessageStart(),
          const StreamTextDelta('Hello, '),
          const StreamTextDelta('Milo!'),
          const StreamMessageStop(stopReason: 'end_turn', outputTokens: 4),
        ],
      ],
    );

    final container = ProviderContainer(
      overrides: [
        llmClientProvider.overrideWithValue(llm),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(chatProvider).messages, isEmpty);

    await container.read(chatProvider.notifier).send('hi');
    final state = container.read(chatProvider);

    expect(state.sending, isFalse);
    expect(state.streamingAssistant, isNull);
    expect(state.messages, hasLength(2));
    expect(state.messages[0].role, ChatRole.user);
    expect(state.messages[0].text, 'hi');
    expect(state.messages[1].role, ChatRole.assistant);
    expect(state.messages[1].text, 'Hello, Milo!');
  });

  test('error during stream surfaces error and clears the streaming draft',
      () async {
    final llm = ScriptedLlmClient(scripts: [[]]);
    // Override streamTurn-like with a throwing stream by using a script
    // that yields nothing, then triggering the post-stream finalize path
    // wouldn't surface the error. Instead, swap to a script the notifier
    // explicitly fails on: the second send hits an empty `scripts` list,
    // which throws StateError.

    final container = ProviderContainer(
      overrides: [
        llmClientProvider.overrideWithValue(llm),
      ],
    );
    addTearDown(container.dispose);

    // First send: empty script — finalises with no assistant text (draft
    // dropped because empty).
    await container.read(chatProvider.notifier).send('first');
    expect(container.read(chatProvider).messages, hasLength(1));
    expect(container.read(chatProvider).error, isNull);

    // Second send: scripts list is now empty — streamTurn throws.
    await container.read(chatProvider.notifier).send('second');
    final state = container.read(chatProvider);
    expect(state.error, isNotNull);
    expect(state.streamingAssistant, isNull);
    expect(state.sending, isFalse);
    // The user message stayed; the failed assistant draft was cleared.
    expect(state.messages.last.role, ChatRole.user);
    expect(state.messages.last.text, 'second');
  });

  test('blank or whitespace-only input is a no-op', () async {
    final llm = ScriptedLlmClient(scripts: const []);
    final container = ProviderContainer(
      overrides: [
        llmClientProvider.overrideWithValue(llm),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatProvider.notifier).send('   ');
    expect(container.read(chatProvider).messages, isEmpty);
    expect(llm.historiesSeen, isEmpty);
  });

  test('streaming state is observable mid-flight', () async {
    final llm = ScriptedLlmClient(
      scripts: [
        [
          const StreamMessageStart(),
          const StreamTextDelta('part 1 '),
          const StreamTextDelta('part 2'),
          const StreamMessageStop(),
        ],
      ],
      pacingDelay: const Duration(milliseconds: 1),
    );

    final container = ProviderContainer(
      overrides: [
        llmClientProvider.overrideWithValue(llm),
      ],
    );
    addTearDown(container.dispose);

    final snapshots = <String?>[];
    final sub = container.listen<ChatState>(
      chatProvider,
      (_, next) => snapshots.add(next.streamingAssistant),
    );
    addTearDown(sub.close);

    await container.read(chatProvider.notifier).send('hi');

    // We should have observed at least one intermediate streamingAssistant
    // value before the final null.
    expect(snapshots.where((s) => s == 'part 1 ').isNotEmpty, isTrue);
    expect(snapshots.last, isNull);
  });
}

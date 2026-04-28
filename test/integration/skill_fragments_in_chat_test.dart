// Phase 3.9 integration test (host-runnable). Walks chat → SessionBuilder
// → SkillLoader → fragment injection end-to-end with a fake LLM, against
// a stack containing both a dog-only and a cat-only skill. Verifies that
// only the dog skill's fragment lands in the LLM's system prompt for a
// dog pet — and the trigger words make a difference, not just species.
//
// Phase 1 + 2 on-device verification already exercises the real Anthropic
// path; this fills the host coverage gap that asset-backed
// AssetSkillSource leaves (no asset bundle in `flutter test`).

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/chat/chat_notifier.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/harness/agent/llm_client.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';
import 'package:petpal/harness/agent/messages.dart';
import 'package:petpal/harness/agent/tool_dispatcher.dart';
import 'package:petpal/harness/skills/skill_manifest.dart';
import 'package:petpal/harness/skills/skill_source.dart';

import '../_helpers/test_provider_scope.dart';

/// A scripted LLM that records every system prompt it received so the
/// test can assert what made it into the cached prefix.
class _RecordingLlm implements LlmClient {
  final List<String> systemPrompts = [];

  @override
  Future<Message> turn({
    required String systemPrompt,
    required List<Message> history,
    List<ToolDefinition> tools = const [],
  }) async {
    systemPrompts.add(systemPrompt);
    return const Message(
      role: 'assistant',
      content: [TextBlock('ack')],
    );
  }

  @override
  Stream<LlmStreamEvent> streamTurn({
    required String systemPrompt,
    required List<Message> history,
    List<ToolDefinition> tools = const [],
  }) async* {
    systemPrompts.add(systemPrompt);
    yield const StreamMessageStart();
    yield const StreamTextDelta('ack');
    yield const StreamContentBlockStop(index: 0);
    yield const StreamMessageStop(stopReason: 'end_turn');
  }
}

class _StaticSkillSource implements SkillSource {
  _StaticSkillSource(this._entries);
  final List<({SkillManifest manifest, Map<String, String> fragments})>
      _entries;

  @override
  Future<List<SkillSourceEntry>> list() async {
    return [
      for (final e in _entries)
        SkillSourceEntry(
          manifest: e.manifest,
          readFragment: (name) async => e.fragments[name]!,
        ),
    ];
  }
}

void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  testWidgets(
      'a chat trigger that matches a dog-only skill injects that '
      "skill's fragment into the system prompt for a dog pet, and never "
      "the cat-only skill's fragment", (tester) async {
    final llm = _RecordingLlm();

    final source = _StaticSkillSource([
      (
        manifest: const SkillManifest(
          id: 'puppy',
          name: 'Puppy Care',
          version: 1,
          category: ['dog'],
          triggers: ['house training', 'puppy'],
          loads: ['overview.md'],
          requiresPro: false,
        ),
        fragments: const {
          'overview.md': '# Puppy overview\nDOG-SKILL-FRAGMENT-MARKER',
        },
      ),
      (
        manifest: const SkillManifest(
          id: 'new-cat',
          name: 'New Cat',
          version: 1,
          category: ['cat'],
          triggers: ['house training', 'litter box'],
          loads: ['overview.md'],
          requiresPro: false,
        ),
        fragments: const {
          'overview.md': '# Cat overview\nCAT-SKILL-FRAGMENT-MARKER',
        },
      ),
    ]);

    // buildChatTestStack seeds a dog pet (category: dog SOUL.md).
    final stack = await buildChatTestStack(
      llm: llm,
      tools: ToolDispatcher(),
      skillSource: source,
    );

    final container = ProviderContainer(overrides: stack.overrides);
    addTearDown(container.dispose);
    await container.read(petsProvider.future);

    await container
        .read(chatProvider.notifier)
        .send('How do I house training my puppy?');

    expect(llm.systemPrompts, hasLength(1));
    final prompt = llm.systemPrompts.single;

    expect(prompt, contains('DOG-SKILL-FRAGMENT-MARKER'),
        reason: 'dog-only skill matched both species + trigger; should '
            'have injected its fragment');
    expect(prompt, isNot(contains('CAT-SKILL-FRAGMENT-MARKER')),
        reason: 'cat-only skill must be filtered out for a dog pet '
            'even though its trigger ("house training") matched');
  });

  testWidgets('an unrelated user message produces no skill fragments '
      'even when species-applicable skills exist', (tester) async {
    final llm = _RecordingLlm();
    final source = _StaticSkillSource([
      (
        manifest: const SkillManifest(
          id: 'puppy',
          name: 'Puppy Care',
          version: 1,
          category: ['dog'],
          triggers: ['puppy', 'house training'],
          loads: ['overview.md'],
          requiresPro: false,
        ),
        fragments: const {
          'overview.md': 'PUPPY-SKILL-MARKER',
        },
      ),
    ]);

    final stack = await buildChatTestStack(
      llm: llm,
      tools: ToolDispatcher(),
      skillSource: source,
    );

    final container = ProviderContainer(overrides: stack.overrides);
    addTearDown(container.dispose);
    await container.read(petsProvider.future);

    await container
        .read(chatProvider.notifier)
        .send('What is the weather like today?');

    final prompt = llm.systemPrompts.single;
    expect(prompt, isNot(contains('# Active skills')),
        reason: 'no trigger match → no Active skills section');
    expect(prompt, isNot(contains('PUPPY-SKILL-MARKER')));
  });
}

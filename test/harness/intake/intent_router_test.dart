import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/agent/llm_client.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';
import 'package:petpal/harness/agent/messages.dart';
import 'package:petpal/harness/intake/intent_router.dart';
import 'package:petpal/harness/vision/vision_gate.dart';

/// Phase 8 task 8.0 — intake intent router tests. Pure-Dart unit
/// tests with a hand-rolled mock LlmClient; no real network. The
/// locked behavior contract lives in
/// `lib/harness/intake/intent_router.dart`'s docstring (DECISIONS
/// row 104).

class _MockLlm implements LlmClient {
  _MockLlm({this.responseText, this.delay, this.shouldThrow = false});

  /// JSON text the mock returns. Null + shouldThrow=true → throws.
  final String? responseText;
  final Duration? delay;
  final bool shouldThrow;

  /// Captured turns for assertion.
  final List<({String systemPrompt, List<Message> history})> calls = [];

  @override
  Future<Message> turn({
    required String systemPrompt,
    required List<Message> history,
    List<ToolDefinition> tools = const [],
  }) async {
    calls.add((systemPrompt: systemPrompt, history: history));
    if (delay != null) await Future<void>.delayed(delay!);
    if (shouldThrow) throw StateError('mock transport error');
    return Message(
      role: Message.assistantRole,
      content: [TextBlock(responseText ?? '')],
    );
  }

  @override
  Stream<LlmStreamEvent> streamTurn({
    required String systemPrompt,
    required List<Message> history,
    List<ToolDefinition> tools = const [],
  }) async* {
    throw UnimplementedError('streaming not used by the intent router');
  }
}

class _BlockingGate implements VisionGate {
  @override
  Future<VisionGateDecision> check() async =>
      VisionGateDecision.blocked('test block');
}

void main() {
  Uint8List bytes() => Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

  group('Phase 8 task 8.0 — IntakeIntentRouter', () {
    group('explicit hint short-circuits the LLM call', () {
      for (final hint in IntakeIntent.values) {
        test('hint=$hint returns immediately without calling the LLM',
            () async {
          final llm = _MockLlm();
          final router = IntakeIntentRouter(
            llm: llm,
            gate: const StubVisionGate(),
          );

          final result = await router.resolve(
            imageBytes: bytes(),
            explicitHint: hint,
          );

          expect(result, hint);
          expect(llm.calls, isEmpty,
              reason: 'explicit hint must short-circuit before the LLM');
        });
      }
    });

    group('soft case — classifier dispatches to the returned intent', () {
      test('logMealAfter', () async {
        final llm = _MockLlm(responseText: '{"intent":"logMealAfter"}');
        final router = IntakeIntentRouter(
          llm: llm,
          gate: const StubVisionGate(),
        );

        final result = await router.resolve(imageBytes: bytes());

        expect(result, IntakeIntent.logMealAfter);
        expect(llm.calls, hasLength(1));
      });

      test('checkMealBefore', () async {
        final llm = _MockLlm(responseText: '{"intent":"checkMealBefore"}');
        final router = IntakeIntentRouter(
          llm: llm,
          gate: const StubVisionGate(),
        );

        final result = await router.resolve(imageBytes: bytes());

        expect(result, IntakeIntent.checkMealBefore);
      });

      test('generalMemory', () async {
        final llm = _MockLlm(responseText: '{"intent":"generalMemory"}');
        final router = IntakeIntentRouter(
          llm: llm,
          gate: const StubVisionGate(),
        );

        final result = await router.resolve(imageBytes: bytes());

        expect(result, IntakeIntent.generalMemory);
      });
    });

    test('passes the image as an ImageBlock + the locked system prompt '
        'with the three-class contract', () async {
      final llm = _MockLlm(responseText: '{"intent":"generalMemory"}');
      final router = IntakeIntentRouter(
        llm: llm,
        gate: const StubVisionGate(),
      );

      await router.resolve(imageBytes: bytes());

      expect(llm.calls, hasLength(1));
      final call = llm.calls.single;

      // System prompt anchors.
      expect(call.systemPrompt, contains('logMealAfter'));
      expect(call.systemPrompt, contains('checkMealBefore'));
      expect(call.systemPrompt, contains('generalMemory'));
      expect(call.systemPrompt, contains('Be conservative'));

      // History carries the image bytes.
      final blocks = call.history.single.content;
      expect(blocks.any((b) => b is ImageBlock), isTrue,
          reason: 'photo bytes go on the wire as an ImageBlock');
    });

    test('userCaption is threaded into the LLM user message as a '
        'TextBlock when non-empty', () async {
      final llm = _MockLlm(responseText: '{"intent":"checkMealBefore"}');
      final router = IntakeIntentRouter(
        llm: llm,
        gate: const StubVisionGate(),
      );

      await router.resolve(
        imageBytes: bytes(),
        userCaption: 'is this safe for Milo?',
      );

      final blocks = llm.calls.single.history.single.content;
      final captionBlock = blocks
          .whereType<TextBlock>()
          .firstWhere((t) => t.text.contains('Caption:'));
      expect(captionBlock.text, contains('is this safe for Milo?'));
    });

    test('userCaption is NOT added when it is empty or whitespace-only',
        () async {
      final llm = _MockLlm(responseText: '{"intent":"generalMemory"}');
      final router = IntakeIntentRouter(
        llm: llm,
        gate: const StubVisionGate(),
      );

      await router.resolve(imageBytes: bytes(), userCaption: '   ');

      final captionBlocks = llm.calls.single.history.single.content
          .whereType<TextBlock>()
          .where((t) => t.text.startsWith('Caption:'));
      expect(captionBlocks, isEmpty);
    });

    test('strips ```json code fences before parsing — model sometimes '
        'wraps despite the prompt forbidding it', () async {
      final llm = _MockLlm(responseText: '''
```json
{"intent":"logMealAfter"}
```
''');
      final router = IntakeIntentRouter(
        llm: llm,
        gate: const StubVisionGate(),
      );

      final result = await router.resolve(imageBytes: bytes());

      expect(result, IntakeIntent.logMealAfter);
    });

    group('always-safe fallbacks → generalMemory', () {
      test('malformed JSON', () async {
        final llm = _MockLlm(responseText: 'not json at all');
        final router = IntakeIntentRouter(
          llm: llm,
          gate: const StubVisionGate(),
        );
        final result = await router.resolve(imageBytes: bytes());
        expect(result, IntakeIntent.generalMemory);
      });

      test('JSON missing the intent field', () async {
        final llm = _MockLlm(responseText: '{"foo":"bar"}');
        final router = IntakeIntentRouter(
          llm: llm,
          gate: const StubVisionGate(),
        );
        final result = await router.resolve(imageBytes: bytes());
        expect(result, IntakeIntent.generalMemory);
      });

      test('unknown intent string drift (snake_case / synonym)', () async {
        final llm = _MockLlm(responseText: '{"intent":"snack"}');
        final router = IntakeIntentRouter(
          llm: llm,
          gate: const StubVisionGate(),
        );
        final result = await router.resolve(imageBytes: bytes());
        expect(result, IntakeIntent.generalMemory);
      });

      test('JSON-decodes to a non-object (e.g. a list or string)',
          () async {
        final llm = _MockLlm(responseText: '"logMealAfter"');
        final router = IntakeIntentRouter(
          llm: llm,
          gate: const StubVisionGate(),
        );
        final result = await router.resolve(imageBytes: bytes());
        expect(result, IntakeIntent.generalMemory);
      });

      test('LLM transport throws', () async {
        final llm = _MockLlm(shouldThrow: true);
        final router = IntakeIntentRouter(
          llm: llm,
          gate: const StubVisionGate(),
        );
        final result = await router.resolve(imageBytes: bytes());
        expect(result, IntakeIntent.generalMemory);
      });

      test('LLM call exceeds the timeout', () async {
        final llm = _MockLlm(
          responseText: '{"intent":"logMealAfter"}',
          delay: const Duration(milliseconds: 200),
        );
        final router = IntakeIntentRouter(
          llm: llm,
          gate: const StubVisionGate(),
          timeout: const Duration(milliseconds: 50),
        );
        final result = await router.resolve(imageBytes: bytes());
        expect(result, IntakeIntent.generalMemory);
      });

      test('VisionGate blocks — short-circuits before the LLM call',
          () async {
        final llm = _MockLlm(responseText: '{"intent":"logMealAfter"}');
        final router = IntakeIntentRouter(
          llm: llm,
          gate: _BlockingGate(),
        );

        final result = await router.resolve(imageBytes: bytes());

        expect(result, IntakeIntent.generalMemory);
        expect(llm.calls, isEmpty,
            reason: 'gate-block short-circuits before the LLM call');
      });
    });

    group('IntakeIntent.fromIdOrFallback drift tolerance', () {
      test('known names map to the matching enum value', () {
        expect(IntakeIntent.fromIdOrFallback('logMealAfter'),
            IntakeIntent.logMealAfter);
        expect(IntakeIntent.fromIdOrFallback('checkMealBefore'),
            IntakeIntent.checkMealBefore);
        expect(IntakeIntent.fromIdOrFallback('generalMemory'),
            IntakeIntent.generalMemory);
      });

      test('null falls back to generalMemory', () {
        expect(IntakeIntent.fromIdOrFallback(null),
            IntakeIntent.generalMemory);
      });

      test('unknown / drifted strings fall back to generalMemory', () {
        expect(IntakeIntent.fromIdOrFallback('snack'),
            IntakeIntent.generalMemory);
        expect(IntakeIntent.fromIdOrFallback('logmeal_after'),
            IntakeIntent.generalMemory);
        expect(IntakeIntent.fromIdOrFallback(''),
            IntakeIntent.generalMemory);
      });
    });
  });
}

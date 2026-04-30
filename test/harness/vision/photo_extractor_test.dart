import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/agent/llm_client.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';
import 'package:petpal/harness/agent/messages.dart';
import 'package:petpal/harness/vision/photo_extractor.dart';
import 'package:petpal/harness/vision/vision_gate.dart';

/// Phase 6 task 6.5 — fixtures for the photo extractor utility.
/// Uses a hand-rolled mock LlmClient that returns canned responses;
/// no real network. The locked schema lives in
/// `lib/harness/vision/photo_extractor.dart`'s docstring (DECISIONS
/// row 41).

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
    throw UnimplementedError('streaming not used by the photo extractor');
  }
}

void main() {
  Uint8List bytes() => Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

  group('Phase 6 task 6.5 — photo extractor', () {
    test('extract() parses a well-formed JSON response into a typed '
        'PhotoExtraction with the locked enum / list shape', () async {
      final llm = _MockLlm(responseText: '''
{
  "setting": "outdoors",
  "activity": "walking",
  "demeanor": "looks relaxed and curious",
  "notable_objects": ["leash", "frozen carrot"],
  "freeform_caption": "Loki at the trailhead.",
  "enrichment_hints": ["Was Loki excited the whole walk?"]
}
''');
      final extractor =
          PhotoExtractor(llm: llm, gate: const StubVisionGate());

      final result = await extractor.extract(imageBytes: bytes());

      expect(result, isNotNull);
      expect(result!.setting, PhotoSetting.outdoors);
      expect(result.activity, PhotoActivity.walking);
      expect(result.demeanor, 'looks relaxed and curious');
      expect(result.notableObjects, ['leash', 'frozen carrot']);
      expect(result.freeformCaption, 'Loki at the trailhead.');
      expect(result.enrichmentHints,
          ['Was Loki excited the whole walk?']);
    });

    test('passes the image as an ImageBlock + the locked system '
        'prompt that forbids diagnosis and requires hedged demeanor',
        () async {
      final llm = _MockLlm(responseText: '{}');
      final extractor =
          PhotoExtractor(llm: llm, gate: const StubVisionGate());

      await extractor.extract(imageBytes: bytes());

      expect(llm.calls, hasLength(1));
      final call = llm.calls.single;

      // System prompt anchors.
      expect(call.systemPrompt, contains('Never diagnose'));
      expect(call.systemPrompt, contains('Hedge demeanor'));
      expect(call.systemPrompt,
          contains("Don't invent objects"));

      // History carries the image bytes.
      final blocks = call.history.single.content;
      expect(blocks.any((b) => b is ImageBlock), isTrue,
          reason: 'photo bytes go on the wire as an ImageBlock');
    });

    test('userHint is forwarded as a steering TextBlock when '
        'non-empty', () async {
      final llm = _MockLlm(responseText: '{}');
      final extractor =
          PhotoExtractor(llm: llm, gate: const StubVisionGate());

      await extractor.extract(
        imageBytes: bytes(),
        userHint: 'Loki at the park, before the rain hit.',
      );

      final blocks = llm.calls.single.history.single.content;
      final hintBlock = blocks
          .whereType<TextBlock>()
          .firstWhere((t) => t.text.contains('caption draft'));
      expect(hintBlock.text,
          contains('Loki at the park, before the rain hit.'));
    });

    test('strips ```json code fences before parsing — the model '
        'sometimes wraps JSON despite the prompt saying not to',
        () async {
      final llm = _MockLlm(responseText: '''
```json
{
  "setting": "home",
  "activity": "resting",
  "demeanor": "",
  "notable_objects": [],
  "freeform_caption": "Loki on the couch.",
  "enrichment_hints": []
}
```
''');
      final extractor =
          PhotoExtractor(llm: llm, gate: const StubVisionGate());

      final result = await extractor.extract(imageBytes: bytes());
      expect(result, isNotNull);
      expect(result!.freeformCaption, 'Loki on the couch.');
    });

    test('returns null when the response is not parseable JSON', () async {
      final llm = _MockLlm(
        responseText: 'I cannot describe this photo.',
      );
      final extractor =
          PhotoExtractor(llm: llm, gate: const StubVisionGate());
      final result = await extractor.extract(imageBytes: bytes());
      expect(result, isNull);
    });

    test('returns null when the LLM transport throws', () async {
      final llm = _MockLlm(shouldThrow: true);
      final extractor =
          PhotoExtractor(llm: llm, gate: const StubVisionGate());
      final result = await extractor.extract(imageBytes: bytes());
      expect(result, isNull);
    });

    test('returns null when the call exceeds the 15s timeout — the '
        '6.6 form-preview save path uses this as the cutoff before '
        'falling back to bare freeform caption', () async {
      final llm = _MockLlm(
        responseText: '{}',
        delay: const Duration(milliseconds: 200),
      );
      final extractor = PhotoExtractor(
        llm: llm,
        gate: const StubVisionGate(),
        timeout: const Duration(milliseconds: 50),
      );
      final result = await extractor.extract(imageBytes: bytes());
      expect(result, isNull);
    });

    test('returns null when VisionGate blocks (Phase 7 entitlement '
        'failure path — Phase 6 stub never blocks but the wire is '
        'in place)', () async {
      final llm = _MockLlm(responseText: '{}');
      final blockingGate = _BlockingGate();
      final extractor =
          PhotoExtractor(llm: llm, gate: blockingGate);
      final result = await extractor.extract(imageBytes: bytes());
      expect(result, isNull);
      expect(llm.calls, isEmpty,
          reason: 'gate-block short-circuits before the LLM call');
    });

    test('unknown enum values map to "other" without dropping the '
        'extraction (resilience to model drift)', () async {
      final llm = _MockLlm(responseText: '''
{
  "setting": "kitchen",
  "activity": "playing",
  "demeanor": "looks curious",
  "notable_objects": [],
  "freeform_caption": "...",
  "enrichment_hints": []
}
''');
      final extractor =
          PhotoExtractor(llm: llm, gate: const StubVisionGate());
      final result = await extractor.extract(imageBytes: bytes());
      expect(result, isNotNull);
      expect(result!.setting, PhotoSetting.other,
          reason: 'unknown setting falls back to other');
      expect(result.activity, PhotoActivity.playing,
          reason: 'known activity preserved');
    });

    test('toFrontmatterPatch drops default / empty values so the '
        'sidecar stays minimal', () {
      // Construct directly (no LLM in this test).
      const minimal = PhotoExtraction(
        setting: PhotoSetting.other,
        activity: PhotoActivity.other,
        demeanor: null,
        notableObjects: [],
        freeformCaption: 'just a photo',
        enrichmentHints: [],
      );
      expect(minimal.toFrontmatterPatch(), isEmpty);

      const populated = PhotoExtraction(
        setting: PhotoSetting.outdoors,
        activity: PhotoActivity.walking,
        demeanor: 'looks alert',
        notableObjects: ['leash'],
        freeformCaption: 'walk',
        enrichmentHints: ['Was the trail busy?'],
      );
      final patch = populated.toFrontmatterPatch();
      expect(patch['setting'], 'outdoors');
      expect(patch['activity'], 'walking');
      expect(patch['demeanor'], 'looks alert');
      expect(patch['notable_objects'], ['leash']);
      expect(patch['enrichment_hints'], ['Was the trail busy?']);
    });
  });
}

class _BlockingGate implements VisionGate {
  @override
  Future<VisionGateDecision> check() async =>
      VisionGateDecision.blocked('test block');
}

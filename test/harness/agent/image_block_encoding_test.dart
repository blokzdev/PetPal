import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpal/harness/agent/anthropic_client.dart';
import 'package:petpal/harness/agent/messages.dart';

/// Phase 6 task 6.4 — wire-shape fixtures for the new ImageBlock
/// content variant. Capture the outbound HTTP request body via
/// MockClient and assert on the encoded JSON shape.

Stream<List<int>> _emptyStream() async* {
  yield utf8.encode(
    'event: message_start\n'
    'data: ${jsonEncode({
      'type': 'message_start',
      'message': {
        'id': 'm',
        'role': 'assistant',
        'content': <Object>[],
        'usage': {
          'input_tokens': 1,
          'output_tokens': 0,
          'cache_creation_input_tokens': 0,
          'cache_read_input_tokens': 0,
        },
      },
    })}\n\n',
  );
  yield utf8.encode(
    'event: message_delta\n'
    'data: ${jsonEncode({
      'type': 'message_delta',
      'delta': {'stop_reason': 'end_turn'},
      'usage': {'output_tokens': 0},
    })}\n\n',
  );
  yield utf8.encode(
    'event: message_stop\ndata: ${jsonEncode({'type': 'message_stop'})}\n\n',
  );
}

/// Run [history] through the client and return the captured outbound
/// request body, decoded as a JSON map. The Anthropic client already
/// finalizes the request before MockClient sees it; we read
/// `(req as http.Request).body` which is the pre-finalize string
/// representation.
Future<Map<String, Object?>> captureRequest(List<Message> history) async {
  final completer = Completer<Map<String, Object?>>();
  final mock = MockClient.streaming((req, _) async {
    final body = jsonDecode((req as http.Request).body) as Map<String, Object?>;
    if (!completer.isCompleted) completer.complete(body);
    return http.StreamedResponse(
      _emptyStream(),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  });
  final client = AnthropicClient(apiKey: 'test', httpClient: mock);
  await for (final _ in client.streamTurn(
    systemPrompt: 'You are PetPal.',
    history: history,
  )) {}
  return completer.future;
}

void main() {
  group('Phase 6 task 6.4 — ImageBlock encoding', () {
    test('ImageBlock encodes to Anthropic\'s base64-source shape with '
        'cache_control: ephemeral by default', () async {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      final body = await captureRequest([
        Message(role: 'user', content: [
          const TextBlock('Look at this:'),
          ImageBlock(bytes: bytes),
        ]),
      ]);

      final messages = body['messages'] as List<Object?>;
      expect(messages, hasLength(1));
      final content = (messages.single as Map<String, Object?>)['content']
          as List<Object?>;
      expect(content, hasLength(2));

      // First block: text, untouched.
      expect((content[0] as Map<String, Object?>)['type'], 'text');
      expect((content[0] as Map<String, Object?>)['text'], 'Look at this:');

      // Second block: image, base64-encoded source.
      final imageBlock = content[1] as Map<String, Object?>;
      expect(imageBlock['type'], 'image');
      final source = imageBlock['source'] as Map<String, Object?>;
      expect(source['type'], 'base64');
      expect(source['media_type'], 'image/jpeg');
      expect(source['data'], base64Encode(bytes));

      // Default cache_control = ephemeral (prompt-cache eligibility on
      // multi-image conversations).
      final cc = imageBlock['cache_control'] as Map<String, Object?>?;
      expect(cc, isNotNull);
      expect(cc!['type'], 'ephemeral');
    });

    test('ImageBlock with cacheControl: false omits the cache_control '
        'key (one-shot images that don\'t need cache eligibility)',
        () async {
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final body = await captureRequest([
        Message(role: 'user', content: [
          ImageBlock(bytes: bytes, cacheControl: false),
        ]),
      ]);

      final imageBlock =
          ((body['messages'] as List).single as Map<String, Object?>)['content']
              as List<Object?>;
      final block = imageBlock.single as Map<String, Object?>;
      expect(block['type'], 'image');
      expect(block.containsKey('cache_control'), isFalse,
          reason: 'cache_control omitted when cacheControl: false');
    });

    test('ImageBlock with explicit mediaType honors the override (PNG '
        'profile photo path)', () async {
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final body = await captureRequest([
        Message(role: 'user', content: [
          ImageBlock(bytes: pngBytes, mediaType: 'image/png'),
        ]),
      ]);
      final block =
          (((body['messages'] as List).single as Map<String, Object?>)['content']
                  as List<Object?>)
              .single as Map<String, Object?>;
      final source = block['source'] as Map<String, Object?>;
      expect(source['media_type'], 'image/png');
    });

    test('TextBlock encoding is unchanged by the ImageBlock addition '
        '(regression guard for the existing chat path)', () async {
      final body = await captureRequest([
        const Message(role: 'user', content: [TextBlock('hi')]),
      ]);
      final block =
          (((body['messages'] as List).single as Map<String, Object?>)['content']
                  as List<Object?>)
              .single as Map<String, Object?>;
      expect(block['type'], 'text');
      expect(block['text'], 'hi');
      // Text blocks NEVER carry cache_control in our encoder.
      expect(block.containsKey('cache_control'), isFalse);
    });
  });
}

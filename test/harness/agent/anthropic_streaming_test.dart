import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpal/harness/agent/anthropic_client.dart';
import 'package:petpal/harness/agent/llm_stream_event.dart';
import 'package:petpal/harness/agent/messages.dart';

/// Builds an SSE byte stream from a list of `(event, payload)` pairs in
/// the shape Anthropic's stream endpoint emits.
Stream<List<int>> _sse(List<({String event, Map<String, Object?> data})> frames) async* {
  for (final f in frames) {
    final body = 'event: ${f.event}\n'
        'data: ${jsonEncode(f.data)}\n'
        '\n';
    yield utf8.encode(body);
  }
}

void main() {
  test('streamTurn yields text deltas in order, then a stop event',
      () async {
    final mock = MockClient.streaming((req, _) async {
      return http.StreamedResponse(
        _sse([
          (event: 'message_start', data: {
            'type': 'message_start',
            'message': {
              'id': 'msg_1',
              'role': 'assistant',
              'content': <Object>[],
              'usage': {
                'input_tokens': 12,
                'output_tokens': 0,
                'cache_creation_input_tokens': 0,
                'cache_read_input_tokens': 8,
              },
            },
          }),
          (event: 'content_block_start', data: {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'text', 'text': ''},
          }),
          (event: 'content_block_delta', data: {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'Hello'},
          }),
          (event: 'content_block_delta', data: {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': ', Milo'},
          }),
          (event: 'content_block_stop', data: {
            'type': 'content_block_stop',
            'index': 0,
          }),
          (event: 'message_delta', data: {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 7},
          }),
          (event: 'message_stop', data: {'type': 'message_stop'}),
        ]),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final client = AnthropicClient(apiKey: 'test', httpClient: mock);

    final events = <LlmStreamEvent>[];
    await for (final e in client.streamTurn(
      systemPrompt: 'You are PetPal.',
      history: const [
        Message(role: 'user', content: [TextBlock('Hi.')]),
      ],
    )) {
      events.add(e);
    }

    // First a message_start, then two text deltas in arrival order, then a
    // message_stop.
    expect(events.whereType<StreamMessageStart>(), hasLength(1));
    final deltas = events.whereType<StreamTextDelta>().toList();
    expect(deltas.map((d) => d.text), ['Hello', ', Milo']);
    final stops = events.whereType<StreamMessageStop>().toList();
    expect(stops, hasLength(1));
    expect(stops.single.stopReason, 'end_turn');
    expect(stops.single.outputTokens, 7);

    // Cache usage from message_start was captured.
    expect(client.lastUsage?.cacheReadInputTokens, 8);
  });

  test('streamTurn throws AnthropicApiException on a non-200 response',
      () async {
    final mock = MockClient.streaming((req, _) async {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({
          'type': 'error',
          'error': {'type': 'authentication_error', 'message': 'bad key'},
        }))),
        401,
      );
    });
    final client = AnthropicClient(apiKey: 'bad', httpClient: mock);

    await expectLater(
      () async {
        await for (final _ in client.streamTurn(
          systemPrompt: 'sys',
          history: const [
            Message(role: 'user', content: [TextBlock('hi')]),
          ],
        )) {}
      },
      throwsA(isA<AnthropicApiException>()
          .having((e) => e.statusCode, 'statusCode', 401)
          .having((e) => e.errorType, 'errorType', 'authentication_error')),
    );
  });

  test('streamTurn ignores unknown event types and tolerates blank lines',
      () async {
    final mock = MockClient.streaming((req, _) async {
      return http.StreamedResponse(
        Stream.value(utf8.encode(
          'event: ping\ndata: {"type":"ping"}\n\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,'
          '"delta":{"type":"text_delta","text":"ok"}}\n\n'
          'event: message_stop\ndata: {"type":"message_stop"}\n\n',
        )),
        200,
      );
    });
    final client = AnthropicClient(apiKey: 'test', httpClient: mock);

    final deltas = <String>[];
    await for (final e in client.streamTurn(
      systemPrompt: 'sys',
      history: const [
        Message(role: 'user', content: [TextBlock('hi')]),
      ],
    )) {
      if (e is StreamTextDelta) deltas.add(e.text);
    }
    expect(deltas, ['ok']);
  });
}

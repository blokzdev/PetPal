import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpal/harness/agent/anthropic_client.dart';
import 'package:petpal/harness/agent/llm_transport.dart';
import 'package:petpal/harness/agent/messages.dart';
import 'package:petpal/harness/agent/proxy_transport.dart';

const _supabaseUrl = 'https://abc.supabase.co';
const _anonKey = 'eyJhbGc-fake-anon';
const _jwt = 'eyJhbGc-fake-jwt';
const _device = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

http.Response _ok(Map<String, Object?> body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

http.Response _err(int status, String code, [String? detail]) {
  final errorBody = <String, Object?>{'code': code};
  if (detail != null) errorBody['detail'] = detail;
  return http.Response(
    jsonEncode({'error': errorBody}),
    status,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, Object?> _stubAssistant(String text) => {
      'role': 'assistant',
      'content': [
        {'type': 'text', 'text': text},
      ],
      'usage': {
        'input_tokens': 50,
        'output_tokens': 10,
        'cache_creation_input_tokens': 0,
        'cache_read_input_tokens': 40,
      },
    };

void main() {
  group('ProxyTransport — type identity', () {
    test('extends LlmTransport', () {
      final t = ProxyTransport(
        supabaseUrl: _supabaseUrl,
        supabaseAnonKey: _anonKey,
        deviceToken: _device,
        httpClient: MockClient((_) async => _ok(_stubAssistant('hi'))),
      );
      expect(t, isA<LlmTransport>());
      t.close();
    });

    test('AnthropicClient also extends LlmTransport (A.3.1 abstraction)', () {
      final t = AnthropicClient(apiKey: 'sk-ant-x');
      expect(t, isA<LlmTransport>());
      t.close();
    });

    test('rejects construction with both userJwt and deviceToken null', () {
      expect(
        () => ProxyTransport(
          supabaseUrl: _supabaseUrl,
          supabaseAnonKey: _anonKey,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ProxyTransport.turn — request shape', () {
    test('POSTs to <supabaseUrl>/functions/v1/llm-proxy', () async {
      late http.Request seen;
      final mock = MockClient((req) async {
        seen = req;
        return _ok(_stubAssistant('hi'));
      });
      final t = ProxyTransport(
        supabaseUrl: _supabaseUrl,
        supabaseAnonKey: _anonKey,
        deviceToken: _device,
        httpClient: mock,
      );

      await t.turn(systemPrompt: 's', history: [Message.userText('hi')]);

      expect(seen.method, 'POST');
      expect(
        seen.url.toString(),
        '$_supabaseUrl/functions/v1/llm-proxy',
        reason: 'must hit the Edge Function URL, not Anthropic directly',
      );
    });

    test('signed-in path — sends Authorization Bearer + apikey, '
        'no x-petpal-device-token', () async {
      late http.Request seen;
      final mock = MockClient((req) async {
        seen = req;
        return _ok(_stubAssistant('hi'));
      });
      final t = ProxyTransport(
        supabaseUrl: _supabaseUrl,
        supabaseAnonKey: _anonKey,
        userJwt: _jwt,
        httpClient: mock,
      );

      await t.turn(systemPrompt: 's', history: [Message.userText('hi')]);

      expect(seen.headers['apikey'], _anonKey);
      expect(seen.headers['authorization'], 'Bearer $_jwt');
      expect(seen.headers.containsKey('x-petpal-device-token'), isFalse);
      expect(
        seen.headers.containsKey('x-api-key'),
        isFalse,
        reason: "ProxyTransport must NOT send Anthropic's master key — "
            'the Edge Function holds it server-side',
      );
    });

    test('anonymous path — sends x-petpal-device-token + apikey, '
        'no Authorization', () async {
      late http.Request seen;
      final mock = MockClient((req) async {
        seen = req;
        return _ok(_stubAssistant('hi'));
      });
      final t = ProxyTransport(
        supabaseUrl: _supabaseUrl,
        supabaseAnonKey: _anonKey,
        deviceToken: _device,
        httpClient: mock,
      );

      await t.turn(systemPrompt: 's', history: [Message.userText('hi')]);

      expect(seen.headers['apikey'], _anonKey);
      expect(seen.headers['x-petpal-device-token'], _device);
      expect(seen.headers.containsKey('authorization'), isFalse);
    });

    test('preserves cache_control on system prompt — passthrough invariant',
        () async {
      // The core regression guard. Losing cache_control = >70% cost
      // regression per CLAUDE.md §6 + DECISIONS row 82.
      late Map<String, Object?> body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, Object?>;
        return _ok(_stubAssistant('hi'));
      });
      final t = ProxyTransport(
        supabaseUrl: _supabaseUrl,
        supabaseAnonKey: _anonKey,
        deviceToken: _device,
        httpClient: mock,
      );

      await t.turn(
        systemPrompt: 'You are PetPal.',
        history: [Message.userText('hi')],
      );

      final systemBlocks = body['system']! as List<Object?>;
      expect(systemBlocks, hasLength(1));
      final block = systemBlocks.first! as Map<String, Object?>;
      expect(block['cache_control'], {'type': 'ephemeral'},
          reason: 'cache_control block must reach the Edge Function intact');
    });

    test('body shape matches AnthropicClient (model, max_tokens, messages)',
        () async {
      late Map<String, Object?> body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, Object?>;
        return _ok(_stubAssistant('hi'));
      });
      final t = ProxyTransport(
        supabaseUrl: _supabaseUrl,
        supabaseAnonKey: _anonKey,
        deviceToken: _device,
        httpClient: mock,
      );

      await t.turn(systemPrompt: 's', history: [Message.userText('hi')]);

      expect(body['model'], 'claude-sonnet-4-6');
      expect(body['max_tokens'], 4096);
      expect(body['messages'], isA<List<Object?>>());
    });
  });

  group('ProxyTransport.turn — quota / rate-limit error mapping', () {
    test('402 monthly_cap_exceeded → AnthropicApiException(statusCode: 402)',
        () async {
      final mock = MockClient(
        (_) async => _err(402, 'monthly_cap_exceeded', '{"cap":200,"count":200}'),
      );
      final t = ProxyTransport(
        supabaseUrl: _supabaseUrl,
        supabaseAnonKey: _anonKey,
        deviceToken: _device,
        httpClient: mock,
      );

      try {
        await t.turn(systemPrompt: 's', history: [Message.userText('hi')]);
        fail('expected AnthropicApiException');
      } on AnthropicApiException catch (e) {
        expect(e.statusCode, 402);
        expect(e.errorType, 'monthly_cap_exceeded');
      }
    });

    test('429 rate_limited → AnthropicApiException(statusCode: 429)',
        () async {
      final mock = MockClient((_) async => _err(429, 'rate_limited'));
      final t = ProxyTransport(
        supabaseUrl: _supabaseUrl,
        supabaseAnonKey: _anonKey,
        deviceToken: _device,
        httpClient: mock,
      );

      try {
        await t.turn(systemPrompt: 's', history: [Message.userText('hi')]);
        fail('expected AnthropicApiException');
      } on AnthropicApiException catch (e) {
        expect(e.statusCode, 429);
        expect(e.errorType, 'rate_limited');
      }
    });

    test('403 banned → AnthropicApiException(statusCode: 403)', () async {
      final mock = MockClient((_) async => _err(403, 'banned'));
      final t = ProxyTransport(
        supabaseUrl: _supabaseUrl,
        supabaseAnonKey: _anonKey,
        deviceToken: _device,
        httpClient: mock,
      );

      try {
        await t.turn(systemPrompt: 's', history: [Message.userText('hi')]);
        fail('expected AnthropicApiException');
      } on AnthropicApiException catch (e) {
        expect(e.statusCode, 403);
      }
    });
  });

  group('ProxyTransport.turn — response decoding', () {
    test('returns the assistant message with a TextBlock', () async {
      final mock = MockClient(
        (_) async => _ok(_stubAssistant('Hello, Loki!')),
      );
      final t = ProxyTransport(
        supabaseUrl: _supabaseUrl,
        supabaseAnonKey: _anonKey,
        deviceToken: _device,
        httpClient: mock,
      );

      final reply = await t.turn(
        systemPrompt: 's',
        history: [Message.userText('hi')],
      );

      expect(reply.role, Message.assistantRole);
      expect(reply.content, hasLength(1));
      expect(reply.content.first, isA<TextBlock>());
      expect((reply.content.first as TextBlock).text, 'Hello, Loki!');
    });

    test('surfaces AnthropicUsage for cache-hit-rate dashboards', () async {
      final mock = MockClient(
        (_) async => _ok(_stubAssistant('hi')),
      );
      final t = ProxyTransport(
        supabaseUrl: _supabaseUrl,
        supabaseAnonKey: _anonKey,
        deviceToken: _device,
        httpClient: mock,
      );

      await t.turn(systemPrompt: 's', history: [Message.userText('hi')]);
      expect(t.lastUsage, isNotNull);
      expect(t.lastUsage!.inputTokens, 50);
      expect(t.lastUsage!.outputTokens, 10);
      expect(t.lastUsage!.cacheReadInputTokens, 40);
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpal/harness/agent/anthropic_client.dart';
import 'package:petpal/harness/agent/messages.dart';

http.Response _ok(Map<String, Object?> body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

http.Response _error(int status, String type, String message) =>
    http.Response(
      jsonEncode({
        'type': 'error',
        'error': {'type': type, 'message': message},
      }),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, Object?> _stubAssistantText(
  String text, {
  Map<String, Object?>? usage,
}) =>
    {
      'role': 'assistant',
      'content': [
        {'type': 'text', 'text': text},
      ],
      'usage': usage ??
          {
            'input_tokens': 10,
            'output_tokens': 5,
            'cache_creation_input_tokens': 0,
            'cache_read_input_tokens': 0,
          },
    };

void main() {
  group('AnthropicClient.turn — request shape', () {
    test('hits POST /v1/messages with the right headers', () async {
      late http.Request seen;
      final mock = MockClient((req) async {
        seen = req;
        return _ok(_stubAssistantText('hi'));
      });
      final client = AnthropicClient(apiKey: 'sk-test', httpClient: mock);

      await client.turn(
        systemPrompt: 's',
        history: [Message.userText('hi')],
      );

      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(seen.headers['x-api-key'], 'sk-test');
      expect(seen.headers['anthropic-version'], '2023-06-01');
      expect(seen.headers['content-type'], contains('application/json'));
    });

    test('wraps systemPrompt in a single text block with cache_control '
        'ephemeral', () async {
      late Map<String, Object?> body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, Object?>;
        return _ok(_stubAssistantText('ok'));
      });
      final client = AnthropicClient(apiKey: 'sk-test', httpClient: mock);

      await client.turn(
        systemPrompt: 'You are PetPal.',
        history: [Message.userText('hi')],
      );

      expect(body['system'], isA<List<Object?>>());
      final systemBlocks = body['system']! as List<Object?>;
      expect(systemBlocks, hasLength(1));
      final block = systemBlocks.first! as Map<String, Object?>;
      expect(block['type'], 'text');
      expect(block['text'], 'You are PetPal.');
      expect(block['cache_control'], {'type': 'ephemeral'});
    });

    test('defaults model to claude-sonnet-4-6', () async {
      late Map<String, Object?> body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, Object?>;
        return _ok(_stubAssistantText('ok'));
      });
      final client = AnthropicClient(apiKey: 'sk-test', httpClient: mock);

      await client.turn(systemPrompt: 's', history: [Message.userText('hi')]);

      expect(body['model'], 'claude-sonnet-4-6');
    });

    test('encodes user, assistant, tool_use, and tool_result blocks',
        () async {
      late Map<String, Object?> body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, Object?>;
        return _ok(_stubAssistantText('ok'));
      });
      final client = AnthropicClient(apiKey: 'sk-test', httpClient: mock);

      await client.turn(
        systemPrompt: 's',
        history: const [
          Message(
            role: Message.userRole,
            content: [TextBlock("Find Milo's vet visits")],
          ),
          Message(
            role: Message.assistantRole,
            content: [
              TextBlock('Looking it up.'),
              ToolUseBlock(
                id: 'tu_1',
                name: 'search_wiki',
                input: {'query': 'vet'},
              ),
            ],
          ),
          Message(
            role: Message.userRole,
            content: [
              ToolResultBlock(
                toolUseId: 'tu_1',
                content: '[{"path":"wiki/1/vet/...md"}]',
              ),
            ],
          ),
        ],
      );

      final messages = body['messages']! as List<Object?>;
      expect(messages, hasLength(3));

      final asst = messages[1]! as Map<String, Object?>;
      expect(asst['role'], 'assistant');
      final asstContent = asst['content']! as List<Object?>;
      expect(asstContent, hasLength(2));
      expect(
        asstContent[1],
        {
          'type': 'tool_use',
          'id': 'tu_1',
          'name': 'search_wiki',
          'input': {'query': 'vet'},
        },
      );

      final toolMsg = messages[2]! as Map<String, Object?>;
      final toolContent = (toolMsg['content']! as List<Object?>).first!
          as Map<String, Object?>;
      expect(toolContent['type'], 'tool_result');
      expect(toolContent['tool_use_id'], 'tu_1');
      expect(toolContent['content'], '[{"path":"wiki/1/vet/...md"}]');
    });

    test('serializes tool definitions in the canonical Anthropic shape',
        () async {
      late Map<String, Object?> body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, Object?>;
        return _ok(_stubAssistantText('ok'));
      });
      final client = AnthropicClient(apiKey: 'sk-test', httpClient: mock);

      await client.turn(
        systemPrompt: 's',
        history: [Message.userText('hi')],
        tools: const [
          ToolDefinition(
            name: 'read_wiki',
            description: 'Read the markdown body at a wiki path.',
            inputSchema: {
              'type': 'object',
              'properties': {
                'path': {'type': 'string'},
              },
              'required': ['path'],
            },
          ),
        ],
      );

      final tools = body['tools']! as List<Object?>;
      expect(tools, hasLength(1));
      final tool = tools.first! as Map<String, Object?>;
      expect(tool['name'], 'read_wiki');
      expect(tool['description'], isA<String>());
      expect(tool['input_schema'], isA<Map<Object?, Object?>>());
    });

    test('omits the tools key entirely when no tools are passed', () async {
      late Map<String, Object?> body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, Object?>;
        return _ok(_stubAssistantText('ok'));
      });
      final client = AnthropicClient(apiKey: 'sk-test', httpClient: mock);

      await client.turn(systemPrompt: 's', history: [Message.userText('hi')]);
      expect(body.containsKey('tools'), isFalse);
    });
  });

  group('AnthropicClient.turn — response parsing', () {
    test('decodes a text-only assistant response', () async {
      final mock = MockClient((req) async => _ok({
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'Hello Milo.'},
            ],
            'usage': {
              'input_tokens': 12,
              'output_tokens': 3,
              'cache_creation_input_tokens': 0,
              'cache_read_input_tokens': 0,
            },
          }));
      final client = AnthropicClient(apiKey: 'sk-test', httpClient: mock);

      final msg = await client.turn(
        systemPrompt: 's',
        history: [Message.userText('hi')],
      );

      expect(msg.role, Message.assistantRole);
      expect(msg.text, 'Hello Milo.');
      expect(msg.toolUses, isEmpty);
    });

    test('decodes interleaved text + tool_use blocks', () async {
      final mock = MockClient((req) async => _ok({
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': "Let me check Milo's wiki."},
              {
                'type': 'tool_use',
                'id': 'toolu_abc',
                'name': 'search_wiki',
                'input': {'query': 'carrot'},
              },
            ],
            'usage': {
              'input_tokens': 1,
              'output_tokens': 1,
              'cache_creation_input_tokens': 0,
              'cache_read_input_tokens': 0,
            },
          }));
      final client = AnthropicClient(apiKey: 'sk-test', httpClient: mock);

      final msg = await client.turn(
        systemPrompt: 's',
        history: [Message.userText('hi')],
      );

      expect(msg.text, "Let me check Milo's wiki.");
      final tu = msg.toolUses.single;
      expect(tu.id, 'toolu_abc');
      expect(tu.name, 'search_wiki');
      expect(tu.input, {'query': 'carrot'});
    });

    test('skips unknown block types (e.g. thinking) without throwing',
        () async {
      final mock = MockClient((req) async => _ok({
            'role': 'assistant',
            'content': [
              {'type': 'thinking', 'thinking': '...'},
              {'type': 'text', 'text': 'Hi.'},
            ],
            'usage': {
              'input_tokens': 1,
              'output_tokens': 1,
              'cache_creation_input_tokens': 0,
              'cache_read_input_tokens': 0,
            },
          }));
      final client = AnthropicClient(apiKey: 'sk-test', httpClient: mock);
      final msg = await client.turn(
        systemPrompt: 's',
        history: [Message.userText('hi')],
      );
      expect(msg.text, 'Hi.');
    });

    test('exposes cache hit/miss counts via lastUsage', () async {
      final mock = MockClient((req) async => _ok({
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'cached.'},
            ],
            'usage': {
              'input_tokens': 5,
              'output_tokens': 7,
              'cache_creation_input_tokens': 0,
              'cache_read_input_tokens': 1234,
            },
          }));
      final client = AnthropicClient(apiKey: 'sk-test', httpClient: mock);

      await client.turn(systemPrompt: 's', history: [Message.userText('hi')]);
      expect(client.lastUsage, isNotNull);
      expect(client.lastUsage!.cacheReadInputTokens, 1234);
      expect(client.lastUsage!.outputTokens, 7);
    });
  });

  group('AnthropicClient.turn — errors', () {
    test('throws AnthropicApiException with errorType on 401', () async {
      final mock = MockClient(
        (req) async => _error(401, 'authentication_error', 'invalid x-api-key'),
      );
      final client = AnthropicClient(apiKey: 'sk-bad', httpClient: mock);

      try {
        await client.turn(
          systemPrompt: 's',
          history: [Message.userText('hi')],
        );
        fail('expected AnthropicApiException');
      } on AnthropicApiException catch (e) {
        expect(e.statusCode, 401);
        expect(e.errorType, 'authentication_error');
        expect(e.message, contains('invalid x-api-key'));
      }
    });

    test('throws on 429 rate limit', () async {
      final mock = MockClient(
        (req) async => _error(429, 'rate_limit_error', 'too many requests'),
      );
      final client = AnthropicClient(apiKey: 'sk-test', httpClient: mock);

      await expectLater(
        client.turn(systemPrompt: 's', history: [Message.userText('hi')]),
        throwsA(isA<AnthropicApiException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.errorType, 'errorType', 'rate_limit_error')),
      );
    });

    test('handles a non-JSON error body without crashing', () async {
      final mock = MockClient(
        (req) async => http.Response('Bad Gateway', 502),
      );
      final client = AnthropicClient(apiKey: 'sk-test', httpClient: mock);

      await expectLater(
        client.turn(systemPrompt: 's', history: [Message.userText('hi')]),
        throwsA(isA<AnthropicApiException>()
            .having((e) => e.statusCode, 'statusCode', 502)
            .having((e) => e.errorType, 'errorType', isNull)
            .having((e) => e.message, 'message', 'Bad Gateway')),
      );
    });
  });
}

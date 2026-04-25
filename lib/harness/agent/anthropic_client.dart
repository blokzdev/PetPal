import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_client.dart';
import 'messages.dart';

/// Default model. CLAUDE.md positions PetPal as a chat agent; Sonnet is the
/// best speed/intelligence balance for conversational pet-care guidance.
const _defaultModel = 'claude-sonnet-4-6';

/// Conservative output ceiling. Keeps responses under SDK HTTP timeout for
/// non-streaming requests (per Anthropic SDK guidance, ~16K is the upper
/// bound before streaming becomes mandatory).
const _defaultMaxTokens = 4096;

const _apiVersion = '2023-06-01';

/// Token-usage stats from the most recent turn. Surfaced separately from
/// [Message] so cache-hit-rate can be inspected without cluttering the
/// [LlmClient] contract that [AgentLoop] consumes.
class AnthropicUsage {
  AnthropicUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheCreationInputTokens,
    required this.cacheReadInputTokens,
  });

  factory AnthropicUsage.fromJson(Map<String, Object?> json) => AnthropicUsage(
        inputTokens: (json['input_tokens'] as num?)?.toInt() ?? 0,
        outputTokens: (json['output_tokens'] as num?)?.toInt() ?? 0,
        cacheCreationInputTokens:
            (json['cache_creation_input_tokens'] as num?)?.toInt() ?? 0,
        cacheReadInputTokens:
            (json['cache_read_input_tokens'] as num?)?.toInt() ?? 0,
      );

  final int inputTokens;
  final int outputTokens;
  final int cacheCreationInputTokens;
  final int cacheReadInputTokens;
}

/// Thrown when the Anthropic API returns a non-2xx response or an unparseable
/// body. [statusCode] is the HTTP status; [errorType] is the API's
/// `error.type` (e.g. `invalid_request_error`, `authentication_error`,
/// `rate_limit_error`).
class AnthropicApiException implements Exception {
  AnthropicApiException({
    required this.statusCode,
    required this.message,
    this.errorType,
  });

  final int statusCode;
  final String message;
  final String? errorType;

  @override
  String toString() =>
      'AnthropicApiException($statusCode${errorType != null ? ' $errorType' : ''}): $message';
}

/// Thin, non-streaming Anthropic Messages API client. Implements [LlmClient]
/// so [AgentLoop] can drive it without knowing it talks to Anthropic.
///
/// Prompt caching: every call wraps [systemPrompt] in a single text block
/// with `cache_control: {type: "ephemeral"}`. The render order is
/// `tools` → `system` → `messages`, so a `cache_control` marker on the last
/// (only) system block caches *both* tools and system together. Keep
/// `systemPrompt` byte-stable across turns and the cache will accrue —
/// SessionBuilder in 1.11 takes responsibility for that, putting volatile
/// content (retrieved snippets) in the messages array instead of the system
/// prompt.
///
/// Streaming is intentionally out of scope for Phase 1.10 — Phase 1.13's dev
/// screen tolerates blocking turns. A streaming `turn` lands later when the
/// chat UI in Phase 2 needs token-level rendering.
class AnthropicClient implements LlmClient {
  AnthropicClient({
    required String apiKey,
    this.model = _defaultModel,
    this.maxTokens = _defaultMaxTokens,
    this.baseUrl = 'https://api.anthropic.com',
    http.Client? httpClient,
  })  : _apiKey = apiKey,
        _http = httpClient ?? http.Client();

  final String _apiKey;
  final http.Client _http;
  final String model;
  final int maxTokens;
  final String baseUrl;

  AnthropicUsage? _lastUsage;

  /// Token usage from the most recent successful turn. Null until the first
  /// turn lands. Useful for cache-hit-rate dashboards.
  AnthropicUsage? get lastUsage => _lastUsage;

  @override
  Future<Message> turn({
    required String systemPrompt,
    required List<Message> history,
    List<ToolDefinition> tools = const [],
  }) async {
    final body = <String, Object?>{
      'model': model,
      'max_tokens': maxTokens,
      'system': [
        {
          'type': 'text',
          'text': systemPrompt,
          'cache_control': {'type': 'ephemeral'},
        },
      ],
      'messages': [for (final m in history) _encodeMessage(m)],
      if (tools.isNotEmpty)
        'tools': [
          for (final t in tools)
            {
              'name': t.name,
              'description': t.description,
              'input_schema': t.inputSchema,
            },
        ],
    };

    final response = await _http.post(
      Uri.parse('$baseUrl/v1/messages'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': _apiKey,
        'anthropic-version': _apiVersion,
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw _errorFromResponse(response);
    }

    final decoded = jsonDecode(response.body) as Map<String, Object?>;
    final usage = decoded['usage'];
    if (usage is Map<String, Object?>) {
      _lastUsage = AnthropicUsage.fromJson(usage);
    }
    return _decodeMessage(decoded);
  }

  void close() => _http.close();

  // ---- encoding -----------------------------------------------------------

  Map<String, Object?> _encodeMessage(Message m) => {
        'role': m.role,
        'content': [for (final block in m.content) _encodeBlock(block)],
      };

  Map<String, Object?> _encodeBlock(ContentBlock block) {
    switch (block) {
      case TextBlock(:final text):
        return {'type': 'text', 'text': text};
      case ToolUseBlock(:final id, :final name, :final input):
        return {
          'type': 'tool_use',
          'id': id,
          'name': name,
          'input': input,
        };
      case ToolResultBlock(:final toolUseId, :final content, :final isError):
        return {
          'type': 'tool_result',
          'tool_use_id': toolUseId,
          'content': content,
          if (isError) 'is_error': true,
        };
    }
  }

  // ---- decoding -----------------------------------------------------------

  Message _decodeMessage(Map<String, Object?> json) {
    final role = json['role'] as String? ?? Message.assistantRole;
    final rawContent = json['content'];
    final blocks = <ContentBlock>[];
    if (rawContent is List) {
      for (final entry in rawContent) {
        if (entry is Map<String, Object?>) {
          final block = _decodeBlock(entry);
          if (block != null) blocks.add(block);
        }
      }
    }
    return Message(role: role, content: blocks);
  }

  ContentBlock? _decodeBlock(Map<String, Object?> json) {
    switch (json['type']) {
      case 'text':
        return TextBlock(json['text'] as String? ?? '');
      case 'tool_use':
        final input = json['input'];
        return ToolUseBlock(
          id: json['id'] as String? ?? '',
          name: json['name'] as String? ?? '',
          input: input is Map<String, Object?>
              ? Map<String, Object?>.from(input)
              : const {},
        );
      default:
        // Thinking blocks and unknown variants are ignored by the harness
        // for now — Phase 1 doesn't surface them.
        return null;
    }
  }

  AnthropicApiException _errorFromResponse(http.Response response) {
    String message = response.body;
    String? errorType;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, Object?>) {
        final error = decoded['error'];
        if (error is Map<String, Object?>) {
          errorType = error['type'] as String?;
          message = (error['message'] as String?) ?? message;
        }
      }
    } catch (_) {
      // Body wasn't JSON — keep the raw body as the message.
    }
    return AnthropicApiException(
      statusCode: response.statusCode,
      message: message,
      errorType: errorType,
    );
  }
}

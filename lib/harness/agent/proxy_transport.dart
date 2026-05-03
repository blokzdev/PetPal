import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'anthropic_client.dart';
import 'llm_stream_event.dart';
import 'llm_transport.dart';
import 'messages.dart';

/// Phase 7 Group A.3 — funded-path transport.
///
/// POSTs to PetPal's Supabase Edge Function
/// (`<supabaseUrl>/functions/v1/llm-proxy`) instead of Anthropic
/// directly. The Edge Function (DECISIONS row 82, see
/// `supabase/functions/llm-proxy/index.ts`) handles auth, rate-limit
/// floor, atomic counter increment, and forwards to Anthropic with
/// PetPal's master key — preserving `cache_control` blocks
/// byte-for-byte (CLAUDE.md §6 prompt-cache lock).
///
/// Authentication shape (DECISIONS rows 70 + 82):
///   - Signed-in users supply a Supabase JWT via [userJwt].
///   - Anonymous (signed-out free) users supply a UUID v4 via
///     [deviceToken]. The Edge Function rejects both-null with 401.
///
/// Quota gating happens server-side; this transport surfaces it as
/// an [AnthropicApiException] with `statusCode: 402` for monthly cap
/// exceeded, `429` for rate-limited, `403` for banned. The Flutter
/// quota gate (Group D.1) catches these and surfaces the paywall
/// per VOICE.md §6 example 14.
///
/// Body shape is identical to [AnthropicClient]'s — same JSON
/// envelope, same `cache_control` blocks. The proxy is a passthrough.
/// Encoding helpers are duplicated here from [AnthropicClient] for
/// A.3.1 (kept self-contained); A.3.2's rename commit may DRY them
/// into a shared protocol module.
class ProxyTransport extends LlmTransport {
  ProxyTransport({
    required String supabaseUrl,
    required String supabaseAnonKey,
    String? userJwt,
    String? deviceToken,
    this.model = 'claude-sonnet-4-6',
    this.maxTokens = 4096,
    http.Client? httpClient,
  })  : _supabaseUrl = supabaseUrl,
        _supabaseAnonKey = supabaseAnonKey,
        _userJwt = userJwt,
        _deviceToken = deviceToken,
        _http = httpClient ?? http.Client() {
    if (userJwt == null && deviceToken == null) {
      throw ArgumentError(
        'ProxyTransport requires either userJwt (signed-in) or '
        'deviceToken (anonymous). The Edge Function rejects '
        'both-null with 401.',
      );
    }
  }

  static const _apiVersion = '2023-06-01';

  final String _supabaseUrl;
  final String _supabaseAnonKey;
  final String? _userJwt;
  final String? _deviceToken;
  final http.Client _http;
  final String model;
  final int maxTokens;

  AnthropicUsage? _lastUsage;
  AnthropicUsage? get lastUsage => _lastUsage;

  Uri get _endpoint => Uri.parse('$_supabaseUrl/functions/v1/llm-proxy');

  Map<String, String> _headers({bool streaming = false}) {
    final jwt = _userJwt;
    final token = _deviceToken;
    return <String, String>{
      'Content-Type': 'application/json',
      'apikey': _supabaseAnonKey,
      // ignore: use_null_aware_elements
      if (jwt != null) 'Authorization': 'Bearer $jwt',
      // ignore: use_null_aware_elements
      if (token != null) 'x-petpal-device-token': token,
      'anthropic-version': _apiVersion,
      if (streaming) 'accept': 'text/event-stream',
    };
  }

  @override
  Future<Message> turn({
    required String systemPrompt,
    required List<Message> history,
    List<ToolDefinition> tools = const [],
  }) async {
    final body = _buildBody(
      systemPrompt: systemPrompt,
      history: history,
      tools: tools,
      streaming: false,
    );

    final response = await _http.post(
      _endpoint,
      headers: _headers(),
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw _errorFromBody(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body) as Map<String, Object?>;
    final usage = decoded['usage'];
    if (usage is Map<String, Object?>) {
      _lastUsage = AnthropicUsage.fromJson(usage);
    }
    return _decodeMessage(decoded);
  }

  @override
  Stream<LlmStreamEvent> streamTurn({
    required String systemPrompt,
    required List<Message> history,
    List<ToolDefinition> tools = const [],
  }) async* {
    final body = _buildBody(
      systemPrompt: systemPrompt,
      history: history,
      tools: tools,
      streaming: true,
    );

    final request = http.Request('POST', _endpoint)
      ..headers.addAll(_headers(streaming: true))
      ..body = jsonEncode(body);

    final streamed = await _http.send(request);
    if (streamed.statusCode != 200) {
      final errBody = await streamed.stream.bytesToString();
      throw _errorFromBody(streamed.statusCode, errBody);
    }

    String? lastStopReason;
    int? lastOutputTokens;

    await for (final raw in streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!raw.startsWith('data:')) continue;
      final payload = raw.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;

      final Map<String, Object?> evt;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map<String, Object?>) continue;
        evt = decoded;
      } catch (_) {
        continue;
      }

      switch (evt['type']) {
        case 'message_start':
          final msg = evt['message'];
          if (msg is Map<String, Object?>) {
            final usage = msg['usage'];
            if (usage is Map<String, Object?>) {
              _lastUsage = AnthropicUsage.fromJson(usage);
            }
          }
          yield const StreamMessageStart();

        case 'content_block_start':
          final index = (evt['index'] as num?)?.toInt() ?? 0;
          final block = evt['content_block'];
          if (block is Map<String, Object?> && block['type'] == 'tool_use') {
            yield StreamToolUseStart(
              index: index,
              id: block['id'] as String? ?? '',
              name: block['name'] as String? ?? '',
            );
          }

        case 'content_block_delta':
          final index = (evt['index'] as num?)?.toInt() ?? 0;
          final delta = evt['delta'];
          if (delta is Map<String, Object?>) {
            switch (delta['type']) {
              case 'text_delta':
                final text = delta['text'];
                if (text is String && text.isNotEmpty) {
                  yield StreamTextDelta(text);
                }
              case 'input_json_delta':
                final partial = delta['partial_json'];
                if (partial is String) {
                  yield StreamToolUseInputDelta(
                    index: index,
                    partialJson: partial,
                  );
                }
            }
          }

        case 'content_block_stop':
          final index = (evt['index'] as num?)?.toInt() ?? 0;
          yield StreamContentBlockStop(index: index);

        case 'message_delta':
          final delta = evt['delta'];
          if (delta is Map<String, Object?>) {
            final reason = delta['stop_reason'];
            if (reason is String) lastStopReason = reason;
          }
          final usage = evt['usage'];
          if (usage is Map<String, Object?>) {
            final out = usage['output_tokens'];
            if (out is num) lastOutputTokens = out.toInt();
          }

        case 'message_stop':
          yield StreamMessageStop(
            stopReason: lastStopReason,
            outputTokens: lastOutputTokens,
          );

        case 'error':
          final err = evt['error'];
          if (err is Map<String, Object?>) {
            throw AnthropicApiException(
              statusCode: 200,
              message: (err['message'] as String?) ?? 'stream error',
              errorType: err['type'] as String?,
            );
          }
      }
    }
  }

  void close() => _http.close();

  // ─── shared body / encoding / decoding ────────────────────────────

  Map<String, Object?> _buildBody({
    required String systemPrompt,
    required List<Message> history,
    required List<ToolDefinition> tools,
    required bool streaming,
  }) =>
      <String, Object?>{
        'model': model,
        'max_tokens': maxTokens,
        if (streaming) 'stream': true,
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

  Map<String, Object?> _encodeMessage(Message m) => {
        'role': m.role,
        'content': [for (final block in m.content) _encodeBlock(block)],
      };

  Map<String, Object?> _encodeBlock(ContentBlock block) {
    switch (block) {
      case TextBlock(:final text):
        return {'type': 'text', 'text': text};
      case ImageBlock(
          :final bytes,
          :final mediaType,
          :final cacheControl,
        ):
        return {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': mediaType,
            'data': base64Encode(bytes),
          },
          if (cacheControl) 'cache_control': {'type': 'ephemeral'},
        };
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
        return null;
    }
  }

  AnthropicApiException _errorFromBody(int statusCode, String rawBody) {
    String message = rawBody;
    String? errorType;
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, Object?>) {
        // Edge Function error shape: {"error": {"code": "...", "detail": "..."}}.
        // Map to AnthropicApiException so callers handle it uniformly.
        final error = decoded['error'];
        if (error is Map<String, Object?>) {
          errorType = error['type'] as String? ?? error['code'] as String?;
          message =
              (error['message'] as String?) ?? (error['detail'] as String?) ?? message;
        }
      }
    } catch (_) {
      // Body wasn't JSON — keep raw as message.
    }
    return AnthropicApiException(
      statusCode: statusCode,
      message: message,
      errorType: errorType,
    );
  }
}

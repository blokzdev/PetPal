import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/chat/chat_error.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/app/entitlement/quota_exception.dart';
import 'package:petpal/harness/agent/direct_transport.dart';

void main() {
  test('401 maps to auth, 429 maps to rate limit, 5xx maps to server',
      () {
    expect(
      categorizeChatError(
        AnthropicApiException(
          statusCode: 401,
          message: 'invalid x-api-key',
          errorType: 'authentication_error',
        ),
      ).category,
      ChatErrorCategory.auth,
    );
    expect(
      categorizeChatError(
        AnthropicApiException(
          statusCode: 429,
          message: 'too many requests',
          errorType: 'rate_limit_error',
        ),
      ).category,
      ChatErrorCategory.rateLimit,
    );
    expect(
      categorizeChatError(
        AnthropicApiException(statusCode: 503, message: 'service_unavailable'),
      ).category,
      ChatErrorCategory.server,
    );
  });

  test('SocketException maps to offline', () {
    expect(
      categorizeChatError(
        const SocketException('No route to host'),
      ).category,
      ChatErrorCategory.offline,
    );
  });

  test('unknown errors fall through to generic with the toString', () {
    final err = categorizeChatError(StateError('something exploded'));
    expect(err.category, ChatErrorCategory.generic);
    expect(err.message, contains('something exploded'));
  });

  group('Phase 7 task D.1 — quota error mapping', () {
    test('client-side TextQuotaExceeded → ChatErrorCategory.quotaExceeded',
        () {
      final err = categorizeChatError(
        TextQuotaExceeded(Entitlement.freeAnonymous()),
      );
      expect(err.category, ChatErrorCategory.quotaExceeded);
      expect(err.message, contains("That's 200 messages this month"));
    });

    test('server-side 402 monthly_cap_exceeded → '
        'ChatErrorCategory.quotaExceeded (same UI category as the '
        'client-side gate)', () {
      final err = categorizeChatError(
        AnthropicApiException(
          statusCode: 402,
          message: 'monthly_cap_exceeded',
          errorType: 'monthly_cap_exceeded',
        ),
      );
      expect(err.category, ChatErrorCategory.quotaExceeded);
      expect(err.message, contains("That's 200 messages this month"));
    });
  });
}

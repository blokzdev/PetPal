import 'dart:io';

import '../../harness/agent/direct_transport.dart';
import '../entitlement/quota_exception.dart';

/// Coarse categorisation of failures the chat surface needs to render
/// differently. Each maps to a one-liner of copy + the same retry
/// affordance, so the UI doesn't have to know about specific exception
/// types.
enum ChatErrorCategory {
  /// API rejected the call as unauthenticated (401, 403). The fix is to
  /// re-enter the API key in onboarding / settings, not to retry.
  auth,

  /// API said too many requests (429). Retry works after a brief wait.
  rateLimit,

  /// No network — SocketException, ClientException with no response.
  /// Retry once connectivity is back.
  offline,

  /// API returned 5xx. Retry usually fixes it.
  server,

  /// Phase 7 task D.1 — free-tier 200 msg/mo cap met. Either the
  /// client-side pre-call gate fired or the proxy returned 402.
  /// UI dispatches the paywall prompt per VOICE.md §6 example 14.
  quotaExceeded,

  /// Anything else — show the message and offer retry.
  generic,
}

class ChatError {
  const ChatError({required this.category, required this.message});

  final ChatErrorCategory category;
  final String message;
}

/// Map a thrown error to the [ChatError] the UI should display. Anything
/// unrecognised falls through to [ChatErrorCategory.generic] with the
/// raw `toString()`.
ChatError categorizeChatError(Object e) {
  // Phase 7 task D.1 — client-side pre-call gate fires before the
  // round-trip when the cached entitlement says the user is over
  // their cap. Per VOICE.md §6 example 14 the upgrade ladder
  // surfaces in the paywall, not in this message — keep the copy
  // brief.
  if (e is TextQuotaExceeded) {
    return const ChatError(
      category: ChatErrorCategory.quotaExceeded,
      message: "That's 200 messages this month.",
    );
  }
  if (e is AnthropicApiException) {
    switch (e.statusCode) {
      case 401:
      case 403:
        return const ChatError(
          category: ChatErrorCategory.auth,
          message:
              'Your Anthropic API key was rejected. Update it in Settings.',
        );
      // Phase 7 task D.1 — server-side text cap exhausted. The
      // proxy returns 402 monthly_cap_exceeded after the atomic
      // counter increment fails. Same UI category as the client
      // pre-call gate above.
      case 402:
        return const ChatError(
          category: ChatErrorCategory.quotaExceeded,
          message: "That's 200 messages this month.",
        );
      case 429:
        return const ChatError(
          category: ChatErrorCategory.rateLimit,
          message:
              'Anthropic is rate-limiting your account. Wait a moment and '
              'try again.',
        );
      default:
        if (e.statusCode >= 500) {
          return ChatError(
            category: ChatErrorCategory.server,
            message:
                'Anthropic returned a ${e.statusCode}. The service is '
                'having issues — try again in a minute.',
          );
        }
        return ChatError(
          category: ChatErrorCategory.generic,
          message: e.message,
        );
    }
  }
  if (e is SocketException || e is HttpException) {
    return const ChatError(
      category: ChatErrorCategory.offline,
      message: 'No internet connection. Reconnect and try again.',
    );
  }
  final s = e.toString();
  return ChatError(
    category: ChatErrorCategory.generic,
    message: s.length > 200 ? '${s.substring(0, 200)}…' : s,
  );
}

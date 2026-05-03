import 'llm_client.dart';

/// Phase 7 Group A.3 — transport abstraction for the agent loop.
///
/// Two concrete transports, picked at construction time based on the
/// active entitlement state (per DECISIONS row 75 hybrid quota model
/// + row 76 proxy build-now decision):
///
///   - [DirectTransport] (BYOK path) — sends requests directly to
///     `api.anthropic.com` with the user's own `sk-ant-…` key. Used
///     when the user has flipped the "Bring your own Anthropic key"
///     toggle in Settings (VOICE.md §6 example 12). Quotas don't
///     apply; calls are between user + Anthropic.
///
///   - [ProxyTransport] (funded path) — sends requests to PetPal's
///     Supabase Edge Function (`/functions/v1/llm-proxy`), which
///     forwards to Anthropic with PetPal's master key after
///     incrementing the per-user counter. Used for free-tier funded
///     allowance (200 msg/mo) and for Pro subscribers (unmetered).
///     The proxy preserves Anthropic's `cache_control` blocks
///     verbatim (DECISIONS row 82 lock).
///
/// Agent loop ([AgentLoop]) consumes [LlmClient] — neither concrete
/// transport leaks beyond construction time. Switching transports is
/// a provider-level concern (Riverpod `llmClientProvider` resolves
/// the right one from `entitlementProvider`).
abstract class LlmTransport implements LlmClient {
  const LlmTransport();
}

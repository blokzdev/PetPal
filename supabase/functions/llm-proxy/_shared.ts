// Shared helpers for Edge Functions. Keep this thin.

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-petpal-device-token',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export function jsonError(status: number, code: string, detail?: string): Response {
  return new Response(
    JSON.stringify({ error: { code, ...(detail ? { detail } : {}) } }),
    {
      status,
      headers: { ...corsHeaders, 'content-type': 'application/json' },
    },
  );
}

export function jsonOk(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}

/**
 * Detect cache_control blocks in an Anthropic /v1/messages request body.
 * Used by the proxy to set the `inbound_had_cache_control` audit column —
 * if this metric drops to zero in prod for cached system-prompt traffic,
 * the proxy lost cache_control passthrough (catastrophic cost regression
 * per CLAUDE.md §6 + DECISIONS row 82).
 *
 * Match recursively against the known schema: messages[].content[].cache_control,
 * system[].cache_control, tools[].cache_control. Returns true if any match.
 */
export function detectCacheControl(body: unknown): boolean {
  if (body === null || typeof body !== 'object') return false;
  if (Array.isArray(body)) return body.some(detectCacheControl);
  const obj = body as Record<string, unknown>;
  if ('cache_control' in obj && obj.cache_control !== undefined) return true;
  for (const v of Object.values(obj)) {
    if (typeof v === 'object' && v !== null && detectCacheControl(v)) return true;
  }
  return false;
}

/**
 * Extract token usage from an Anthropic streaming response's accumulated
 * SSE payload. Anthropic emits `message_delta` events with `usage` fields
 * during streaming and a terminal `message_stop` event. We sum them.
 *
 * Returns null on parse failure (the request still succeeds; we just
 * don't log token counts for that row).
 */
export interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheCreationTokens: number;
}

export function extractTokenUsageFromSSE(sseText: string): TokenUsage | null {
  let inputTokens = 0;
  let outputTokens = 0;
  let cacheReadTokens = 0;
  let cacheCreationTokens = 0;
  let saw = false;

  for (const line of sseText.split('\n')) {
    if (!line.startsWith('data: ')) continue;
    const data = line.slice(6).trim();
    if (data === '' || data === '[DONE]') continue;
    try {
      const parsed = JSON.parse(data);
      const usage = parsed?.message?.usage ?? parsed?.usage;
      if (usage && typeof usage === 'object') {
        saw = true;
        if (typeof usage.input_tokens === 'number') {
          inputTokens = Math.max(inputTokens, usage.input_tokens);
        }
        if (typeof usage.output_tokens === 'number') {
          outputTokens = Math.max(outputTokens, usage.output_tokens);
        }
        if (typeof usage.cache_read_input_tokens === 'number') {
          cacheReadTokens = Math.max(cacheReadTokens, usage.cache_read_input_tokens);
        }
        if (typeof usage.cache_creation_input_tokens === 'number') {
          cacheCreationTokens = Math.max(
            cacheCreationTokens,
            usage.cache_creation_input_tokens,
          );
        }
      }
    } catch {
      // Skip malformed SSE rows; we tolerate partial parse failure.
    }
  }
  return saw
    ? { inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens }
    : null;
}

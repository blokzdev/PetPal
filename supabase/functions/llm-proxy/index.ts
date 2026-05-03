// llm-proxy — Phase 7 Group A.2 backend Edge Function.
//
// Forwards Anthropic /v1/messages requests with PetPal's master API
// key, atomically increments the per-user message counter, and
// returns the streaming response back to the client. NEVER stores
// chat content; logs only token counts + metadata.
//
// Identity model (DECISIONS row 70 + 82):
//   - Signed-in users: Authorization: Bearer <Supabase JWT>
//   - Anonymous free users: x-petpal-device-token: <UUID v4>
//
// Quota model (DECISIONS row 75 — hybrid client+server, this is the
// canonical server side):
//   - Anonymous: 200 msg/mo cap (FREE_MONTHLY_TEXT_CAP)
//   - Free signed-in: 200 msg/mo cap (entitlement state='free')
//   - Pro signed-in: unmetered (entitlement state='pro_*'); cap=null
//   - BYOK: never reaches this proxy by definition; client routes
//     through DirectTransport straight to api.anthropic.com.
//
// Rate-limit floor (DECISIONS row 82): 100 msg/hour per actor,
// enforced by check_rate_limit() Postgres function.
//
// Cache_control passthrough (CLAUDE.md §6 lock + DECISIONS row 82):
// the request body is forwarded raw to Anthropic. We never deserialize
// + re-serialize, so cache_control blocks survive intact. The audit
// column proxy_request_log.inbound_had_cache_control catches
// regressions if the body shape ever changes.

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import {
  corsHeaders,
  jsonError,
  detectCacheControl,
  extractTokenUsageFromSSE,
} from './_shared.ts';

export const ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages';
export const FREE_MONTHLY_TEXT_CAP = 200;

interface ResolvedActor {
  type: 'user' | 'anonymous';
  id: string;
  cap: number | null;
}

export interface HandlerDeps {
  supabase: SupabaseClient;
  anthropicFetch: typeof fetch;
  anthropicKey: string;
  /** Optional waitUntil override for tests; defaults to fire-and-forget. */
  waitUntil?: (p: Promise<unknown>) => void;
}

export async function handleProxyRequest(
  req: Request,
  deps: HandlerDeps,
): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonError(405, 'method_not_allowed');
  }

  let actor: ResolvedActor;
  try {
    actor = await resolveActor(req, deps.supabase);
  } catch (e) {
    return jsonError(401, 'unauthorized', (e as Error).message);
  }

  const { data: rateLimit, error: rateErr } = await deps.supabase.rpc(
    'check_rate_limit',
    { p_actor_id: actor.id, p_actor_type: actor.type },
  );
  if (rateErr) {
    return jsonError(500, 'rate_limit_check_failed', rateErr.message);
  }
  if (!rateLimit?.allowed) {
    const reason = rateLimit?.reason ?? 'rate_limited';
    const status = reason === 'banned' ? 403 : 429;
    return jsonError(status, reason);
  }

  const { data: increment, error: incErr } = await deps.supabase.rpc(
    'increment_text_counter',
    {
      p_actor_id: actor.id,
      p_actor_type: actor.type,
      p_free_cap: actor.cap,
    },
  );
  if (incErr) {
    return jsonError(500, 'counter_failed', incErr.message);
  }
  if (!increment?.allowed) {
    return jsonError(402, 'monthly_cap_exceeded', JSON.stringify(increment));
  }

  const bodyText = await req.text();
  let bodyParsed: unknown;
  try {
    bodyParsed = JSON.parse(bodyText);
  } catch {
    return jsonError(400, 'invalid_json');
  }
  const inboundHadCacheControl = detectCacheControl(bodyParsed);
  const requestModel =
    typeof (bodyParsed as Record<string, unknown>)?.model === 'string'
      ? ((bodyParsed as Record<string, unknown>).model as string)
      : null;

  const startedAt = Date.now();
  let upstream: Response;
  try {
    upstream = await deps.anthropicFetch(ANTHROPIC_API_URL, {
      method: 'POST',
      headers: {
        'x-api-key': deps.anthropicKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: bodyText,
    });
  } catch (e) {
    return jsonError(502, 'upstream_unreachable', (e as Error).message);
  }

  if (!upstream.body) {
    return jsonError(502, 'upstream_no_body');
  }
  const [forClient, forLog] = upstream.body.tee();

  const responseHeaders = new Headers(upstream.headers);
  for (const [k, v] of Object.entries(corsHeaders)) {
    responseHeaders.set(k, v);
  }

  const logTask = (async () => {
    const reader = forLog.getReader();
    const decoder = new TextDecoder();
    let acc = '';
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        acc += decoder.decode(value, { stream: true });
      }
    } catch {
      // Stream errors don't fail the response; log without token counts.
    }
    const usage = extractTokenUsageFromSSE(acc);
    await deps.supabase.from('proxy_request_log').insert({
      user_id: actor.type === 'user' ? actor.id : null,
      device_token: actor.type === 'anonymous' ? actor.id : null,
      model: requestModel,
      input_tokens: usage?.inputTokens ?? null,
      output_tokens: usage?.outputTokens ?? null,
      cache_read_tokens: usage?.cacheReadTokens ?? null,
      cache_creation_tokens: usage?.cacheCreationTokens ?? null,
      status_code: upstream.status,
      latency_ms: Date.now() - startedAt,
      inbound_had_cache_control: inboundHadCacheControl,
    });
  })();

  if (deps.waitUntil) {
    deps.waitUntil(logTask);
  } else {
    logTask.catch(() => {});
  }

  return new Response(forClient, {
    status: upstream.status,
    headers: responseHeaders,
  });
}

async function resolveActor(
  req: Request,
  supabase: SupabaseClient,
): Promise<ResolvedActor> {
  const authHeader = req.headers.get('authorization');
  const deviceToken = req.headers.get('x-petpal-device-token');

  if (authHeader?.startsWith('Bearer ')) {
    const jwt = authHeader.slice(7);
    const { data, error } = await supabase.auth.getUser(jwt);
    if (error || !data?.user) {
      throw new Error('invalid_jwt');
    }
    const userId = data.user.id;

    const { data: ent } = await supabase
      .from('entitlements')
      .select('state')
      .eq('user_id', userId)
      .maybeSingle();
    const state = ent?.state ?? 'free';
    const cap = state === 'free' ? FREE_MONTHLY_TEXT_CAP : null;

    return { type: 'user', id: userId, cap };
  }

  if (deviceToken && /^[0-9a-f-]{36}$/i.test(deviceToken)) {
    return { type: 'anonymous', id: deviceToken, cap: FREE_MONTHLY_TEXT_CAP };
  }

  throw new Error('no_credentials');
}

// Bootstrap when running as a deployed Edge Function.
if (import.meta.main) {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { persistSession: false } },
  );
  const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY') ?? '';

  Deno.serve((req) =>
    handleProxyRequest(req, {
      supabase,
      anthropicFetch: fetch,
      anthropicKey,
      // @ts-ignore — EdgeRuntime exists in Supabase Edge Runtime.
      waitUntil: typeof EdgeRuntime !== 'undefined'
        // @ts-ignore
        ? EdgeRuntime.waitUntil.bind(EdgeRuntime)
        : undefined,
    }),
  );
}

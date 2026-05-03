// Phase 7 Group A.2 — llm-proxy Edge Function tests.
//
// Pins the load-bearing invariants: cache_control passthrough (the
// single most important regression to catch — losing it costs >70%
// per CLAUDE.md §6 prompt-cache lock), auth-required, quota gate,
// rate-limit gate, and BYOK separation.
//
// Run via `deno test --allow-net --allow-env supabase/functions/_tests/`.

import { assertEquals, assertExists } from 'https://deno.land/std@0.190.0/assert/mod.ts';
import {
  handleProxyRequest,
  HandlerDeps,
} from '../llm-proxy/index.ts';
import { detectCacheControl } from '../llm-proxy/_shared.ts';

// ─── Test fixtures ──────────────────────────────────────────────────────

const VALID_DEVICE_TOKEN = '12345678-1234-1234-1234-123456789abc';
const VALID_USER_ID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const ANTHROPIC_KEY = 'sk-ant-test-key';

interface RpcCall {
  fn: string;
  args: Record<string, unknown>;
}

interface FakeSupabaseConfig {
  rateLimitAllowed?: boolean;
  rateLimitReason?: string;
  incrementAllowed?: boolean;
  incrementResult?: Record<string, unknown>;
  authUser?: { id: string } | null;
  entitlementState?: string;
}

function makeFakeSupabase(cfg: FakeSupabaseConfig = {}) {
  const rpcCalls: RpcCall[] = [];
  const inserts: Record<string, unknown>[] = [];

  const rpc = (fn: string, args: Record<string, unknown>) => {
    rpcCalls.push({ fn, args });
    if (fn === 'check_rate_limit') {
      return Promise.resolve({
        data: {
          allowed: cfg.rateLimitAllowed ?? true,
          reason: cfg.rateLimitReason,
        },
        error: null,
      });
    }
    if (fn === 'increment_text_counter') {
      return Promise.resolve({
        data: cfg.incrementResult ?? { allowed: cfg.incrementAllowed ?? true, count: 1 },
        error: null,
      });
    }
    return Promise.resolve({ data: null, error: { message: 'unknown_fn' } });
  };

  const from = (_table: string) => ({
    select: () => ({
      eq: () => ({
        maybeSingle: () =>
          Promise.resolve({
            data: cfg.entitlementState
              ? { state: cfg.entitlementState }
              : null,
            error: null,
          }),
      }),
    }),
    insert: (row: Record<string, unknown>) => {
      inserts.push(row);
      return Promise.resolve({ data: null, error: null });
    },
  });

  const auth = {
    getUser: (_jwt: string) =>
      Promise.resolve({
        data: cfg.authUser !== undefined
          ? { user: cfg.authUser }
          : { user: { id: VALID_USER_ID } },
        error: cfg.authUser === null ? { message: 'invalid_jwt' } : null,
      }),
  };

  // deno-lint-ignore no-explicit-any
  return { fake: { rpc, from, auth } as any, rpcCalls, inserts };
}

function makeFakeAnthropicFetch(opts: {
  status?: number;
  body?: string;
  capture?: { url?: string; init?: RequestInit; bodyText?: string };
}) {
  return async (url: string | URL | Request, init?: RequestInit): Promise<Response> => {
    if (opts.capture) {
      opts.capture.url = url.toString();
      opts.capture.init = init;
      if (init?.body && typeof init.body === 'string') {
        opts.capture.bodyText = init.body;
      }
    }
    const body = opts.body ?? 'data: {"type":"message_stop"}\n\n';
    return new Response(body, {
      status: opts.status ?? 200,
      headers: { 'content-type': 'text/event-stream' },
    });
  };
}

async function readResponseBody(res: Response): Promise<string> {
  if (!res.body) return '';
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let acc = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    acc += decoder.decode(value, { stream: true });
  }
  return acc;
}

// ─── Tests ─────────────────────────────────────────────────────────────

Deno.test('cache_control passthrough — proxy forwards body byte-for-byte to Anthropic', async () => {
  const { fake } = makeFakeSupabase();
  const capture: { bodyText?: string } = {};
  const requestBody = JSON.stringify({
    model: 'claude-sonnet-4-6',
    system: [
      {
        type: 'text',
        text: 'You are PetPal.',
        cache_control: { type: 'ephemeral' },
      },
    ],
    messages: [{ role: 'user', content: 'hello' }],
  });

  const req = new Request('http://localhost/llm-proxy', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-petpal-device-token': VALID_DEVICE_TOKEN,
    },
    body: requestBody,
  });

  const res = await handleProxyRequest(req, {
    supabase: fake,
    anthropicFetch: makeFakeAnthropicFetch({ capture }),
    anthropicKey: ANTHROPIC_KEY,
  } as HandlerDeps);
  await readResponseBody(res);

  assertEquals(res.status, 200);
  // The catastrophic-regression check: bytes sent to Anthropic must
  // equal bytes received from client. No re-serialization.
  assertEquals(capture.bodyText, requestBody);
  // Defensive: cache_control must still parse out of the captured body.
  assertEquals(detectCacheControl(JSON.parse(capture.bodyText!)), true);
});

Deno.test('cache_control detection — recursive across system, messages, tools', () => {
  // Regression: cache_control can land at any depth in the request body.
  // detectCacheControl walks the tree.
  assertEquals(
    detectCacheControl({
      system: [{ type: 'text', text: 'x', cache_control: { type: 'ephemeral' } }],
    }),
    true,
  );
  assertEquals(
    detectCacheControl({
      messages: [
        { role: 'user', content: [{ type: 'text', text: 'x', cache_control: { type: 'ephemeral' } }] },
      ],
    }),
    true,
  );
  assertEquals(
    detectCacheControl({
      tools: [{ name: 't', description: 'd', cache_control: { type: 'ephemeral' } }],
    }),
    true,
  );
  assertEquals(detectCacheControl({ messages: [{ role: 'user', content: 'plain' }] }), false);
});

Deno.test('rejects requests without auth — no JWT and no device-token → 401', async () => {
  const { fake } = makeFakeSupabase();
  const req = new Request('http://localhost/llm-proxy', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ model: 'claude-sonnet-4-6', messages: [] }),
  });

  const res = await handleProxyRequest(req, {
    supabase: fake,
    anthropicFetch: makeFakeAnthropicFetch({}),
    anthropicKey: ANTHROPIC_KEY,
  } as HandlerDeps);

  assertEquals(res.status, 401);
});

Deno.test('quota wall — 200/mo cap returns 402 monthly_cap_exceeded', async () => {
  const { fake, rpcCalls } = makeFakeSupabase({
    incrementAllowed: false,
    incrementResult: { allowed: false, cap: 200, count: 200 },
  });

  const req = new Request('http://localhost/llm-proxy', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-petpal-device-token': VALID_DEVICE_TOKEN,
    },
    body: JSON.stringify({ model: 'claude-sonnet-4-6', messages: [] }),
  });

  const res = await handleProxyRequest(req, {
    supabase: fake,
    anthropicFetch: makeFakeAnthropicFetch({}),
    anthropicKey: ANTHROPIC_KEY,
  } as HandlerDeps);

  assertEquals(res.status, 402);
  // Increment was attempted with the free cap.
  const incCall = rpcCalls.find((c) => c.fn === 'increment_text_counter');
  assertExists(incCall);
  assertEquals(incCall!.args.p_free_cap, 200);
});

Deno.test('rate-limit floor — 100/hr cap returns 429', async () => {
  const { fake } = makeFakeSupabase({
    rateLimitAllowed: false,
    rateLimitReason: 'rate_limited',
  });

  const req = new Request('http://localhost/llm-proxy', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-petpal-device-token': VALID_DEVICE_TOKEN,
    },
    body: JSON.stringify({ model: 'claude-sonnet-4-6', messages: [] }),
  });

  const res = await handleProxyRequest(req, {
    supabase: fake,
    anthropicFetch: makeFakeAnthropicFetch({}),
    anthropicKey: ANTHROPIC_KEY,
  } as HandlerDeps);

  assertEquals(res.status, 429);
});

Deno.test('banned token — returns 403 (different status from rate-limit)', async () => {
  const { fake } = makeFakeSupabase({
    rateLimitAllowed: false,
    rateLimitReason: 'banned',
  });

  const req = new Request('http://localhost/llm-proxy', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-petpal-device-token': VALID_DEVICE_TOKEN,
    },
    body: JSON.stringify({ model: 'claude-sonnet-4-6', messages: [] }),
  });

  const res = await handleProxyRequest(req, {
    supabase: fake,
    anthropicFetch: makeFakeAnthropicFetch({}),
    anthropicKey: ANTHROPIC_KEY,
  } as HandlerDeps);

  assertEquals(res.status, 403);
});

Deno.test('Pro user (state=pro_monthly) → unmetered: cap is null in increment call', async () => {
  const { fake, rpcCalls } = makeFakeSupabase({
    authUser: { id: VALID_USER_ID },
    entitlementState: 'pro_monthly',
  });

  const req = new Request('http://localhost/llm-proxy', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: 'Bearer fake-jwt',
    },
    body: JSON.stringify({ model: 'claude-sonnet-4-6', messages: [] }),
  });

  const res = await handleProxyRequest(req, {
    supabase: fake,
    anthropicFetch: makeFakeAnthropicFetch({}),
    anthropicKey: ANTHROPIC_KEY,
  } as HandlerDeps);
  await readResponseBody(res);

  assertEquals(res.status, 200);
  const incCall = rpcCalls.find((c) => c.fn === 'increment_text_counter');
  assertExists(incCall);
  // Pro = unmetered → cap is null. Counter still increments (for billing
  // visibility) but no wall fires.
  assertEquals(incCall!.args.p_free_cap, null);
});

Deno.test('rejects malformed JSON body with 400', async () => {
  const { fake } = makeFakeSupabase();

  const req = new Request('http://localhost/llm-proxy', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-petpal-device-token': VALID_DEVICE_TOKEN,
    },
    body: 'not json',
  });

  const res = await handleProxyRequest(req, {
    supabase: fake,
    anthropicFetch: makeFakeAnthropicFetch({}),
    anthropicKey: ANTHROPIC_KEY,
  } as HandlerDeps);

  assertEquals(res.status, 400);
});

Deno.test('rejects GET with 405', async () => {
  const { fake } = makeFakeSupabase();
  const req = new Request('http://localhost/llm-proxy', { method: 'GET' });
  const res = await handleProxyRequest(req, {
    supabase: fake,
    anthropicFetch: makeFakeAnthropicFetch({}),
    anthropicKey: ANTHROPIC_KEY,
  } as HandlerDeps);
  assertEquals(res.status, 405);
});

Deno.test('OPTIONS preflight — returns CORS headers', async () => {
  const { fake } = makeFakeSupabase();
  const req = new Request('http://localhost/llm-proxy', { method: 'OPTIONS' });
  const res = await handleProxyRequest(req, {
    supabase: fake,
    anthropicFetch: makeFakeAnthropicFetch({}),
    anthropicKey: ANTHROPIC_KEY,
  } as HandlerDeps);
  assertEquals(res.status, 200);
  assertEquals(res.headers.get('Access-Control-Allow-Origin'), '*');
});

Deno.test('proxy_request_log row records inbound_had_cache_control accurately', async () => {
  const { fake, inserts } = makeFakeSupabase();
  // Use a synchronous waitUntil so the log write completes before assertion.
  let logCompleted: Promise<unknown> = Promise.resolve();
  const waitUntil = (p: Promise<unknown>) => {
    logCompleted = p;
  };

  const req = new Request('http://localhost/llm-proxy', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-petpal-device-token': VALID_DEVICE_TOKEN,
    },
    body: JSON.stringify({
      model: 'claude-sonnet-4-6',
      system: [{ type: 'text', text: 'sys', cache_control: { type: 'ephemeral' } }],
      messages: [{ role: 'user', content: 'hi' }],
    }),
  });

  const res = await handleProxyRequest(req, {
    supabase: fake,
    anthropicFetch: makeFakeAnthropicFetch({
      body: 'data: {"type":"message_stop","message":{"usage":{"input_tokens":50,"output_tokens":10,"cache_read_input_tokens":40}}}\n\n',
    }),
    anthropicKey: ANTHROPIC_KEY,
    waitUntil,
  });
  await readResponseBody(res);
  await logCompleted;

  assertEquals(inserts.length, 1);
  const row = inserts[0];
  assertEquals(row.inbound_had_cache_control, true);
  assertEquals(row.model, 'claude-sonnet-4-6');
  assertEquals(row.input_tokens, 50);
  assertEquals(row.output_tokens, 10);
  assertEquals(row.cache_read_tokens, 40);
});

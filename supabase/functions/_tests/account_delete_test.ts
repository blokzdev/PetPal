// Phase 7 task H.1.d.cron — account-delete Edge Function tests.
//
// Pins the load-bearing invariants: auth gates (401 paths), method
// gate (405 / OPTIONS pass-through), audit-row insert shape (now
// includes `user_id` per migration 0003 — load-bearing for the
// daily-reconciliation cron's undo + hard-purge path), retention
// window math, and admin sign-out call.
//
// Run via `deno test --allow-net --allow-env supabase/functions/_tests/`.

import {
  assert,
  assertEquals,
  assertExists,
} from 'https://deno.land/std@0.190.0/assert/mod.ts';
import {
  handleDeleteRequest,
  HandlerDeps,
} from '../account-delete/index.ts';

// ─── Test fixtures ──────────────────────────────────────────────────────

const VALID_USER_ID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const FROZEN_NOW = new Date('2026-05-03T12:00:00Z');
const EXPECTED_RETENTION_END = new Date('2026-06-02T12:00:00Z');

interface FakeAdminConfig {
  authUser?: { id: string } | null;
  authError?: { message: string } | null;
  insertError?: { message: string } | null;
  /** When set, signOut throws this — verifies we don't crash if the
   *  admin-signOut surface is missing or rejects. */
  signOutThrows?: boolean;
}

function makeFakeAdmin(cfg: FakeAdminConfig = {}) {
  const inserts: Record<string, unknown>[] = [];
  const signOutCalls: string[] = [];

  const auth = {
    getUser: (_jwt: string) =>
      Promise.resolve({
        data: cfg.authUser !== undefined
          ? { user: cfg.authUser }
          : { user: { id: VALID_USER_ID } },
        error: cfg.authError ?? null,
      }),
    admin: {
      signOut: (userId: string) => {
        signOutCalls.push(userId);
        if (cfg.signOutThrows) {
          return Promise.reject(new Error('signOut failed'));
        }
        return Promise.resolve({ error: null });
      },
    },
  };

  const from = (_table: string) => ({
    insert: (row: Record<string, unknown>) => {
      inserts.push(row);
      return Promise.resolve({
        data: null,
        error: cfg.insertError ?? null,
      });
    },
  });

  // deno-lint-ignore no-explicit-any
  return { admin: { auth, from } as any, inserts, signOutCalls };
}

function deps(cfg: FakeAdminConfig = {}): HandlerDeps & {
  inserts: Record<string, unknown>[];
  signOutCalls: string[];
} {
  const fake = makeFakeAdmin(cfg);
  return {
    admin: fake.admin,
    sha256: (s: string) => Promise.resolve(`hash:${s}`),
    now: () => FROZEN_NOW,
    inserts: fake.inserts,
    signOutCalls: fake.signOutCalls,
  };
}

function makeRequest({
  method = 'POST',
  authHeader = `Bearer fake.jwt.token`,
}: {
  method?: string;
  authHeader?: string | null;
} = {}): Request {
  const headers: Record<string, string> = {};
  if (authHeader !== null) headers['Authorization'] = authHeader;
  return new Request('http://test/account-delete', {
    method,
    headers,
  });
}

async function readBody(res: Response): Promise<Record<string, unknown>> {
  const text = await res.text();
  return text ? JSON.parse(text) as Record<string, unknown> : {};
}

// ─── Tests ──────────────────────────────────────────────────────────────

Deno.test('OPTIONS — preflight returns 200 + CORS headers', async () => {
  const d = deps();
  const res = await handleDeleteRequest(
    new Request('http://test/account-delete', { method: 'OPTIONS' }),
    d,
  );
  assertEquals(res.status, 200);
  assertExists(res.headers.get('Access-Control-Allow-Origin'));
  assertEquals(d.inserts.length, 0);
  assertEquals(d.signOutCalls.length, 0);
});

Deno.test('GET — 405 method_not_allowed', async () => {
  const d = deps();
  const res = await handleDeleteRequest(
    makeRequest({ method: 'GET' }),
    d,
  );
  assertEquals(res.status, 405);
  const body = await readBody(res);
  assertEquals(
    (body.error as { code: string }).code,
    'method_not_allowed',
  );
});

Deno.test('POST without Authorization header — 401 unauthorized', async () => {
  const d = deps();
  const res = await handleDeleteRequest(
    makeRequest({ authHeader: null }),
    d,
  );
  assertEquals(res.status, 401);
  const body = await readBody(res);
  assertEquals((body.error as { code: string }).code, 'unauthorized');
});

Deno.test('POST with non-Bearer Authorization — 401 unauthorized', async () => {
  const d = deps();
  const res = await handleDeleteRequest(
    makeRequest({ authHeader: 'Basic dXNlcjpwYXNz' }),
    d,
  );
  assertEquals(res.status, 401);
});

Deno.test('POST with empty Bearer token — 401 unauthorized', async () => {
  const d = deps();
  const res = await handleDeleteRequest(
    makeRequest({ authHeader: 'Bearer ' }),
    d,
  );
  assertEquals(res.status, 401);
});

Deno.test('POST with invalid JWT — 401 invalid_jwt', async () => {
  const d = deps({
    authUser: null,
    authError: { message: 'JWT expired' },
  });
  const res = await handleDeleteRequest(makeRequest(), d);
  assertEquals(res.status, 401);
  const body = await readBody(res);
  assertEquals((body.error as { code: string }).code, 'invalid_jwt');
});

Deno.test('POST happy path — inserts audit row with user_id + hash + timestamps', async () => {
  const d = deps();
  const res = await handleDeleteRequest(makeRequest(), d);

  assertEquals(res.status, 200);
  const body = await readBody(res);
  assertEquals(
    body.retention_window_ends_at,
    EXPECTED_RETENTION_END.toISOString(),
  );

  // Audit row insert — load-bearing invariant per DECISIONS row 90.
  // Both `user_id` (operational, NULLed by cron after purge) and
  // `user_id_hash` (steady-state PII-free trail) must land.
  assertEquals(d.inserts.length, 1);
  const row = d.inserts[0];
  assertEquals(row.user_id, VALID_USER_ID);
  assertEquals(row.user_id_hash, `hash:${VALID_USER_ID}`);
  assertEquals(row.delete_requested_at, FROZEN_NOW.toISOString());
  assertEquals(
    row.retention_window_ends_at,
    EXPECTED_RETENTION_END.toISOString(),
  );
});

Deno.test('POST happy path — fires admin.signOut for the user', async () => {
  const d = deps();
  await handleDeleteRequest(makeRequest(), d);
  assertEquals(d.signOutCalls.length, 1);
  assertEquals(d.signOutCalls[0], VALID_USER_ID);
});

Deno.test('retention window — 30 days exactly from `now`', async () => {
  // Verifies the 30-day-window contract from row 77. If this drifts
  // (e.g. timezone bug, leap-day off-by-one), a regulator-facing
  // promise breaks.
  const d = deps();
  await handleDeleteRequest(makeRequest(), d);
  const row = d.inserts[0];
  const start = new Date(row.delete_requested_at as string);
  const end = new Date(row.retention_window_ends_at as string);
  const diffDays = (end.getTime() - start.getTime()) /
    (24 * 60 * 60 * 1000);
  assertEquals(diffDays, 30);
});

Deno.test('insert error — 500 insert_failed (does NOT sign out)', async () => {
  const d = deps({
    insertError: { message: 'database_unreachable' },
  });
  const res = await handleDeleteRequest(makeRequest(), d);
  assertEquals(res.status, 500);
  const body = await readBody(res);
  assertEquals((body.error as { code: string }).code, 'insert_failed');
  // Do NOT sign out if the audit insert failed — the deletion didn't
  // happen, so the user's session should stay valid for retry.
  assertEquals(d.signOutCalls.length, 0);
});

Deno.test('default sha256 — produces hex output (smoke test)', async () => {
  // Use the real default `defaultSha256Hex` by omitting the override.
  // Verifies the hash is hex-encoded and 64 chars (SHA-256 length).
  const fake = makeFakeAdmin();
  const realDeps: HandlerDeps = {
    admin: fake.admin,
    now: () => FROZEN_NOW,
  };
  const res = await handleDeleteRequest(makeRequest(), realDeps);
  assertEquals(res.status, 200);
  const row = fake.inserts[0];
  const hash = row.user_id_hash as string;
  assertEquals(hash.length, 64);
  assert(/^[0-9a-f]{64}$/.test(hash), `expected 64-char hex, got: ${hash}`);
});

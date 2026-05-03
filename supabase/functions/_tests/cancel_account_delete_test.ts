// Phase 7 task H.1.d.undo — cancel-account-delete Edge Function tests.

import {
  assertEquals,
  assertExists,
} from 'https://deno.land/std@0.190.0/assert/mod.ts';
import {
  HandlerDeps,
  handleCancelRequest,
} from '../cancel-account-delete/index.ts';

const VALID_USER_ID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

interface FakeConfig {
  authUser?: { id: string } | null;
  authError?: { message: string } | null;
  /** Simulated rows returned from the conditional delete .select(). */
  deletedRows?: Array<{ id: number }>;
  deleteError?: string;
}

function makeFakeAdmin(cfg: FakeConfig) {
  // deno-lint-ignore no-explicit-any
  const captured: any = {
    deletes: 0,
    eqUserId: null as string | null,
    isHardPurgedAt: null as null | { col: string; val: null | string },
  };

  const auth = {
    getUser: (_jwt: string) =>
      Promise.resolve({
        data: cfg.authUser !== undefined
          ? { user: cfg.authUser }
          : { user: { id: VALID_USER_ID } },
        error: cfg.authError ?? null,
      }),
  };

  const from = (_table: string) => ({
    delete: () => ({
      eq: (_col: string, val: string) => {
        captured.eqUserId = val;
        return {
          is: (col: string, val: null) => {
            captured.isHardPurgedAt = { col, val };
            return {
              select: (_cols: string) => {
                captured.deletes++;
                if (cfg.deleteError) {
                  return Promise.resolve({
                    data: null,
                    error: { message: cfg.deleteError },
                  });
                }
                return Promise.resolve({
                  data: cfg.deletedRows ?? [],
                  error: null,
                });
              },
            };
          },
        };
      },
    }),
  });

  // deno-lint-ignore no-explicit-any
  return { admin: { auth, from } as any, captured };
}

function deps(cfg: FakeConfig = {}): HandlerDeps & { captured: { deletes: number; eqUserId: string | null; isHardPurgedAt: { col: string; val: null | string } | null } } {
  const fake = makeFakeAdmin(cfg);
  return { admin: fake.admin, captured: fake.captured };
}

function makeRequest({
  method = 'POST',
  authHeader = `Bearer fake.jwt.token`,
}: { method?: string; authHeader?: string | null } = {}): Request {
  const headers: Record<string, string> = {};
  if (authHeader !== null) headers['Authorization'] = authHeader;
  return new Request('http://test/cancel-account-delete', { method, headers });
}

async function readBody(res: Response): Promise<Record<string, unknown>> {
  const text = await res.text();
  return text ? JSON.parse(text) as Record<string, unknown> : {};
}

// ─── Tests ──────────────────────────────────────────────────────────

Deno.test('OPTIONS preflight → 200 + CORS headers', async () => {
  const d = deps();
  const res = await handleCancelRequest(
    new Request('http://test/cancel', { method: 'OPTIONS' }),
    d,
  );
  assertEquals(res.status, 200);
  assertExists(res.headers.get('Access-Control-Allow-Origin'));
});

Deno.test('non-POST → 405', async () => {
  const d = deps();
  const res = await handleCancelRequest(
    makeRequest({ method: 'GET' }),
    d,
  );
  assertEquals(res.status, 405);
});

Deno.test('missing Authorization → 401', async () => {
  const d = deps();
  const res = await handleCancelRequest(
    makeRequest({ authHeader: null }),
    d,
  );
  assertEquals(res.status, 401);
});

Deno.test('invalid JWT → 401 invalid_jwt', async () => {
  const d = deps({ authUser: null, authError: { message: 'expired' } });
  const res = await handleCancelRequest(makeRequest(), d);
  assertEquals(res.status, 401);
  const body = await readBody(res);
  assertEquals((body.error as { code: string }).code, 'invalid_jwt');
});

Deno.test('happy path — pending row exists → was_pending=true', async () => {
  const d = deps({ deletedRows: [{ id: 42 }] });
  const res = await handleCancelRequest(makeRequest(), d);
  assertEquals(res.status, 200);
  const body = await readBody(res);
  assertEquals(body.was_pending, true);

  // Load-bearing scoping invariants from row 90:
  //   - delete is filtered by user_id (no other user's row touched)
  //   - delete is filtered by hard_purged_at IS NULL (already-purged
  //     audit rows MUST be preserved as steady-state trail)
  assertEquals(d.captured.eqUserId, VALID_USER_ID);
  assertEquals(d.captured.isHardPurgedAt?.col, 'hard_purged_at');
  assertEquals(d.captured.isHardPurgedAt?.val, null);
});

Deno.test('no pending row → was_pending=false (idempotent no-op)', async () => {
  const d = deps({ deletedRows: [] });
  const res = await handleCancelRequest(makeRequest(), d);
  assertEquals(res.status, 200);
  const body = await readBody(res);
  assertEquals(body.was_pending, false);
});

Deno.test('database error → 500 cancel_failed', async () => {
  const d = deps({ deleteError: 'pg_connection_lost' });
  const res = await handleCancelRequest(makeRequest(), d);
  assertEquals(res.status, 500);
  const body = await readBody(res);
  assertEquals((body.error as { code: string }).code, 'cancel_failed');
});

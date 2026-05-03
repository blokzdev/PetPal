// Phase 7 task H.1.d.cron — daily-reconciliation-cron Edge Function tests.
//
// Pins the load-bearing invariants per DECISIONS row 90:
//   - Method gate (405 on non-POST).
//   - Query selects the right subset (pending + past retention +
//     user_id non-null).
//   - Undo path (recent sign-in → audit row deleted, no purge).
//   - Hard-purge path (no recent sign-in → Storage cleared, proxy
//     log cleared, auth user deleted, audit row finalized).
//   - Idempotency (re-run is no-op on already-purged rows).
//   - Error tolerance (per-row failure reported in `errors[]`,
//     loop continues).
//   - Stage-by-stage hard-purge ordering — proxy_request_log delete
//     MUST run before auth.admin.deleteUser (FK SET NULL + check
//     constraint conflict on user-only rows).
//
// Run via `deno test --allow-net --allow-env supabase/functions/_tests/`.

import {
  assert,
  assertEquals,
} from 'https://deno.land/std@0.190.0/assert/mod.ts';
import {
  HandlerDeps,
  handleCronRequest,
  PendingDeletion,
  runReconciliation,
} from '../daily-reconciliation-cron/index.ts';

const FROZEN_NOW = new Date('2026-06-15T03:00:00Z');
const RECENT_SIGN_IN = new Date('2026-06-10T08:00:00Z');
const STALE_SIGN_IN = new Date('2026-04-01T12:00:00Z');

interface UserRecord {
  id: string;
  last_sign_in_at?: string;
}

interface FakeConfig {
  pendingRows?: PendingDeletion[];
  pendingQueryError?: string;
  users?: UserRecord[];
  storageObjects?: Record<string, string[]>;
  storageBucketAvailable?: boolean;
  proxyDeleteError?: string;
  authDeleteError?: string;
  authDeleteNotFound?: boolean;
  auditFinalizeError?: string;
  auditUndoError?: string;
}

interface FakeRecorder {
  storageBucket: string | null;
  storageRemovedPaths: string[];
  proxyDeletes: string[];
  authDeletes: string[];
  auditUpdates: Array<{ id: number; row: Record<string, unknown> }>;
  auditDeletes: number[];
  /** Stage-ordering log — every fake mutation appends here so we can
   *  assert ordering. */
  callOrder: string[];
}

function makeFakeAdmin(cfg: FakeConfig): {
  // deno-lint-ignore no-explicit-any
  admin: any;
  recorder: FakeRecorder;
} {
  const recorder: FakeRecorder = {
    storageBucket: null,
    storageRemovedPaths: [],
    proxyDeletes: [],
    authDeletes: [],
    auditUpdates: [],
    auditDeletes: [],
    callOrder: [],
  };

  const auth = {
    admin: {
      getUserById: (userId: string) => {
        recorder.callOrder.push(`getUserById:${userId}`);
        const u = (cfg.users ?? []).find((x) => x.id === userId);
        if (!u) {
          return Promise.resolve({
            data: null,
            error: { message: 'user_not_found' },
          });
        }
        return Promise.resolve({
          data: { user: u },
          error: null,
        });
      },
      deleteUser: (userId: string) => {
        recorder.callOrder.push(`deleteUser:${userId}`);
        recorder.authDeletes.push(userId);
        if (cfg.authDeleteNotFound) {
          return Promise.resolve({ error: { message: 'User not found' } });
        }
        if (cfg.authDeleteError) {
          return Promise.resolve({ error: { message: cfg.authDeleteError } });
        }
        return Promise.resolve({ error: null });
      },
    },
  };

  const storageBucket = {
    list: (path: string, _opts: unknown) => {
      const objects = cfg.storageObjects ?? {};
      // Top-level call: bucket.list(<user_id>) returns subfolders.
      // Each pet folder contains files under <user_id>/<pet>/<file>.
      const direct = objects[path] ?? [];
      return Promise.resolve({
        data: direct.map((name) => ({ name })),
        error: null,
      });
    },
    remove: (paths: string[]) => {
      recorder.callOrder.push(`storage.remove:${paths.length}`);
      recorder.storageRemovedPaths.push(...paths);
      return Promise.resolve({ data: null, error: null });
    },
  };

  const storage = cfg.storageBucketAvailable === false
    ? undefined
    : {
        from: (bucket: string) => {
          recorder.storageBucket = bucket;
          return storageBucket;
        },
      };

  const from = (table: string) => {
    if (table === 'deleted_accounts_log') {
      return {
        select: (_cols: string) => ({
          is: (_col: string, _val: null) => ({
            not: (_c: string, _o: string, _v: null) => ({
              lte: (_c: string, _ts: string) =>
                Promise.resolve({
                  data: cfg.pendingQueryError
                    ? null
                    : (cfg.pendingRows ?? []),
                  error: cfg.pendingQueryError
                    ? { message: cfg.pendingQueryError }
                    : null,
                }),
            }),
          }),
        }),
        update: (row: Record<string, unknown>) => ({
          eq: (_col: string, id: number) => {
            recorder.callOrder.push(`audit.update:${id}`);
            recorder.auditUpdates.push({ id, row });
            return Promise.resolve({
              data: null,
              error: cfg.auditFinalizeError
                ? { message: cfg.auditFinalizeError }
                : null,
            });
          },
        }),
        delete: () => ({
          eq: (_col: string, id: number) => {
            recorder.callOrder.push(`audit.delete:${id}`);
            recorder.auditDeletes.push(id);
            return Promise.resolve({
              data: null,
              error: cfg.auditUndoError
                ? { message: cfg.auditUndoError }
                : null,
            });
          },
        }),
      };
    }
    if (table === 'proxy_request_log') {
      return {
        delete: () => ({
          eq: (_col: string, userId: string) => {
            recorder.callOrder.push(`proxy.delete:${userId}`);
            recorder.proxyDeletes.push(userId);
            return Promise.resolve({
              data: null,
              error: cfg.proxyDeleteError
                ? { message: cfg.proxyDeleteError }
                : null,
            });
          },
        }),
      };
    }
    throw new Error(`unexpected table: ${table}`);
  };

  return {
    admin: { auth, from, storage },
    recorder,
  };
}

function deps(cfg: FakeConfig): HandlerDeps & { recorder: FakeRecorder } {
  const fake = makeFakeAdmin(cfg);
  return {
    admin: fake.admin,
    now: () => FROZEN_NOW,
    recorder: fake.recorder,
  };
}

const sampleRow = (overrides: Partial<PendingDeletion> = {}): PendingDeletion => ({
  id: 1,
  user_id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  delete_requested_at: '2026-05-15T12:00:00Z',
  retention_window_ends_at: '2026-06-14T12:00:00Z',
  ...overrides,
});

// ─── Method + query gates ──────────────────────────────────────────

Deno.test('non-POST request → 405', async () => {
  const d = deps({ pendingRows: [] });
  const res = await handleCronRequest(
    new Request('http://test/cron', { method: 'GET' }),
    d,
  );
  assertEquals(res.status, 405);
});

Deno.test('empty pending list → scanned=0', async () => {
  const d = deps({ pendingRows: [] });
  const result = await runReconciliation(d);
  assertEquals(result.scanned, 0);
  assertEquals(result.purged, 0);
  assertEquals(result.undone, 0);
  assertEquals(result.errors.length, 0);
});

Deno.test('query error surfaces in errors[] without crashing', async () => {
  const d = deps({ pendingQueryError: 'connection_lost' });
  const result = await runReconciliation(d);
  assertEquals(result.scanned, 0);
  assertEquals(result.errors.length, 1);
  assertEquals(result.errors[0].stage, 'query_pending');
});

// ─── Undo path ──────────────────────────────────────────────────────

Deno.test('user signed in after delete request → undo (audit row deleted)',
  async () => {
    const row = sampleRow();
    const d = deps({
      pendingRows: [row],
      users: [{ id: row.user_id, last_sign_in_at: RECENT_SIGN_IN.toISOString() }],
    });
    const result = await runReconciliation(d);
    assertEquals(result.scanned, 1);
    assertEquals(result.undone, 1);
    assertEquals(result.purged, 0);
    assertEquals(d.recorder.auditDeletes, [row.id]);
    // Hard-purge work must NOT run on the undo path.
    assertEquals(d.recorder.proxyDeletes.length, 0);
    assertEquals(d.recorder.authDeletes.length, 0);
    assertEquals(d.recorder.storageRemovedPaths.length, 0);
  });

Deno.test('user signed in BEFORE delete request → hard-purge (no undo)',
  async () => {
    const row = sampleRow();
    const d = deps({
      pendingRows: [row],
      users: [{ id: row.user_id, last_sign_in_at: STALE_SIGN_IN.toISOString() }],
    });
    const result = await runReconciliation(d);
    assertEquals(result.undone, 0);
    assertEquals(result.purged, 1);
  });

Deno.test('user with no sign-in record → hard-purge', async () => {
  const row = sampleRow();
  const d = deps({
    pendingRows: [row],
    users: [{ id: row.user_id }], // no last_sign_in_at
  });
  const result = await runReconciliation(d);
  assertEquals(result.purged, 1);
  assertEquals(result.undone, 0);
});

// ─── Hard-purge path ────────────────────────────────────────────────

Deno.test('hard-purge — Storage cleared, proxy log cleared, auth user deleted, audit finalized',
  async () => {
    const row = sampleRow();
    const d = deps({
      pendingRows: [row],
      users: [{ id: row.user_id }],
      storageObjects: {
        [row.user_id]: ['42', '43'],
        [`${row.user_id}/42`]: ['vet/visit.md.enc', 'weight/log.md.enc'],
        [`${row.user_id}/43`]: ['SOUL.md.enc'],
      },
    });
    const result = await runReconciliation(d);
    assertEquals(result.purged, 1);
    assertEquals(result.errors.length, 0);

    // Storage paths reflect the recursed file listing.
    assertEquals(d.recorder.storageBucket, 'wiki');
    assertEquals(d.recorder.storageRemovedPaths.sort(), [
      `${row.user_id}/42/vet/visit.md.enc`,
      `${row.user_id}/42/weight/log.md.enc`,
      `${row.user_id}/43/SOUL.md.enc`,
    ].sort());

    // Proxy log cleared.
    assertEquals(d.recorder.proxyDeletes, [row.user_id]);

    // Auth user deleted.
    assertEquals(d.recorder.authDeletes, [row.user_id]);

    // Audit row finalized — hard_purged_at + user_id NULL.
    assertEquals(d.recorder.auditUpdates.length, 1);
    const update = d.recorder.auditUpdates[0];
    assertEquals(update.id, row.id);
    assertEquals(update.row.hard_purged_at, FROZEN_NOW.toISOString());
    assertEquals(update.row.user_id, null);
  });

Deno.test('hard-purge — proxy_request_log delete MUST precede auth.admin.deleteUser',
  async () => {
    // Load-bearing ordering invariant per DECISIONS row 90: the FK
    // is ON DELETE SET NULL, but proxy_request_log's check
    // constraint requires (user_id IS NULL) XOR (device_token IS
    // NULL); SET NULL on a user-only row would fail the check.
    // Explicit DELETE before auth deletion sidesteps the conflict.
    const row = sampleRow();
    const d = deps({
      pendingRows: [row],
      users: [{ id: row.user_id }],
    });
    await runReconciliation(d);

    const proxyIdx = d.recorder.callOrder.findIndex(
      (s) => s.startsWith('proxy.delete:'),
    );
    const authIdx = d.recorder.callOrder.findIndex(
      (s) => s.startsWith('deleteUser:'),
    );
    assert(proxyIdx >= 0, 'proxy.delete must be invoked');
    assert(authIdx >= 0, 'deleteUser must be invoked');
    assert(
      proxyIdx < authIdx,
      `proxy.delete must precede deleteUser; ` +
        `got proxyIdx=${proxyIdx}, authIdx=${authIdx}, ` +
        `order=${JSON.stringify(d.recorder.callOrder)}`,
    );
  });

Deno.test('hard-purge — auth user_not_found is tolerated (idempotent re-run)',
  async () => {
    const row = sampleRow();
    const d = deps({
      pendingRows: [row],
      users: [{ id: row.user_id }],
      authDeleteNotFound: true,
    });
    const result = await runReconciliation(d);
    assertEquals(result.purged, 1);
    assertEquals(result.errors.length, 0);
    // Audit row still finalized — the audit trail is the source of
    // truth for "we deleted this account."
    assertEquals(d.recorder.auditUpdates.length, 1);
  });

Deno.test('hard-purge — proxy delete failure surfaces in errors[]', async () => {
  const row = sampleRow();
  const d = deps({
    pendingRows: [row],
    users: [{ id: row.user_id }],
    proxyDeleteError: 'pg_connection_lost',
  });
  const result = await runReconciliation(d);
  assertEquals(result.purged, 0);
  assertEquals(result.errors.length, 1);
  assertEquals(result.errors[0].user_id, row.user_id);
  assertEquals(result.errors[0].stage, 'process_row');
});

Deno.test('multiple rows — one failure does not block the rest', async () => {
  const ok = sampleRow({ id: 1, user_id: '11111111-1111-1111-1111-111111111111' });
  const fail = sampleRow({ id: 2, user_id: '22222222-2222-2222-2222-222222222222' });
  const ok2 = sampleRow({ id: 3, user_id: '33333333-3333-3333-3333-333333333333' });

  // Make the middle row's auth.admin.deleteUser hard-fail (non-not-found).
  let firstSeen = false;
  const cfg: FakeConfig = {
    pendingRows: [ok, fail, ok2],
    users: [
      { id: ok.user_id },
      { id: fail.user_id },
      { id: ok2.user_id },
    ],
  };

  // Custom fake — wrap deleteUser to inject error on the middle row.
  const fake = makeFakeAdmin(cfg);
  const origDelete = fake.admin.auth.admin.deleteUser;
  fake.admin.auth.admin.deleteUser = (userId: string) => {
    if (userId === fail.user_id && !firstSeen) {
      firstSeen = true;
      return Promise.resolve({ error: { message: 'storage_full' } });
    }
    return origDelete(userId);
  };

  const result = await runReconciliation({
    admin: fake.admin,
    now: () => FROZEN_NOW,
  });

  assertEquals(result.scanned, 3);
  assertEquals(result.purged, 2);
  assertEquals(result.errors.length, 1);
  assertEquals(result.errors[0].user_id, fail.user_id);
});

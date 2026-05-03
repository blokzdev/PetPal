// daily-reconciliation-cron — Phase 7 task H.1.d.cron.
//
// Per DECISIONS row 77 (Option e: 30-day soft delete) + row 90
// (this row's H.1.d.cron close).
//
// Runs once per day, triggered by pg_cron via `net.http_post` with
// the service-role JWT (verify_jwt = true on this function — internal
// use only). For each pending account-deletion whose retention window
// has expired, this function either:
//
//   1. **Undoes the deletion** if the user signed in during the
//      window (`auth.users.last_sign_in_at > delete_requested_at`).
//      DELETEs the `deleted_accounts_log` row entirely — the user's
//      sign-in proved intent to keep the account.
//   2. **Hard-purges** otherwise:
//      a. Storage: list + delete every object under prefix
//         `<user_id>/` in the `wiki` bucket.
//      b. `proxy_request_log` — explicit DELETE before the auth.users
//         delete, because the FK is ON DELETE SET NULL and the table's
//         check constraint requires exactly one of (user_id,
//         device_token) to be non-null. SET NULL on a user-only row
//         would fail the check.
//      c. `auth.admin.deleteUser(user_id)` — cascades via FK to
//         entitlements, sync_challenges, wiki_sync_objects,
//         banned_user_ids.
//      d. UPDATE `deleted_accounts_log` SET hard_purged_at = now(),
//         user_id = NULL — the audit row stays as the PII-free
//         compliance trail.
//
// **Idempotency.** Hard-purge is naturally idempotent — re-running
// against an already-purged user_id is a no-op (Storage list returns
// empty, proxy_request_log delete affects 0 rows, auth.admin.deleteUser
// returns user_not_found which we treat as success). The audit-row
// UPDATE is conditional on hard_purged_at IS NULL (idempotent).
//
// **Observability.** Returns a JSON summary of {scanned, undone,
// purged, errors[]} so cron operators can monitor for stuck
// deletions.
//
// **Wiki bucket.** Per migration 0002 + DECISIONS row 83, objects
// are keyed `<user_id>/<pet_id>/<relative_path>.enc`. List recursively
// under `<user_id>/`, batch-delete in groups of 1000 (Storage API
// limit).
//
// **The undo defensive check is belt-and-suspenders.** The
// `cancel-account-delete` Edge Function (sibling commit) is the
// proactive client-driven path; this cron-side check covers users
// who sign in via a different surface or before the cancel function
// existed.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { jsonError, jsonOk } from '../llm-proxy/_shared.ts';

const STORAGE_BUCKET = 'wiki';
const STORAGE_BATCH_SIZE = 1000;

export interface PendingDeletion {
  id: number;
  user_id: string;
  delete_requested_at: string;
  retention_window_ends_at: string;
}

export interface CronResult {
  scanned: number;
  undone: number;
  purged: number;
  errors: Array<{ user_id: string | null; stage: string; message: string }>;
}

export interface HandlerDeps {
  /** Service-role client. */
  admin: ReturnType<typeof createClient>;
  /** Override for tests; defaults to Date.now(). */
  now?: () => Date;
}

export async function handleCronRequest(
  req: Request,
  deps: HandlerDeps,
): Promise<Response> {
  if (req.method !== 'POST') {
    return jsonError(405, 'method_not_allowed');
  }

  const result = await runReconciliation(deps);
  return jsonOk(result);
}

export async function runReconciliation(
  deps: HandlerDeps,
): Promise<CronResult> {
  const now = deps.now ? deps.now() : new Date();
  const result: CronResult = {
    scanned: 0,
    undone: 0,
    purged: 0,
    errors: [],
  };

  // Query the index-friendly subset: pending rows past retention
  // with user_id still attached. Rows with NULL user_id are already
  // hard-purged and serve only as historical audit trail.
  const { data: pending, error: queryErr } = await deps.admin
    .from('deleted_accounts_log')
    .select('id, user_id, delete_requested_at, retention_window_ends_at')
    .is('hard_purged_at', null)
    .not('user_id', 'is', null)
    .lte('retention_window_ends_at', now.toISOString());

  if (queryErr) {
    result.errors.push({
      user_id: null,
      stage: 'query_pending',
      message: queryErr.message,
    });
    return result;
  }

  const rows = (pending ?? []) as unknown as PendingDeletion[];
  result.scanned = rows.length;

  for (const row of rows) {
    try {
      const undone = await maybeUndo(row, deps);
      if (undone) {
        result.undone++;
      } else {
        await hardPurge(row, deps, now);
        result.purged++;
      }
    } catch (e) {
      result.errors.push({
        user_id: row.user_id,
        stage: 'process_row',
        message: e instanceof Error ? e.message : String(e),
      });
    }
  }

  return result;
}

/// Returns true if the user signed in during the retention window —
/// the deletion is reversed (audit row removed).
async function maybeUndo(
  row: PendingDeletion,
  deps: HandlerDeps,
): Promise<boolean> {
  // deno-lint-ignore no-explicit-any
  const adminAuth = (deps.admin.auth as any).admin;
  if (!adminAuth?.getUserById) {
    // Test fakes without the admin surface — skip the undo check.
    // Real Supabase always exposes admin.getUserById on service role.
    return false;
  }

  const { data, error } = await adminAuth.getUserById(row.user_id);
  if (error) {
    // user_not_found: the auth row is already gone (manual ops or a
    // prior partial run). Treat as "no sign-in"; downstream
    // hardPurge will be a near-no-op + still mark the audit row.
    return false;
  }

  const lastSignIn = data?.user?.last_sign_in_at as string | undefined;
  if (!lastSignIn) return false;

  const signedInAt = new Date(lastSignIn);
  const requestedAt = new Date(row.delete_requested_at);
  if (signedInAt.getTime() <= requestedAt.getTime()) return false;

  // Sign-in is more recent than the delete request → undo.
  const { error: deleteErr } = await deps.admin
    .from('deleted_accounts_log')
    .delete()
    .eq('id', row.id);
  if (deleteErr) {
    throw new Error(`undo_delete_failed: ${deleteErr.message}`);
  }
  return true;
}

async function hardPurge(
  row: PendingDeletion,
  deps: HandlerDeps,
  now: Date,
): Promise<void> {
  const userId = row.user_id;

  // 1. Storage — list + delete every object under `<user_id>/`.
  await purgeWikiBucket(userId, deps);

  // 2. proxy_request_log — explicit DELETE because the FK is SET
  //    NULL but the row's check constraint requires (user_id IS NULL)
  //    XOR (device_token IS NULL); user-only rows would fail check
  //    after a SET NULL.
  const { error: proxyErr } = await deps.admin
    .from('proxy_request_log')
    .delete()
    .eq('user_id', userId);
  if (proxyErr) {
    throw new Error(`purge_proxy_log_failed: ${proxyErr.message}`);
  }

  // 3. auth.admin.deleteUser — cascades to entitlements,
  //    sync_challenges, wiki_sync_objects, banned_user_ids via FK.
  // deno-lint-ignore no-explicit-any
  const adminAuth = (deps.admin.auth as any).admin;
  if (adminAuth?.deleteUser) {
    const { error: authErr } = await adminAuth.deleteUser(userId);
    if (authErr) {
      const msg = (authErr as { message?: string }).message ?? '';
      // user_not_found is acceptable — already purged in a prior
      // partial run. Anything else surfaces.
      if (!msg.toLowerCase().includes('not found')) {
        throw new Error(`auth_delete_user_failed: ${msg}`);
      }
    }
  }

  // 4. Mark the audit row purged + NULL out the operational user_id
  //    so the steady-state row is hash + timestamps only.
  const { error: updateErr } = await deps.admin
    .from('deleted_accounts_log')
    .update({
      hard_purged_at: now.toISOString(),
      user_id: null,
    })
    .eq('id', row.id);
  if (updateErr) {
    throw new Error(`audit_finalize_failed: ${updateErr.message}`);
  }
}

async function purgeWikiBucket(
  userId: string,
  deps: HandlerDeps,
): Promise<void> {
  // deno-lint-ignore no-explicit-any
  const storage = (deps.admin as any).storage;
  if (!storage?.from) return; // tests without storage surface

  const bucket = storage.from(STORAGE_BUCKET);
  const paths = await listAllObjects(bucket, userId);
  if (paths.length === 0) return;

  // Storage API caps batch deletes at 1000 paths per call.
  for (let i = 0; i < paths.length; i += STORAGE_BATCH_SIZE) {
    const batch = paths.slice(i, i + STORAGE_BATCH_SIZE);
    const { error } = await bucket.remove(batch);
    if (error) {
      throw new Error(
        `purge_storage_failed: ${(error as { message?: string }).message ?? error}`,
      );
    }
  }
}

async function listAllObjects(
  // deno-lint-ignore no-explicit-any
  bucket: any,
  userId: string,
): Promise<string[]> {
  // Supabase Storage list is shallow per `prefix` — recurse into
  // each pet-id subfolder. Object keys are
  // `<user_id>/<pet_id>/<relative>.enc` (DECISIONS row 83).
  const out: string[] = [];

  const { data: top, error: topErr } = await bucket.list(userId, {
    limit: STORAGE_BATCH_SIZE,
  });
  if (topErr) {
    throw new Error(
      `list_storage_failed: ${(topErr as { message?: string }).message ?? topErr}`,
    );
  }
  if (!top) return out;

  for (const entry of top as Array<{ name: string }>) {
    const subPath = `${userId}/${entry.name}`;
    // Folders show up with no `metadata`; files have metadata. Both
    // surface the same `name` field. Recurse one level for folders;
    // files at top-level shouldn't exist per the row-83 keyspace but
    // are caught defensively.
    const { data: nested, error: nestErr } = await bucket.list(subPath, {
      limit: STORAGE_BATCH_SIZE,
    });
    if (nestErr) {
      throw new Error(
        `list_storage_failed: ${(nestErr as { message?: string }).message ?? nestErr}`,
      );
    }
    if (nested && nested.length > 0) {
      for (const file of nested as Array<{ name: string }>) {
        out.push(`${subPath}/${file.name}`);
      }
    } else {
      // Leaf file directly at <user_id>/<name>.
      out.push(subPath);
    }
  }

  return out;
}

if (import.meta.main) {
  const admin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { persistSession: false } },
  );

  Deno.serve((req) => handleCronRequest(req, { admin }));
}

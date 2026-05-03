// cancel-account-delete — Phase 7 task H.1.d.undo (proactive client path).
//
// Per DECISIONS row 77 (30-day undo window) + row 90 (this row's
// H.1.d.undo close).
//
// Companion to `account-delete` + `daily-reconciliation-cron`. When
// the user signs in during the 30-day retention window, the client
// fires this function to immediately cancel the pending deletion —
// the cron-side `last_sign_in_at` check is the belt-and-suspenders
// defence; this is the proactive path.
//
// Contract:
//   - POST + JWT-authenticated. Same auth pattern as `account-delete`.
//   - Service-role client deletes any
//     `deleted_accounts_log WHERE user_id = ? AND hard_purged_at IS NULL`.
//   - Returns `{ was_pending: bool }` — true if a pending row was
//     deleted, false if no pending deletion existed (idempotent
//     no-op response).
//   - Once `hard_purged_at` is non-null the row is the steady-state
//     audit trail and must NOT be touched (the deletion already
//     completed; "cancel" no longer applies).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { corsHeaders, jsonError, jsonOk } from '../llm-proxy/_shared.ts';

export interface HandlerDeps {
  /** Service-role client. */
  admin: ReturnType<typeof createClient>;
}

export async function handleCancelRequest(
  req: Request,
  deps: HandlerDeps,
): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonError(405, 'method_not_allowed');
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    return jsonError(401, 'unauthorized');
  }
  const jwt = authHeader.substring('Bearer '.length).trim();
  if (jwt.length === 0) {
    return jsonError(401, 'unauthorized');
  }

  const { data: userResp, error: userErr } =
    await deps.admin.auth.getUser(jwt);
  if (userErr || !userResp?.user) {
    return jsonError(401, 'invalid_jwt');
  }
  const userId = userResp.user.id;

  // Delete only PENDING rows (hard_purged_at IS NULL). Already-purged
  // rows are the historical trail and must be preserved.
  // PostgREST `delete().eq().is()` returns the affected rows when
  // we ask for them via `.select()`.
  const { data: deleted, error: deleteErr } = await deps.admin
    .from('deleted_accounts_log')
    .delete()
    .eq('user_id', userId)
    .is('hard_purged_at', null)
    .select('id');

  if (deleteErr) {
    return jsonError(500, 'cancel_failed', deleteErr.message);
  }

  const wasPending = (deleted ?? []).length > 0;
  return jsonOk({ was_pending: wasPending });
}

if (import.meta.main) {
  const admin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { persistSession: false } },
  );

  Deno.serve((req) => handleCancelRequest(req, { admin }));
}

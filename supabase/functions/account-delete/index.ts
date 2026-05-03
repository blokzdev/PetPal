// account-delete — Phase 7 task H.1.d soft-delete cascade.
//
// Per DECISIONS row 77 — Option (e): soft delete + 30-day window.
// User taps "Delete account", confirmation cascade fires, this Edge
// Function:
//
//   1. Authenticates the request via the user's Supabase JWT.
//   2. Hashes the auth UUID with SHA-256 — the audit log holds the
//      hash, NOT the user_id, so the GDPR/CCPA "we deleted everything
//      including identity" claim holds even if the audit log itself
//      is preserved.
//   3. Inserts a row in `deleted_accounts_log` with
//      retention_window_ends_at = now() + 30 days.
//   4. Signs the user out of the current session — the client also
//      clears its local session, so post-call the device is signed
//      out.
//
// What this Edge Function does NOT do (deferred to a follow-up
// commit alongside the daily cron):
//
//   - Hard-purge of wiki blobs, entitlement row, counter rows,
//     proxy_request_log entries, and the auth.users row. Per row 77
//     these run on the cron AT THE END of the 30-day window so the
//     user can sign in to undo within that window.
//   - Undo path. v1 ships a hard 30-day window; if the user signs in
//     during the window, the cron sees their fresh `last_sign_in_at`
//     and removes the deleted_accounts_log row before hard-purge
//     fires. (Implementation lands with the cron commit.)
//
// Identity model (DECISIONS row 70 + 82): magic-link Supabase Auth.
// JWT in the Authorization header is the single auth signal.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { corsHeaders, jsonError, jsonOk } from '../llm-proxy/_shared.ts';

const RETENTION_DAYS = 30;

export interface HandlerDeps {
  /** Service-role client — bypasses RLS for the audit log insert
   *  and the auth.signOut admin call. */
  admin: ReturnType<typeof createClient>;
  /** Override for tests; defaults to native crypto.subtle.digest. */
  sha256?: (s: string) => Promise<string>;
  /** Override for tests; defaults to Date.now(). */
  now?: () => Date;
}

export async function handleDeleteRequest(
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

  // Validate JWT + extract user_id via the admin client.
  const { data: userResp, error: userErr } =
    await deps.admin.auth.getUser(jwt);
  if (userErr || !userResp?.user) {
    return jsonError(401, 'invalid_jwt');
  }
  const userId = userResp.user.id;

  // Hash user_id for the audit row.
  const hashFn = deps.sha256 ?? defaultSha256Hex;
  const userIdHash = await hashFn(userId);

  const now = deps.now ? deps.now() : new Date();
  const retentionEnd = new Date(
    now.getTime() + RETENTION_DAYS * 24 * 60 * 60 * 1000,
  );

  // Insert the audit row. RLS is bypassed via the service-role
  // client; the table itself has no RLS policy that would let a
  // signed-in user write to it directly.
  const { error: insertErr } = await deps.admin
    .from('deleted_accounts_log')
    .insert({
      user_id_hash: userIdHash,
      delete_requested_at: now.toISOString(),
      retention_window_ends_at: retentionEnd.toISOString(),
    });
  if (insertErr) {
    return jsonError(500, 'insert_failed', insertErr.message);
  }

  // Sign the user out of this session so the JWT they hold becomes
  // invalid. The client also clears its local session, but
  // belt-and-suspenders. (Note: we use admin.auth.admin.signOut
  // — admin scope is required to invalidate someone else's session
  // by user_id.)
  // deno-lint-ignore no-explicit-any
  const adminAuth = (deps.admin.auth as any).admin;
  if (adminAuth?.signOut) {
    await adminAuth.signOut(userId);
  }

  return jsonOk({
    retention_window_ends_at: retentionEnd.toISOString(),
  });
}

async function defaultSha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(input),
  );
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

if (import.meta.main) {
  const admin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { persistSession: false } },
  );

  Deno.serve((req) => handleDeleteRequest(req, { admin }));
}

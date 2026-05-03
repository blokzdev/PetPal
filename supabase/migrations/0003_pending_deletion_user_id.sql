-- Phase 7 task H.1.d.cron — operational user_id column on deleted_accounts_log.
--
-- Source-of-truth: DECISIONS row 87 (sub-piece deferral) + row 90
-- (this row's H.1.d.cron close).
--
-- Background. Migration 0001 created `deleted_accounts_log` with only
-- `user_id_hash` (one-way SHA-256) so the steady-state audit trail
-- carries no PII — important for GDPR/CCPA compliance proofs that may
-- be retained for years. But the daily-reconciliation cron needs the
-- actual user_id during the 30-day retention window to:
--   - Look up `auth.users.last_sign_in_at` for the undo check.
--   - Hard-purge wiki blobs from Supabase Storage at prefix
--     `<user_id>/`.
--   - Cascade-delete via `auth.admin.deleteUser(user_id)`.
--
-- Solution. Add `user_id uuid` column (FK to `auth.users.id`, ON
-- DELETE SET NULL). The column is non-null during the 30-day window
-- (account-delete writes it alongside the hash). After hard-purge
-- completes, the cron NULLs it out — the audit trail is back to
-- hash-only steady state.
--
-- Pre-launch — no production data — so no backfill required.

alter table public.deleted_accounts_log
  add column user_id uuid references auth.users(id) on delete set null;

-- Index for the cron's primary query: pending rows past retention,
-- with user_id still present (rows where user_id is null are already
-- hard-purged, just the audit-hash trail remains).
create index deleted_accounts_log_pending_purge_idx
  on public.deleted_accounts_log (retention_window_ends_at, user_id)
  where hard_purged_at is null and user_id is not null;

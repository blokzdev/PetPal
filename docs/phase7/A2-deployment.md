# Phase 7 Group A.2 — Backend deployment checklist

This is the one-time provisioning + secrets checklist for the
Supabase backend. Locked spec lives in `DECISIONS.md` row 82.

Estimated time: 30–45 minutes for a clean run.

## Prerequisites

- A Google Cloud Platform / Supabase account (free tier OK for `petpal-dev`).
- A paid Anthropic account with a master API key. **This key funds the
  free 200-msg/mo allowance** — do not commit it anywhere.
- Play Console access (for the RTDN webhook URL registration in step 7).
- [Supabase CLI](https://supabase.com/docs/guides/cli) installed locally
  (`brew install supabase/tap/supabase` on macOS,
  `scoop install supabase` on Windows).
- [Deno](https://deno.com/) installed (the Edge Function runtime; also
  needed locally to run `deno test`).

## Step 1 — Create the Supabase projects

In the Supabase Dashboard:

1. Click **New project**. Name: `petpal-dev`. Region: `us-east-1`.
   Tier: Free. Database password: store in your password manager.
2. Repeat for `petpal-prod`. **Tier: Pro** ($25/mo). Region: `us-east-1`.

Capture from each project's Settings → API page:

- `Project URL` (e.g. `https://xxxxxxxx.supabase.co`)
- `anon public` key
- `service_role secret` key (treat like a password)

## Step 2 — Link the local repo to the dev project

From the repo root:

```bash
cd /path/to/PetPal
supabase login                            # one-time auth
supabase link --project-ref <petpal-dev-project-ref>
```

(`<petpal-dev-project-ref>` is the slug in the project URL — the
`xxxxxxxx` part of `https://xxxxxxxx.supabase.co`.)

## Step 3 — Push the schema migration

```bash
supabase db push
```

This applies `supabase/migrations/0001_phase7_init.sql` to the dev
project. Tables created:

- `entitlements` (one row per signed-in user)
- `anonymous_counters` (signed-out free users)
- `banned_device_tokens` / `banned_user_ids`
- `proxy_request_log` (request metadata, no chat content)
- `deleted_accounts_log` (GDPR audit trail)

Functions created: `check_rate_limit`, `increment_text_counter`,
`reset_monthly_counters`, `purge_stale_anonymous_counters`,
`purge_stale_proxy_logs`, `touch_updated_at`.

RLS enabled on all tables. The only user-facing policy is "users
read own entitlement"; everything else is service-role-only.

## Step 4 — Set Edge Function secrets

```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
```

Verify:

```bash
supabase secrets list
```

You should see `ANTHROPIC_API_KEY`. Supabase's `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY` are auto-injected — no manual set needed.

## Step 5 — Deploy the Edge Functions

```bash
supabase functions deploy llm-proxy
supabase functions deploy account-delete
supabase functions deploy cancel-account-delete
supabase functions deploy daily-reconciliation-cron
```

(`play-billing-webhook` is declared but not yet implemented; deploy
it when Group C.1 ships its index.ts.)

The deployed function URLs are:
- `https://<project-ref>.supabase.co/functions/v1/llm-proxy`
- `https://<project-ref>.supabase.co/functions/v1/account-delete`
- `https://<project-ref>.supabase.co/functions/v1/cancel-account-delete`
- `https://<project-ref>.supabase.co/functions/v1/daily-reconciliation-cron`

Verify the proxy with a curl ping (this should return 401 since we
haven't supplied auth):

```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/llm-proxy" \
     -H "content-type: application/json" \
     -d '{}' | jq
```

Expected: `{"error":{"code":"unauthorized",...}}`

The same shape works against `account-delete` + `cancel-account-delete`.

## Step 6 — Configure cron jobs (counter reset + storage hygiene + account purge)

In the Supabase Dashboard → Database → Extensions, enable `pg_cron`
**and** `pg_net` (the latter is required for the
`daily-reconciliation-cron` HTTP invocation in step 6c).

### 6a — Internal SQL crons

```sql
select cron.schedule(
  'reset-monthly-counters',
  '0 2 * * *',   -- nightly at 02:00 UTC
  $$ select public.reset_monthly_counters() $$
);

select cron.schedule(
  'purge-stale-anonymous-counters',
  '0 3 * * *',   -- nightly at 03:00 UTC
  $$ select public.purge_stale_anonymous_counters() $$
);

select cron.schedule(
  'purge-stale-proxy-logs',
  '0 4 * * *',   -- nightly at 04:00 UTC
  $$ select public.purge_stale_proxy_logs() $$
);
```

These are idempotent — re-running won't reset already-reset counters.

### 6b — Daily-reconciliation-cron secret

Set a `cron_secret` setting that authenticates the daily-purge
HTTP call. The secret rides as the `Authorization` header so the
Edge Function (`verify_jwt = true`) treats it as a service-role
invocation.

```sql
-- Generate a strong random secret (run once; capture the output).
select encode(gen_random_bytes(32), 'hex');
-- Example output: e3a9f5b2c1...   (64 hex chars)

-- Persist as a Postgres setting (replace <SERVICE_ROLE_JWT> with the
-- service_role key from Settings → API; the Edge Function expects a
-- Supabase JWT with role=service_role per supabase/config.toml's
-- verify_jwt=true on this function).
alter database postgres set "app.daily_cron_jwt" = '<SERVICE_ROLE_JWT>';
```

### 6c — Daily account-deletion purge cron

Per DECISIONS row 90 — runs the `daily-reconciliation-cron` Edge
Function once daily. The function scans `deleted_accounts_log` for
entries past their 30-day retention window, undoes deletions for
users who signed in during the window, hard-purges everything else.

```sql
select cron.schedule(
  'daily-account-purge',
  '0 5 * * *',   -- nightly at 05:00 UTC (after the SQL crons above)
  $$
    select net.http_post(
      url := 'https://<project-ref>.supabase.co/functions/v1/daily-reconciliation-cron',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || current_setting('app.daily_cron_jwt'),
        'Content-Type', 'application/json'
      ),
      body := '{}'::jsonb
    );
  $$
);
```

Replace `<project-ref>` with the project slug from step 1.

### 6d — Verify cron registration

```sql
select * from cron.job;
```

Expected: 4 rows for `reset-monthly-counters`,
`purge-stale-anonymous-counters`, `purge-stale-proxy-logs`,
`daily-account-purge`.

### 6e — Smoke-test the daily-reconciliation-cron manually

Before letting the cron run unattended, fire it once with a
service-role JWT:

```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/daily-reconciliation-cron" \
     -H "Authorization: Bearer <SERVICE_ROLE_JWT>" \
     -H "Content-Type: application/json" \
     -d '{}' | jq
```

Expected: `{"scanned": 0, "undone": 0, "purged": 0, "errors": []}`
(non-zero counts on prod once real deletions land).

## Step 7 — Set up cost-run-up alerts

Per DECISIONS row 82:

- **Global daily spend** — soft warn at $50/day, hard alert at $200/day.
- **Per-user daily spend** — soft warn at $5/day per user.
- **Edge Function 5xx rate** — alert at >5% in any 15-min window.

Implementation paths:

1. **Anthropic-side dashboard.** In the Anthropic console, set a
   monthly spend alert at the projected steady-state cap (start with
   $500/mo and tune).
2. **Supabase-side query.** Run as a manual nightly cron initially
   (until traffic warrants real alerting infra):
   ```sql
   select sum(input_tokens * 3.0 / 1e6 + output_tokens * 15.0 / 1e6) as usd_estimate
   from proxy_request_log
   where request_at > now() - interval '24 hours';
   ```
   (Using Sonnet pricing $3/$15 per MTok input/output as v1 baseline.)
3. **Edge Function 5xx.** Supabase Dashboard → Edge Functions → logs
   tab. Filter by status >= 500.

v1.x: replace the manual queries with Slack/email webhooks via Supabase
Functions cron triggers.

## Step 8 — Production deploy (after dev verification)

Repeat steps 2–7 against `petpal-prod`. Use a separate `.env.prod`
locally if you want to avoid `supabase link` thrashing between dev
and prod.

Production-only:

- **Custom domain** (optional): map `api.petpal.app` to the project.
- **Daily backups**: enabled by default on Pro tier; verify in
  Settings → Database → Backups.
- **Email deliverability monitoring**: Settings → Authentication
  → Email. Watch bounce rate; switch to Resend/Postmark if >2%.

## Step 9 — Run tests

Locally, against the dev project:

```bash
# Database / SQL function tests (smoke test the migration + RPCs)
supabase db reset                  # rebuilds dev DB from migrations
psql "$(supabase db remote-url)" \
  -c "SELECT public.check_rate_limit('00000000-0000-0000-0000-000000000000', 'user');"
# Should return: {"allowed": true}

# Edge Function tests
deno test --allow-net --allow-env supabase/functions/_tests/
```

Expected: 4 test files (`llm_proxy_test.ts`, `account_delete_test.ts`,
`cancel_account_delete_test.ts`, `daily_reconciliation_cron_test.ts`)
covering ~40 invariants total. All must pass.

## Step 10 — Hand-off

Once the above is green, A.2 is on-device deployable. Group A.3
(LlmTransport refactor on the Flutter side) is the next task — it
needs:

- The deployed function URL (from step 5)
- The `anon public` key (from step 1)
- A device-token UUID generator on the client

Inject via `--dart-define`:

```bash
flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=eyJh...
```

CI gets the same flags via repository secrets.

## Rollback

If A.2 ships broken on prod:

```bash
supabase db reset --linked       # WARNING: destroys data
# Or selectively:
supabase migration list
supabase migration repair --status reverted <version>
supabase functions delete llm-proxy
```

Drift schema rollback for the Flutter side is handled by Drift's
own migration system (we're at schema v1 today; A.2's table
additions are server-side only — the client doesn't need a
schema bump until B.1).

## Out of scope

- Sync bucket setup (Group G.1)
- Play Billing webhook URL registration in Play Console (Group C.1)
- Play-API daily reconciliation cron (Group C — runs against Play
  API, needs Play credentials we haven't provisioned yet). Distinct
  from the `daily-reconciliation-cron` Edge Function in step 6c,
  which scans `deleted_accounts_log` for account-deletion purges.

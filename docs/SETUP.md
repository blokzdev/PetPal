# PetPal — Phase 7 setup guide

Everything you (the human) need to do on the dashboards / CLI / file
system, in order. Phase 7 is code-complete (DECISIONS rows 89 + 90
mark the last sub-piece closes); the only remaining gate is the
two-device on-device verification — this guide is the prerequisite
for that pass.

For the deeper Supabase A.2 deploy details, see
[`docs/phase7/A2-deployment.md`](./phase7/A2-deployment.md). This
guide consolidates that + Play Console + Flutter dart-defines + BYOK
dev + cost alerts in one place.

---

## 1. One-time prerequisites

Install on your dev machine:

```bash
brew install supabase/tap/supabase   # macOS; Windows: scoop install supabase
brew install deno                     # for `deno test` against the Edge Function
```

Accounts you'll need:

- **Supabase** account (free tier OK for dev; **Pro tier** ~$25/mo for
  prod project)
- **Anthropic** account with a paid API key (this funds the free-tier
  200-msg/mo allowance; expect ~$0.30 per active user/month at v1
  traffic estimates)
- **Google Play Console** account ($25 one-time registration; needed
  for Pro IAP testing)

---

## 2. Supabase — dev project (Group A.2 + G + H)

```bash
cd /path/to/PetPal
supabase login
```

In the Supabase Dashboard → **New project** → name `petpal-dev`,
region `us-east-1`, free tier. Save the database password.

From Settings → API, copy:

- `Project URL` (e.g. `https://abcdefgh.supabase.co`)
- `anon public` key
- `service_role secret` key (treat like a password)

### 2a. Push migrations + secrets + Edge Functions

```bash
supabase link --project-ref abcdefgh        # the slug from Project URL
supabase db push                             # applies 0001 + 0002 + 0003
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase functions deploy llm-proxy
supabase functions deploy account-delete
supabase functions deploy cancel-account-delete
supabase functions deploy daily-reconciliation-cron
```

Migrations applied (in order):

- `0001_phase7_init.sql` — entitlements, anonymous_counters, banned
  tokens/users, proxy_request_log, deleted_accounts_log, RLS, cron
  helpers (`reset_monthly_counters`, `purge_stale_anonymous_counters`,
  `purge_stale_proxy_logs`).
- `0002_sync_objects.sql` — sync_challenges + wiki_sync_objects +
  storage RLS policies for the `wiki` bucket.
- `0003_pending_deletion_user_id.sql` — operational `user_id` column
  on `deleted_accounts_log` so the daily-reconciliation cron can
  check `auth.users.last_sign_in_at` for the undo path (DECISIONS
  row 90).

`play-billing-webhook` is intentionally not deployed yet — see §6 +
§4's Webhook URL note.

### 2b. Storage bucket

In the Supabase Dashboard → **Storage** → **New bucket**:

- Name: `wiki` (must match exactly — the H.1.b RLS policies + the
  `SupabaseSyncBackend` are hard-coded to this name)
- Public: **off** (wiki blobs are E2EE ciphertext but the bucket is
  still per-user access-controlled via the policies in
  `0002_sync_objects.sql`)
- File size limit: leave default (50MB is plenty for ~2KB markdown
  ciphertext blobs)
- Allowed MIME types: leave unrestricted (blobs upload as
  `application/octet-stream`)

### 2c. Auth — magic-link redirect URL (REQUIRED)

In the Supabase Dashboard → **Authentication → URL Configuration →
Additional Redirect URLs**, add **exactly**:

```
petpal://login-callback
```

Without this, magic-link tap returns `400 invalid_request` and
sign-in silently fails. The exact-string match is enforced by
Supabase Auth; trailing slashes / capitalization variants are
rejected.

### 2d. SQL crons + daily-account-purge

In the Supabase Dashboard → **Database → Extensions**, enable
`pg_cron` **and** `pg_net` (the latter is required for §2d's
HTTP-invocation cron).

In the SQL Editor:

```sql
-- Internal SQL crons (counter reset + storage hygiene)
select cron.schedule('reset-monthly-counters', '0 2 * * *',
  $$ select public.reset_monthly_counters() $$);
select cron.schedule('purge-stale-anonymous-counters', '0 3 * * *',
  $$ select public.purge_stale_anonymous_counters() $$);
select cron.schedule('purge-stale-proxy-logs', '0 4 * * *',
  $$ select public.purge_stale_proxy_logs() $$);

-- Daily account-deletion purge (calls the Edge Function via HTTP).
-- Replace <SERVICE_ROLE_JWT> with the service_role key from
-- Settings → API. The Edge Function's verify_jwt=true requires a
-- service-role JWT in the Authorization header.
alter database postgres
  set "app.daily_cron_jwt" = '<SERVICE_ROLE_JWT>';

select cron.schedule('daily-account-purge', '0 5 * * *',
  $$
    select net.http_post(
      url := 'https://abcdefgh.supabase.co/functions/v1/daily-reconciliation-cron',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || current_setting('app.daily_cron_jwt'),
        'Content-Type', 'application/json'
      ),
      body := '{}'::jsonb
    );
  $$);
```

Verify cron registration:

```sql
select * from cron.job;
```

Expected: 4 rows (`reset-monthly-counters`,
`purge-stale-anonymous-counters`, `purge-stale-proxy-logs`,
`daily-account-purge`).

### 2e. Smoke-test the deploys

```bash
# llm-proxy — should return unauthorized 401
curl -X POST "https://abcdefgh.supabase.co/functions/v1/llm-proxy" \
  -H "content-type: application/json" -d '{}' | jq

# account-delete + cancel-account-delete — same shape
curl -X POST "https://abcdefgh.supabase.co/functions/v1/account-delete" \
  -H "content-type: application/json" -d '{}' | jq

# daily-reconciliation-cron — manual fire with service-role JWT;
# expect {scanned:0, undone:0, purged:0, errors:[]} on a clean dev project
curl -X POST "https://abcdefgh.supabase.co/functions/v1/daily-reconciliation-cron" \
  -H "Authorization: Bearer <SERVICE_ROLE_JWT>" \
  -H "Content-Type: application/json" -d '{}' | jq
```

For prod: repeat 2a–2e against a separate `petpal-prod` project (Pro
tier, $25/mo).

---

## 3. Flutter — dart-defines (Group A.3)

The Flutter app reads Supabase coordinates at compile time via
`--dart-define`. **Don't commit real values.**

Create `dart-defines.json` at the repo root (gitignored — add
`dart-defines.json` to `.gitignore`):

```json
{
  "SUPABASE_URL": "https://abcdefgh.supabase.co",
  "SUPABASE_ANON_KEY": "eyJhbGciOi..."
}
```

Run / build with:

```bash
flutter run --dart-define-from-file=dart-defines.json
flutter build apk --release --split-per-abi --dart-define-from-file=dart-defines.json
```

For CI, set the same names as repository secrets and pass them
through.

> **Behavior without dart-defines.** The app reads these via
> `String.fromEnvironment(...)` at construction time. Without them,
> `supabaseRuntimeConfigProvider` returns null, which has cascading
> effects: sign-in is unavailable (Settings → "Sign in" tile is
> hidden), sync card stays in `signedOut` state, and the chat
> surface renders the `_ChatUnavailableBanner` ("Chat needs a
> connection to Claude. Add your Anthropic key in Settings to start
> chatting"). The user must then manually enable BYOK in Settings →
> Plan card → BYOK toggle to chat at all. **Two-device verification
> requires the dart-defines pointing at a real Supabase project** —
> sign-in, sync, account-delete, paywall hard-wall, and the proxy
> path are all gated on it.

---

## 4. Play Console — product registration

In Play Console → **Monetize → Products**, register exactly these IDs
(they're locked in `lib/platform/billing/product_ids.dart`):

### Subscriptions

| Product ID | Type | Base plan | Price |
|---|---|---|---|
| `pro_monthly` | Subscription | `monthly`, monthly billing | **$7.99/mo** |
| `pro_annual` | Subscription | `annual`, yearly billing | **$59.00/yr** |

Both subs use the **same subscription group** ("PetPal Pro") so users
can switch between monthly/annual without orphan grants.

### In-app products

| Product ID | Type | Price | Notes |
|---|---|---|---|
| `photo_credits_50` | **Consumable** | **$2.99** | 50 vision analyses; rolls over indefinitely |
| `care_pack_reactive_dog` | **Non-consumable** | **$2.99** | Unlocks reactive-dog skill |
| `expert_pack_senior_dog` | **Non-consumable** | $14.99–$39.99 | **Reserved but unused in v1** — register in Play Console anyway so the ID is claimed; the Flutter code references it but no UI surfaces buying it. Deferred to v1.x. |

### Tester accounts

- Play Console → **Setup → License testing** → add your Gmail + any
  teammates as license testers.
- Play Console → **Testing → Internal testing** → create a track, add
  the same Gmail accounts as testers.
- **All IAP testing happens via this internal track**. Per Stage 1
  risk-mitigation lock: never test with real cards.

### Webhook URL

**Skip for now.** The `play-billing-verify` Edge Function (server-side
receipt verification) lands in a later Phase 7 commit. Once it ships,
you'll come back to Play Console → Monetize setup → **Real-time
developer notifications** and paste in:

```
https://abcdefgh.supabase.co/functions/v1/play-billing-webhook
```

Until then, IAP works in optimistic-emit mode (the Flutter client
trusts the Play sandbox response and updates entitlement immediately;
backend reconciliation is a no-op).

---

## 5. BYOK developer testing

For local dev without burning your real Anthropic budget on the proxy
path, you can run as a BYOK user. Onboarding is no longer the entry
point for this — F.1 (DECISIONS row 74) replaced the API-key prompt
with a 2-page welcome → privacy flow, and BYOK now lives as an
opt-in toggle in Settings.

1. Onboard the app fresh (welcome page → privacy disclosure → done).
   You'll land on the home screen signed-out.
2. **Settings → Plan card → BYOK toggle**. Flip it ON. A modal sheet
   prompts for an Anthropic key; the validator runs a format regex
   (`sk-ant-[A-Za-z0-9_-]{40,}`) + a live ping to
   `api.anthropic.com/v1/models` before accepting.
3. App now routes through `DirectTransport` straight to
   `api.anthropic.com`. No Supabase round-trip; no quota; no Pro
   features (sync, multi-pet, vision, synthesis are all Pro-gated —
   BYOK only lifts the cost-driven text + vision quotas).

**Where to get the dev key:** Anthropic Console → API Keys → Create
new key. Tag it `petpal-dev-byok` so it's distinguishable from the
proxy master key set in §2a's `supabase secrets`.

**Existing-key auto-promote.** If you already had a key stored from
a pre-F.1 build (`flutter_secure_storage` `api_key` slot),
`EntitlementNotifier.build()` silently promotes you to BYOK on first
launch — no re-entry needed. Same migration runs for the
`welcome_completed` flag so you don't re-hit onboarding.

---

## 6. What shipped since this doc was first written

Phase 7 was incomplete when this guide was first authored at commit
`8a2e70e`. The original §6 listed six "Stage 2 catch-up" rows
deferred to later commits. Five have shipped:

| Feature | Shipped in | Reference |
|---|---|---|
| Cloud sync provider (Supabase Storage) | Group G.1 + G.2 | DECISIONS rows 83 + 84 |
| E2EE passphrase derivation (Argon2id) | Group G.2 | DECISIONS row 71 |
| Magic-link auth (Supabase) | Group H.1.a–c | DECISIONS row 70 (redirect URL config moved to §2c above) |
| Multi-pet UI | Group E.2 | DECISIONS row 36 |
| Account deletion + 30-day undo + hard-purge cron | Group H.1.d + H.1.d-follow-ups | DECISIONS rows 77, 87, 90 (`account-delete`, `cancel-account-delete`, `daily-reconciliation-cron` Edge Functions in §2a above) |

**Still deferred:**

| Feature | Blocked by | Where you'll set it up |
|---|---|---|
| Server-side IAP receipt verification | `play-billing-verify` Edge Function (Phase 8 prerequisite) | Play Console RTDN webhook URL — see §4 "Webhook URL" |

DECISIONS rows 89 + 90 close H.2.b (accessibility audit) +
H.1.d-follow-ups respectively. The only Phase-7 gate that remains
is the two-device on-device verification — which this guide is the
prerequisite for.

---

## 7. Cost alerts (do this once both dev + prod are deployed)

In the **Anthropic Console**:

- Set a monthly spend cap. Start conservative — $50/mo for
  `petpal-dev`, $500/mo for `petpal-prod`. Tune up once you have real
  usage.

In the **Supabase Dashboard** (per project):

- Settings → Usage → set up email alerts at 80% of the Pro tier's
  bandwidth + storage limits.

For per-user spend visibility (manual until Group H ships proper
alerting), run nightly in Supabase SQL Editor:

```sql
select user_id,
       sum(input_tokens * 3.0 / 1e6 + output_tokens * 15.0 / 1e6) as usd_estimate
from proxy_request_log
where request_at > now() - interval '24 hours'
group by user_id
order by usd_estimate desc
limit 20;
```

(Sonnet pricing: $3/MTok input, $15/MTok output. Adjust if you
switch the default model.)

---

## 8. Quick sanity checklist before two-device verification

**Supabase project (per §2):**

- [ ] `petpal-dev` (or `petpal-prod`) project provisioned + linked
- [ ] All three migrations applied (`supabase migration list` shows
      0001 + 0002 + 0003 as remote-committed)
- [ ] `ANTHROPIC_API_KEY` secret set (`supabase secrets list`
      includes it)
- [ ] **All four** Edge Functions deployed: `llm-proxy`,
      `account-delete`, `cancel-account-delete`,
      `daily-reconciliation-cron`
- [ ] `wiki` Storage bucket created (private, default size limit)
- [ ] **Magic-link redirect URL** `petpal://login-callback` added
      to Auth → URL Configuration → Additional Redirect URLs
- [ ] `pg_cron` + `pg_net` extensions enabled
- [ ] **All four** crons scheduled: `reset-monthly-counters`,
      `purge-stale-anonymous-counters`, `purge-stale-proxy-logs`,
      `daily-account-purge` — confirm via `select * from cron.job`
- [ ] `app.daily_cron_jwt` Postgres setting holds the service-role
      JWT
- [ ] Manual smoke-test of `daily-reconciliation-cron` returns
      `{scanned:0, undone:0, purged:0, errors:[]}` against an
      empty project

**Flutter (per §3):**

- [ ] `dart-defines.json` exists locally with dev project URL +
      anon key
- [ ] `dart-defines.json` is gitignored (verify with
      `git check-ignore dart-defines.json`)

**Play Console (per §4):**

- [ ] 5 product IDs registered (`pro_monthly`, `pro_annual`,
      `photo_credits_50`, `care_pack_reactive_dog`,
      `expert_pack_senior_dog`)
- [ ] Both subs in the same "PetPal Pro" subscription group
- [ ] Internal-testing track active
- [ ] Your Google account (and your test partner's, for
      device B) added as license tester + internal-track tester

**Test devices (two needed for full verification):**

- [ ] Device A: signed into Google account that's a registered
      tester; APK installed via internal-track download
- [ ] Device B: same — different Google account is fine, but the
      tester pool must include it
- [ ] Sideload-installed APKs **will not** receive IAP responses
      from Play; install via the internal track only

If any of these is missing, the corresponding ODV step will fail
with cryptic errors (e.g. magic-link → 400 invalid_request, IAP →
silent purchase failure, account-delete → audit row never hard-
purged).

---

That's everything actionable for two-device on-device verification.
§5 (BYOK dev testing) + §7 (cost alerts) are deferrable. §1 + §2 +
§3 + §4 are the load-bearing prerequisites.

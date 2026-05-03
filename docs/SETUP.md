# PetPal — Phase 7 setup guide

Everything you (the human) need to do on the dashboards / CLI / file
system, in order. Stop at "Stage 2 catch-up" — anything past there
waits on later phase commits.

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

## 2. Supabase — dev project (Group A.2)

Follow the existing checklist:

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

Then locally:

```bash
supabase link --project-ref abcdefgh        # the slug from Project URL
supabase db push                             # applies 0001_phase7_init.sql + 0002_sync_objects.sql
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase functions deploy llm-proxy
```

Then in the Supabase Dashboard → **Storage** → **New bucket**:

- Name: `wiki` (must match exactly — the H.1.b RLS policies + the
  `SupabaseSyncBackend` are hard-coded to this name)
- Public: **off** (wiki blobs are E2EE ciphertext but the bucket is
  still per-user access-controlled via the policies in
  `0002_sync_objects.sql`)
- File size limit: leave default (50MB is plenty for ~2KB markdown
  ciphertext blobs)
- Allowed MIME types: leave unrestricted (blobs upload as
  `application/octet-stream`)

In the Supabase SQL Editor (Dashboard → SQL Editor), enable `pg_cron`
and run:

```sql
select cron.schedule('reset-monthly-counters', '0 2 * * *',
  $$ select public.reset_monthly_counters() $$);
select cron.schedule('purge-stale-anonymous-counters', '0 3 * * *',
  $$ select public.purge_stale_anonymous_counters() $$);
select cron.schedule('purge-stale-proxy-logs', '0 4 * * *',
  $$ select public.purge_stale_proxy_logs() $$);
```

Verify with a curl ping (should return `{"error":{"code":"unauthorized"...}}`):

```bash
curl -X POST "https://abcdefgh.supabase.co/functions/v1/llm-proxy" \
  -H "content-type: application/json" -d '{}' | jq
```

For prod: repeat the whole section against a separate `petpal-prod`
project (Pro tier).

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

> **Note:** Phase 7 code reads these via `String.fromEnvironment(...)`
> at the seams that need them (currently only `ProxyTransport` once
> the provider wiring lands for it — Stage 2 work). Until then, you
> can run without dart-defines and the app stays on the BYOK path
> with the user's manually entered Anthropic key.

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
path, you can run as a BYOK user:

1. Onboard the app fresh.
2. When the API-key entry screen lands, paste a developer-tier
   Anthropic key (a separate key from the master one you used in
   step 2's `supabase secrets set` — keep them separate so you can
   revoke independently).
3. App now routes through `DirectTransport` straight to
   `api.anthropic.com`. No Supabase round-trip; no quota; no Pro
   features (sync, multi-pet, vision, synthesis are all Pro-gated).

**Where to get the dev key:** Anthropic Console → API Keys → Create
new key. Tag it `petpal-dev-byok` so it's distinguishable from the
proxy master key.

---

## 6. Stage 2 catch-up — what's not yet ready for setup

These need code that hasn't shipped yet. Don't try to configure them
now:

| Feature | Blocked by | Where you'll set it up |
|---|---|---|
| Server-side IAP receipt verification | `play-billing-verify` Edge Function (later C-group commit) | Play Console RTDN webhook URL |
| Cloud sync provider | Group G.1 architectural decision (Supabase Storage vs other) | Likely same `supabase secrets` + a new bucket |
| E2EE passphrase derivation | Group G.2 implementation | In-app onboarding flow (no dashboard config) |
| Auth (Supabase magic-link email) | Group H.1.a (this commit) | Supabase Dashboard → Authentication → Email templates (already partly seeded by `supabase/templates/magic_link.html`) **AND** Authentication → URL Configuration → "Additional Redirect URLs" must include `petpal://login-callback` exactly — without this, magic-link tap returns 400 invalid_request |
| Multi-pet UI | Group E.2 | No dashboard config; pure Flutter |
| Account deletion + data export | Group H.1 | Settings screen + Supabase function (will need an `account-delete` Edge Function) |

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

## 8. Quick sanity checklist before each on-device test session

- [ ] `petpal-dev` project deployed + cron jobs scheduled
- [ ] `ANTHROPIC_API_KEY` secret set on Supabase
- [ ] `dart-defines.json` exists locally with dev project URL + anon
      key
- [ ] Play Console: 5 product IDs registered, internal-testing track
      active, your Google account added as tester
- [ ] Test device: signed into Google account that's a registered
      tester
- [ ] APK installed via internal-track download (NOT a sideload —
      IAP only flows through Play-installed builds)

If any of these is missing, IAP purchases will silently fail or get
rejected by Play with cryptic errors.

---

That's everything actionable today. Most of it (sections 4 + 5 + 7)
you can defer until you actually want to test IAPs / cost-monitoring
on-device. Section 2 + 3 are the only ones blocking your next
dev-iteration loop.

# Phase 7 wrap

Code-complete-with-deferrals close. The Pro tier monetization
architecture, multi-pet UI, magic-link sign-in, E2EE sync,
account-delete cascade, and crash-analytics scaffold all shipped.
Three explicit deferrals route forward to Phase 8 prerequisites
or v1.0.x patch commits. Two-device on-device verification is
required before Phase 7 can be marked formally complete; it's
fundamentally a human-action gate (cannot be codeable).

## What shipped

**Backend foundation** (Group A).
- DECISIONS row 82 — Supabase project spec, magic-link auth, proxy
  latency budget, observability + abuse-detection signals, schema
  for `entitlements` + `anonymous_counters` + `proxy_request_log`
  + `deleted_accounts_log`.
- `supabase/functions/llm-proxy/` Edge Function — atomic counter
  increment + cache_control passthrough to Anthropic. Deno test
  pins 11 invariants.
- `LlmTransport` two-path refactor — `DirectTransport` (BYOK
  lane) + `ProxyTransport` (signed-in / anonymous via proxy).

**Tier service & entitlements** (Group B).
- Drift schema v2 — `entitlements` table mirrors the canonical
  Supabase shape per row 78. Domain `Entitlement` value class +
  `EntitlementState` enum with state-derived flag derivations.

**Play Billing integration** (Group C).
- Subscription IAPs ($7.99/mo + $59/yr), photo credit pack
  ($2.99 = 50 vision), one care pack starter (Reactive Dog,
  $2.99). Expert pack deferred to v1.x per DECISIONS row 81.

**Quota enforcement** (Group D).
- Five gates: chat msg, vision, reminder, pet count, sync. BYOK
  lifts cost-driven gates only (text + vision); reminder + pet +
  sync gates stay Pro-only per row 36.

**Paywall + Pro UX** (Group E).
- Hard-wall + BYOK escape on chat-quota hit; inline error +
  Compare-plans link on pet-cap; multi-pet UI (pet switcher,
  cross-pet Journal "All pets" mode, family-wide reminders
  sectioned by pet).

**BYOK path** (Group F).
- Onboarding rewrite (no key required, welcome → privacy → done,
  proxy-default framing per VOICE.md §6 example 15). Settings
  BYOK toggle with format check + live ping validation.

**Sync** (Group G + H.1.b).
- Argon2id passphrase-derived AES-256-GCM E2EE wiki sync. Per-
  user salt (DECISIONS row 84), wire-format `[1B version][12B
  IV][ct][16B GCM mac]`, AAD = pet_id + path + write_ts.
- `SupabaseSyncBackend` REST-direct (Storage + PostgREST) impl
  shipped in H.1.b. Conflict resolver with 5s skew tolerance +
  structural-divergence detection + cross-device-deterministic
  loser selection.
- Migration `0002_sync_objects.sql` — `sync_challenges` +
  `wiki_sync_objects` tables, RLS policies, Storage bucket
  policies for the `wiki` bucket.

**Account, Settings, Pre-Launch** (Group H).
- H.1.a — `supabase_flutter` adoption + auth scaffold
  (`AppAuthSession`, `AuthGateway` abstraction, `Supabase.
  initialize` wired with `--dart-define` guard).
- H.1.b — production `SupabaseSyncBackend` + `cloudSync
  AdapterProvider` rewiring against the entitlement-gated
  E2EE adapter.
- H.1.c.1 — magic-link sign-in screen + Settings sign-in/out
  tiles + `_SyncCard` `signedOut` flip + VOICE.md §6 examples
  16–20 locked (sign-in tile, sign-out confirmation, sign-in
  flow, sync passphrase gate, account-delete cascade).
- H.1.c.2 — auth-aware `EntitlementNotifier` (signed-in users
  fetch userId-keyed row from Supabase per row 78; cache
  fallback on transient failure) + `ProxyTransport` wiring +
  `_ChatUnavailableBanner` conditional flip with both-paths
  CTAs.
- H.1.d — account delete cascade per DECISIONS row 77 Option e:
  single-screen disclosure + typed-confirmation gate + inline
  export-first affordance + `account-delete` Edge Function
  inserting `deleted_accounts_log` row with retention window.
- H.1.e — privacy copy refresh (onboarding "Your pet's journal"
  + About "Privacy policy" subtitle) for the post-H.1 reality
  (chat + sync both leave the device, both honest).
- H.2.a — opt-in crash analytics scaffold + `sk-ant-`
  redaction layer + Settings → Diagnostics toggle. `Noop
  CrashAnalytics` is the v1 production default (nothing
  transmits until a concrete provider lands in Phase 8+).

## Deferred — three explicit gates before Phase 7 → Phase 8

**1. H.2.b — comprehensive accessibility audit**
(DECISIONS row 88). Per-screen audit: contrast, screen-reader
labels, text-scaling resilience, touch-target sizes. Must land
before `flutter build appbundle --release` in Phase 8 task 8.6
— Play Store's pre-launch accessibility scanner gates the AAB.

**2. H.1.d sub-pieces** (DECISIONS row 87).
  - Daily cron + hard-purge of wiki blobs / entitlement /
    counters / proxy_request_log / auth.users at the end of the
    30-day window. The `deleted_accounts_log_retention_idx` is
    already in place — the cron is mechanical.
  - Post-sign-in undo prompt within the retention window.
  - Local Drift + wiki-files wipe at delete-tap.

  The cron is load-bearing for Phase 8's data-safety form;
  local wipe + undo prompt can ride v1.0.x patch updates.

**3. Two-device on-device verification** (CLAUDE.md §14 lock —
code cannot substitute). The full verification checklist lives
in ROADMAP.md under H.3:
  - Sign in via magic-link on device A → subscribe with Play
    tester account → install on device B → sign in with same
    email → enter passphrase → confirm wiki syncs end-to-end
    with no plaintext on backend (proxy log inspection).
  - Add a second pet; pet switcher works across devices.
  - Trigger sync conflict via offline writes on both devices
    + confirm `.conflict.md` lands deterministically with
    matching loser content on both ends.
  - Chat 200+ messages on a fresh free tester → confirm hard-
    wall fires with both Upgrade + BYOK CTAs.
  - Flip BYOK on signed-in user → confirm calls bypass the
    backend (verify via proxy logs).
  - Buy photo credit pack → confirm balance rolls over to
    next month.
  - Buy care pack → confirm Pro-gated skill loads.
  - Trigger account deletion → verify export prompt + sync
    purge confirmation + 30-day soft-delete window + (after
    cron lands) hard-purge on the recovery-window expiration
    date.

## Phase 8 prerequisites checklist

Before Phase 8 task 8.1 begins, confirm:

- [ ] H.2.b accessibility audit committed (DECISIONS row 88).
- [ ] Daily-cron Edge Function + cron registration on `petpal-
  prod` (DECISIONS row 87 piece 1).
- [ ] Two-device on-device verification run end-to-end on a
  Play tester account against `petpal-prod`.

The cron + accessibility audit are codeable in any session.
The on-device verification is the human gate.

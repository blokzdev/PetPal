-- Phase 7 Group A.2 — initial backend schema.
--
-- Source-of-truth: DECISIONS row 82.
-- Cross-references:
--   row 36 (monetization model: tiers, quotas, BYOK)
--   row 69 (single-provider Supabase lock)
--   row 70 (auth model: magic-link Supabase Auth)
--   row 75 (hybrid quota: server-canonical lives here)
--   row 76 (Anthropic proxy build-now)
--   row 77 (account deletion semantics)
--   row 78 (subscription state via webhook + reconciliation)

-- ──────────────────────────────────────────────────────────────────────
-- entitlements: one row per signed-in user.
-- Canonical state per row 78 — Play webhooks refresh it; daily
-- reconciliation cron catches missed webhooks.
-- ──────────────────────────────────────────────────────────────────────
create table public.entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  state text not null default 'free'
    check (state in ('free', 'pro_monthly', 'pro_annual', 'byok')),
  renewal_date timestamptz,
  grace_until timestamptz,
  photo_credits_balance int not null default 0
    check (photo_credits_balance >= 0),
  monthly_text_count int not null default 0
    check (monthly_text_count >= 0),
  monthly_vision_count int not null default 0
    check (monthly_vision_count >= 0),
  counter_period_start timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index entitlements_renewal_date_idx on public.entitlements (renewal_date)
  where renewal_date is not null;
create index entitlements_state_idx on public.entitlements (state);

-- updated_at trigger
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger entitlements_touch
  before update on public.entitlements
  for each row execute function public.touch_updated_at();

-- ──────────────────────────────────────────────────────────────────────
-- anonymous_counters: signed-out free users.
-- device_token is a UUID v4 generated client-side at install and
-- stored in flutter_secure_storage. Anonymous users have text-chat
-- only; no vision, no Pro features (those require sign-in).
-- ──────────────────────────────────────────────────────────────────────
create table public.anonymous_counters (
  device_token text primary key,
  monthly_text_count int not null default 0
    check (monthly_text_count >= 0),
  counter_period_start timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index anonymous_counters_last_seen_idx
  on public.anonymous_counters (last_seen_at);

-- ──────────────────────────────────────────────────────────────────────
-- ban tables — manual ops response to confirmed abusers.
-- v1 simple: insert a row, the rate limiter rejects.
-- ──────────────────────────────────────────────────────────────────────
create table public.banned_device_tokens (
  device_token text primary key,
  reason text,
  banned_at timestamptz not null default now()
);

create table public.banned_user_ids (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reason text,
  banned_at timestamptz not null default now()
);

-- ──────────────────────────────────────────────────────────────────────
-- proxy_request_log: per-request metadata for cost dashboards + abuse
-- detection. NEVER stores chat content — only tokens, model, timing.
-- Retention: 90 days (cleanup cron); aggregate dashboards keep totals.
-- ──────────────────────────────────────────────────────────────────────
create table public.proxy_request_log (
  id bigserial primary key,
  user_id uuid references auth.users(id) on delete set null,
  device_token text,
  request_at timestamptz not null default now(),
  model text,
  input_tokens int,
  output_tokens int,
  cache_read_tokens int,
  cache_creation_tokens int,
  status_code int,
  error_code text,
  latency_ms int,
  -- cache_control passthrough invariant: this column is set true only
  -- when the inbound request body contained a `cache_control` block.
  -- If we ever see this stuck at false in prod for cached system-prompt
  -- traffic, the proxy lost the passthrough — catastrophic cost regression.
  inbound_had_cache_control boolean not null default false,
  check ((user_id is null) <> (device_token is null))
);

create index proxy_request_log_user_id_request_at_idx
  on public.proxy_request_log (user_id, request_at desc)
  where user_id is not null;
create index proxy_request_log_device_token_request_at_idx
  on public.proxy_request_log (device_token, request_at desc)
  where device_token is not null;
create index proxy_request_log_request_at_idx
  on public.proxy_request_log (request_at);

-- ──────────────────────────────────────────────────────────────────────
-- deleted_accounts_log: GDPR/CCPA audit trail per row 77.
-- No user content; just hash + dates so we can prove compliance during
-- a regulatory audit without retaining the user's identity.
-- ──────────────────────────────────────────────────────────────────────
create table public.deleted_accounts_log (
  id bigserial primary key,
  user_id_hash text not null,
  delete_requested_at timestamptz not null default now(),
  retention_window_ends_at timestamptz not null,
  hard_purged_at timestamptz
);

create index deleted_accounts_log_retention_idx
  on public.deleted_accounts_log (retention_window_ends_at)
  where hard_purged_at is null;

-- ──────────────────────────────────────────────────────────────────────
-- check_rate_limit(actor_id, actor_type) — 100 msg/hour floor.
-- Also rejects banned tokens/users. Returns jsonb {allowed, reason}.
-- ──────────────────────────────────────────────────────────────────────
create or replace function public.check_rate_limit(
  p_actor_id text,
  p_actor_type text
) returns jsonb
language plpgsql security definer
as $$
declare
  hourly_count int;
  is_banned boolean;
begin
  if p_actor_type = 'user' then
    select exists(select 1 from public.banned_user_ids where user_id = p_actor_id::uuid)
      into is_banned;
  elsif p_actor_type = 'anonymous' then
    select exists(select 1 from public.banned_device_tokens where device_token = p_actor_id)
      into is_banned;
  else
    return jsonb_build_object('allowed', false, 'reason', 'unknown_actor_type');
  end if;

  if is_banned then
    return jsonb_build_object('allowed', false, 'reason', 'banned');
  end if;

  if p_actor_type = 'user' then
    select count(*) into hourly_count
      from public.proxy_request_log
      where user_id = p_actor_id::uuid
        and request_at > now() - interval '1 hour';
  else
    select count(*) into hourly_count
      from public.proxy_request_log
      where device_token = p_actor_id
        and request_at > now() - interval '1 hour';
  end if;

  if hourly_count >= 100 then
    return jsonb_build_object('allowed', false, 'reason', 'rate_limited');
  end if;

  return jsonb_build_object('allowed', true);
end $$;

-- ──────────────────────────────────────────────────────────────────────
-- increment_text_counter(actor_id, actor_type, free_cap) — atomic with
-- row-level lock per row 75 (concurrent requests at the 199/200
-- boundary serialize correctly). Returns jsonb {allowed, new_count, cap}.
--
-- Caller passes free_cap=200 for anonymous + free signed-in; null for
-- Pro / BYOK (unmetered text). The function checks cap before
-- incrementing; if the increment would exceed cap, returns allowed=false
-- without committing the increment (so retries don't double-count).
-- ──────────────────────────────────────────────────────────────────────
create or replace function public.increment_text_counter(
  p_actor_id text,
  p_actor_type text,
  p_free_cap int
) returns jsonb
language plpgsql security definer
as $$
declare
  current_count int;
  current_period_start timestamptz;
  new_count int;
begin
  if p_actor_type = 'user' then
    -- Row-level lock on the entitlements row for this user.
    select monthly_text_count, counter_period_start
      into current_count, current_period_start
      from public.entitlements
      where user_id = p_actor_id::uuid
      for update;

    if not found then
      -- Auto-provision a free entitlement row on first proxy hit.
      insert into public.entitlements (user_id, state)
        values (p_actor_id::uuid, 'free')
        on conflict (user_id) do nothing;
      select monthly_text_count, counter_period_start
        into current_count, current_period_start
        from public.entitlements
        where user_id = p_actor_id::uuid
        for update;
    end if;

    if p_free_cap is not null and current_count >= p_free_cap then
      return jsonb_build_object('allowed', false, 'cap', p_free_cap, 'count', current_count);
    end if;

    new_count := current_count + 1;
    update public.entitlements
      set monthly_text_count = new_count
      where user_id = p_actor_id::uuid;

  elsif p_actor_type = 'anonymous' then
    insert into public.anonymous_counters (device_token, monthly_text_count, last_seen_at)
      values (p_actor_id, 0, now())
      on conflict (device_token) do update
        set last_seen_at = excluded.last_seen_at;

    select monthly_text_count, counter_period_start
      into current_count, current_period_start
      from public.anonymous_counters
      where device_token = p_actor_id
      for update;

    if p_free_cap is not null and current_count >= p_free_cap then
      return jsonb_build_object('allowed', false, 'cap', p_free_cap, 'count', current_count);
    end if;

    new_count := current_count + 1;
    update public.anonymous_counters
      set monthly_text_count = new_count
      where device_token = p_actor_id;

  else
    return jsonb_build_object('allowed', false, 'reason', 'unknown_actor_type');
  end if;

  return jsonb_build_object('allowed', true, 'count', new_count);
end $$;

-- ──────────────────────────────────────────────────────────────────────
-- reset_monthly_counters() — cron-callable, idempotent.
-- Resets any row whose counter_period_start + 1 month has passed.
-- Pro counters reset on entitlement-renewal date (subscription
-- anniversary); free anonymous counters reset on calendar-month
-- boundary. Both flow through this function — caller cron can run
-- nightly.
-- ──────────────────────────────────────────────────────────────────────
create or replace function public.reset_monthly_counters()
returns int
language plpgsql security definer
as $$
declare
  rows_affected int := 0;
  ent_rows int;
  anon_rows int;
begin
  update public.entitlements
    set monthly_text_count = 0,
        monthly_vision_count = 0,
        counter_period_start = now()
    where counter_period_start + interval '1 month' < now();
  get diagnostics ent_rows = row_count;

  update public.anonymous_counters
    set monthly_text_count = 0,
        counter_period_start = now()
    where counter_period_start + interval '1 month' < now();
  get diagnostics anon_rows = row_count;

  rows_affected := ent_rows + anon_rows;
  return rows_affected;
end $$;

-- ──────────────────────────────────────────────────────────────────────
-- purge_stale_anonymous_counters() — storage hygiene per row 82.
-- Removes anonymous_counters rows untouched for 90 days.
-- ──────────────────────────────────────────────────────────────────────
create or replace function public.purge_stale_anonymous_counters()
returns int
language plpgsql security definer
as $$
declare
  rows_affected int;
begin
  delete from public.anonymous_counters
    where last_seen_at < now() - interval '90 days';
  get diagnostics rows_affected = row_count;
  return rows_affected;
end $$;

-- ──────────────────────────────────────────────────────────────────────
-- purge_stale_proxy_logs() — storage hygiene; 90-day retention.
-- ──────────────────────────────────────────────────────────────────────
create or replace function public.purge_stale_proxy_logs()
returns int
language plpgsql security definer
as $$
declare
  rows_affected int;
begin
  delete from public.proxy_request_log
    where request_at < now() - interval '90 days';
  get diagnostics rows_affected = row_count;
  return rows_affected;
end $$;

-- ──────────────────────────────────────────────────────────────────────
-- Row-Level Security.
-- Edge Functions use the service role key (bypasses RLS by design).
-- Direct user reads against entitlements use the user's JWT — they can
-- read their own row only. Everything else is service-role-only.
-- ──────────────────────────────────────────────────────────────────────
alter table public.entitlements enable row level security;
alter table public.anonymous_counters enable row level security;
alter table public.banned_device_tokens enable row level security;
alter table public.banned_user_ids enable row level security;
alter table public.proxy_request_log enable row level security;
alter table public.deleted_accounts_log enable row level security;

create policy "users read own entitlement" on public.entitlements
  for select using (auth.uid() = user_id);

-- No INSERT/UPDATE/DELETE policies — service role only writes.
-- Other tables have no policies — service role only.

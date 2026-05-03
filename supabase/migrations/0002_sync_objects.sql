-- Phase 7 Group H.1.b — sync object metadata + per-user passphrase challenge.
--
-- Source-of-truth: DECISIONS rows 70 + 71 + 83 + 84.
-- Cross-references:
--   row 36 (sync is Pro-only — RLS lets any authed user read; the Pro
--          gate is client-side via EntitlementGatedSyncAdapter)
--   row 70 (auth required for sync)
--   row 71 (E2EE Argon2 lock)
--   row 83 (object key shape, sidecar metadata table)
--   row 84 (per-user salt — single sync_challenges row per user)
--
-- This migration depends on `public.touch_updated_at()` from 0001.

-- ──────────────────────────────────────────────────────────────────────
-- sync_challenges: per-user passphrase challenge.
-- One row per user. Holds the per-user salt + the encrypted challenge
-- constant (per `lib/data/sync/sync_session.dart` SyncChallenge
-- serialization). The actual passphrase NEVER leaves the device — only
-- the salt + the ciphertext-of-a-known-constant uploads here.
-- ──────────────────────────────────────────────────────────────────────
create table public.sync_challenges (
  user_id uuid primary key references auth.users(id) on delete cascade,
  salt_b64 text not null,
  ciphertext_b64 text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger sync_challenges_touch
  before update on public.sync_challenges
  for each row execute function public.touch_updated_at();

alter table public.sync_challenges enable row level security;

-- Each user only sees / writes their own challenge row.
create policy "sync_challenges_self_select"
  on public.sync_challenges
  for select using (auth.uid() = user_id);

create policy "sync_challenges_self_insert"
  on public.sync_challenges
  for insert with check (auth.uid() = user_id);

create policy "sync_challenges_self_update"
  on public.sync_challenges
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ──────────────────────────────────────────────────────────────────────
-- wiki_sync_objects: per-object sidecar metadata for delta queries.
--
-- Per DECISIONS row 83: body_hash is the SHA-256 hex of the *plaintext*
-- (not ciphertext — ciphertext changes every encrypt due to fresh IV).
-- Server cannot verify this matches the blob; it's a trust-the-client
-- field used for client-side LWW comparison + dedup.
--
-- write_ts is stored as bigint millis-since-epoch (matches the Dart
-- DateTime.toUtc().millisecondsSinceEpoch wire format used by
-- RemoteObjectMeta.toJson()).
--
-- Pull queries this table for `updated_at > since` (server-side row
-- mtime) to find changed paths without downloading every blob.
-- ──────────────────────────────────────────────────────────────────────
create table public.wiki_sync_objects (
  user_id uuid not null references auth.users(id) on delete cascade,
  pet_id int not null,
  relative_path text not null,
  write_ts bigint not null,
  body_hash text not null,
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, pet_id, relative_path)
);

-- Index for the listSince query path (most common read).
create index wiki_sync_objects_pet_updated_idx
  on public.wiki_sync_objects (user_id, pet_id, updated_at);

create trigger wiki_sync_objects_touch
  before update on public.wiki_sync_objects
  for each row execute function public.touch_updated_at();

alter table public.wiki_sync_objects enable row level security;

create policy "wiki_sync_objects_self_select"
  on public.wiki_sync_objects
  for select using (auth.uid() = user_id);

create policy "wiki_sync_objects_self_insert"
  on public.wiki_sync_objects
  for insert with check (auth.uid() = user_id);

create policy "wiki_sync_objects_self_update"
  on public.wiki_sync_objects
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ──────────────────────────────────────────────────────────────────────
-- Storage bucket: 'wiki' for E2EE wiki blobs.
--
-- Per DECISIONS row 83: object key shape is <user_id>/<pet_id>/<path>.enc
-- so (storage.foldername(name))[1] = <user_id> as text.
--
-- The bucket itself MUST also be created via Supabase Dashboard →
-- Storage → New bucket → name "wiki" (private, not public). This script
-- declares only the row-level policies; bucket creation is a one-time
-- dashboard step documented in docs/SETUP.md.
-- ──────────────────────────────────────────────────────────────────────
create policy "wiki_storage_self_select"
  on storage.objects for select
  using (
    bucket_id = 'wiki'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "wiki_storage_self_insert"
  on storage.objects for insert
  with check (
    bucket_id = 'wiki'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "wiki_storage_self_update"
  on storage.objects for update
  using (
    bucket_id = 'wiki'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'wiki'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "wiki_storage_self_delete"
  on storage.objects for delete
  using (
    bucket_id = 'wiki'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

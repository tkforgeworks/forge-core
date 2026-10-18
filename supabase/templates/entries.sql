-- forge_core template: the generic jsonb table an app's user data lives in
-- (spec: Data model). Copy into the app's supabase/migrations with a
-- timestamp prefix AFTER the forge_accounts migration; rename the table if
-- the app wants. The shape is what ForgeEntriesRepository and an app-side
-- last-write-wins sync expect.

create table if not exists public.entries (
  -- Client-supplied: the app's own UUID for the row, so a device can create
  -- offline and push later without an id exchange.
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  -- One table, many kinds ('tasting_note', …); each kind has its own
  -- fromJson/toJson in the app.
  kind text not null,
  data jsonb not null,
  created_at timestamptz not null default now(),
  -- Client-supplied: the device's last-change time; the newest wins.
  updated_at timestamptz not null,
  -- Tombstone: set when deleted; data is '{}' from then on. Rows are kept
  -- so other devices learn about the deletion, and go with the user.
  deleted_at timestamptz,
  constraint entries_tombstone_empty
    check (deleted_at is null or data = '{}'::jsonb)
);

comment on table public.entries is
  'forge_core: per-user jsonb entries with client-supplied id/updated_at and tombstones.';

-- What the sync's key listing walks: one user's rows by change time.
create index if not exists entries_user_updated
  on public.entries (user_id, updated_at, id);
create index if not exists entries_user_kind
  on public.entries (user_id, kind);

alter table public.entries enable row level security;

drop policy if exists "entries: own rows" on public.entries;
create policy "entries: own rows"
  on public.entries for all
  to authenticated
  using ((select auth.uid()) = user_id and public.forge_account_active())
  with check ((select auth.uid()) = user_id and public.forge_account_active());

grant select, insert, update, delete on public.entries to authenticated;

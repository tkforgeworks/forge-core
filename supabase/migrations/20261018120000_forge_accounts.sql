-- forge_core: the shared account row (spec: Data model).
--
-- One row per auth user, created by trigger so an account never exists
-- without it. The client reads only its own row and never writes the table
-- directly: changes go through the security-definer functions below, which
-- act on auth.uid() only. forge_account_active() is what every user-owned
-- table's policy calls, so access ends the moment deletion is requested.
--
-- Copied into each app's supabase/migrations by `dart run
-- forge_core:sync_supabase`; never edit the copy.

create table if not exists public.accounts (
  id uuid primary key references auth.users (id) on delete cascade,
  username text
    constraint accounts_username_length
      check (username is null or char_length(username) between 1 and 40),
  created_at timestamptz not null default now(),
  deletion_requested_at timestamptz
);

comment on table public.accounts is
  'forge_core: one row per auth user; username and the pending-deletion flag.';

alter table public.accounts enable row level security;

-- Read your own row; no insert/update/delete policy at all.
drop policy if exists "accounts: read own row" on public.accounts;
create policy "accounts: read own row"
  on public.accounts for select
  to authenticated
  using ((select auth.uid()) = id);

grant select on public.accounts to authenticated;

-- A row for every new auth user.
create or replace function public.forge_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.accounts (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists forge_on_auth_user_created on auth.users;
create trigger forge_on_auth_user_created
  after insert on auth.users
  for each row execute function public.forge_handle_new_user();

-- Users that existed before this migration.
insert into public.accounts (id)
select id from auth.users
on conflict (id) do nothing;

-- True while the caller's account is not pending deletion. Every
-- user-owned table's policy includes this.
create or replace function public.forge_account_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.accounts
    where id = (select auth.uid()) and deletion_requested_at is null
  );
$$;

-- Sets (or clears, with null / blank) the caller's username.
create or replace function public.set_username(new_username text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v text := nullif(btrim(new_username), '');
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  if v is not null and char_length(v) > 40 then
    raise exception 'username is longer than 40 characters'
      using errcode = '22001';
  end if;
  update public.accounts
  set username = v
  where id = (select auth.uid()) and deletion_requested_at is null;
end;
$$;

-- Flags the caller's account for the purge (forge_core deleteAccount()).
-- Idempotent: a second call keeps the first timestamp.
create or replace function public.request_account_deletion()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  update public.accounts
  set deletion_requested_at = coalesce(deletion_requested_at, now())
  where id = (select auth.uid());
end;
$$;

revoke all on function public.forge_handle_new_user() from public;
revoke all on function public.forge_account_active() from public;
revoke all on function public.set_username(text) from public;
revoke all on function public.request_account_deletion() from public;
grant execute on function public.forge_account_active() to authenticated;
grant execute on function public.set_username(text) to authenticated;
grant execute on function public.request_account_deletion() to authenticated;

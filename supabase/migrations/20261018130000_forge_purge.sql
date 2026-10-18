-- forge_core: drive the account purge (spec: Account deletion).
--
-- When accounts.deletion_requested_at is set, a first purge attempt starts at
-- once; a pg_cron job repeats the call every 15 minutes for every account
-- still flagged, so a failed attempt is retried until the purge Edge
-- Function (supabase/functions/forge-purge) has removed the user. The
-- function is reached through pg_net with a shared token; both the project
-- URL and the token live in Vault under fixed names:
--
--   select vault.create_secret('https://<ref>.supabase.co', 'forge_project_url');
--   select vault.create_secret('<random token>',           'forge_purge_token');
--
-- and the same token is the function's FORGE_PURGE_TOKEN secret. Until both
-- exist, requesting deletion still works (the flag is set and access ends);
-- the purge simply waits.

create or replace function public.forge_request_purge()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  project_url text;
  purge_token text;
begin
  select decrypted_secret into project_url
    from vault.decrypted_secrets where name = 'forge_project_url' limit 1;
  select decrypted_secret into purge_token
    from vault.decrypted_secrets where name = 'forge_purge_token' limit 1;
  if project_url is null or purge_token is null then
    raise notice 'forge_request_purge: vault secrets missing; purge not called';
    return;
  end if;
  if not exists (
    select 1 from public.accounts where deletion_requested_at is not null
  ) then
    return;
  end if;
  perform net.http_post(
    url := rtrim(project_url, '/') || '/functions/v1/forge-purge',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || purge_token
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000
  );
end;
$$;

revoke all on function public.forge_request_purge() from public;

-- First attempt: the moment an account is flagged.
create or replace function public.forge_on_deletion_requested()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.deletion_requested_at is not null
     and old.deletion_requested_at is null then
    perform public.forge_request_purge();
  end if;
  return new;
end;
$$;

revoke all on function public.forge_on_deletion_requested() from public;

drop trigger if exists forge_on_deletion_requested on public.accounts;
create trigger forge_on_deletion_requested
  after update of deletion_requested_at on public.accounts
  for each row execute function public.forge_on_deletion_requested();

-- Retry: every 15 minutes while anything is flagged.
select cron.unschedule(jobid) from cron.job where jobname = 'forge-purge';
select cron.schedule(
  'forge-purge',
  '*/15 * * * *',
  $$ select public.forge_request_purge(); $$
);

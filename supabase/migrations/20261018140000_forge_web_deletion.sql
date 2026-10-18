-- forge_core: web-initiated account deletion (spec: Account deletion, "Web
-- deletion requests").
--
-- The website's form posts an email to the forge-delete-request Edge
-- Function, which asks the database for a single-use token (stored only as
-- a SHA-256 hash, with an expiry) and emails a confirmation link. Clicking
-- it calls forge-delete-confirm, which consumes the token and flags the
-- account exactly as the in-app path does; the purge takes over from there.
--
-- The token table lives in a schema PostgREST does not expose; the two
-- functions below are the only way in, and only the project's secret key
-- (service_role) may call them.

create schema if not exists forge_private;
revoke all on schema forge_private from public, anon, authenticated;

create table if not exists forge_private.deletion_tokens (
  token_hash text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz
);

comment on table forge_private.deletion_tokens is
  'forge_core: hashed single-use tokens for web-initiated account deletion.';

-- Issues a token for the account with [target_email], replacing any
-- outstanding one. Returns the raw token (never stored) or null when no
-- such account exists; the caller answers identically either way.
create or replace function public.forge_create_deletion_token(
  target_email text,
  ttl interval default interval '24 hours'
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  target uuid;
  raw text;
begin
  select id into target
    from auth.users
    where lower(email) = lower(btrim(target_email))
    limit 1;
  if target is null then
    return null;
  end if;
  raw := translate(
    encode(extensions.gen_random_bytes(32), 'base64'),
    '+/=', '-_'
  );
  delete from forge_private.deletion_tokens where user_id = target;
  insert into forge_private.deletion_tokens (token_hash, user_id, expires_at)
  values (
    encode(extensions.digest(raw, 'sha256'), 'hex'),
    target,
    now() + ttl
  );
  return raw;
end;
$$;

-- Consumes [raw_token]: true when it was valid, unexpired and unused, in
-- which case the account is flagged (which starts the purge). False
-- otherwise; nothing is revealed about why.
create or replace function public.forge_confirm_deletion(raw_token text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  hit forge_private.deletion_tokens%rowtype;
begin
  select * into hit
    from forge_private.deletion_tokens
    where token_hash = encode(extensions.digest(coalesce(raw_token, ''), 'sha256'), 'hex')
    for update;
  if hit.token_hash is null or hit.consumed_at is not null or hit.expires_at < now() then
    return false;
  end if;
  update forge_private.deletion_tokens
    set consumed_at = now()
    where token_hash = hit.token_hash;
  update public.accounts
    set deletion_requested_at = coalesce(deletion_requested_at, now())
    where id = hit.user_id;
  return true;
end;
$$;

-- Housekeeping: drop tokens that can no longer be used.
create or replace function public.forge_prune_deletion_tokens()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from forge_private.deletion_tokens
  where consumed_at is not null or expires_at < now() - interval '1 day';
$$;

revoke all on function public.forge_create_deletion_token(text, interval) from public, anon, authenticated;
revoke all on function public.forge_confirm_deletion(text) from public, anon, authenticated;
revoke all on function public.forge_prune_deletion_tokens() from public, anon, authenticated;
grant execute on function public.forge_create_deletion_token(text, interval) to service_role;
grant execute on function public.forge_confirm_deletion(text) to service_role;
grant execute on function public.forge_prune_deletion_tokens() to service_role;

select cron.unschedule(jobid) from cron.job where jobname = 'forge-prune-deletion-tokens';
select cron.schedule(
  'forge-prune-deletion-tokens',
  '17 4 * * *',
  $$ select public.forge_prune_deletion_tokens(); $$
);

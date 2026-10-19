-- Smoke test for 20261018140000_forge_web_deletion.sql. Rolls back.
begin;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at,
        confirmation_token, recovery_token, email_change_token_new, email_change, email_change_token_current,
        phone_change, phone_change_token, reauthentication_token, raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous)
values ('00000000-0000-4000-8000-00000000000b', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'Web-Smoke@example.com', '', now(), now(),
        '', '', '', '', '', '', '', '', '{}', '{}', false, false);

do $$
declare
  tok text;
begin
  -- Unknown address: null, and nothing stored.
  if public.forge_create_deletion_token('nobody@example.com') is not null then
    raise exception 'unknown email should yield null';
  end if;
  if (select count(*) from forge_private.deletion_tokens) <> 0 then
    raise exception 'no token should be stored for an unknown email';
  end if;

  -- Known address, case-insensitive, trimmed.
  tok := public.forge_create_deletion_token('  web-smoke@EXAMPLE.com ');
  if tok is null or length(tok) < 40 then
    raise exception 'token not issued';
  end if;
  if exists (select 1 from forge_private.deletion_tokens where token_hash = tok) then
    raise exception 'raw token must not be stored';
  end if;

  -- A bad token does nothing.
  if public.forge_confirm_deletion('not-a-token') then
    raise exception 'bad token should not confirm';
  end if;
  -- The real one flags the account, once.
  if not public.forge_confirm_deletion(tok) then
    raise exception 'valid token should confirm';
  end if;
  if (select deletion_requested_at from public.accounts where id = '00000000-0000-4000-8000-00000000000b') is null then
    raise exception 'account not flagged';
  end if;
  if public.forge_confirm_deletion(tok) then
    raise exception 'a consumed token should not confirm again';
  end if;

  -- Issuing again replaces; an expired token is refused.
  tok := public.forge_create_deletion_token('web-smoke@example.com', interval '-1 second');
  if public.forge_confirm_deletion(tok) then
    raise exception 'expired token should not confirm';
  end if;
  perform public.forge_prune_deletion_tokens();
  if (select count(*) from forge_private.deletion_tokens) <> 1 then
    -- the just-expired one is kept a day for diagnostics; the consumed one is gone
    raise exception 'prune kept % rows', (select count(*) from forge_private.deletion_tokens);
  end if;
end $$;

-- The functions are not callable as a user.
set local role authenticated;
do $$
begin
  begin
    perform public.forge_create_deletion_token('web-smoke@example.com');
    raise exception 'authenticated should not be able to issue tokens';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

rollback;

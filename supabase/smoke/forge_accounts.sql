-- Smoke test for 20261018120000_forge_accounts.sql. Run against a project
-- that has the migration applied; everything rolls back.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/smoke/forge_accounts.sql
begin;

-- A throwaway auth user; the trigger must give it an account row.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'smoke@example.com', '', now(), now());

do $$
begin
  if not exists (select 1 from public.accounts where id = '00000000-0000-4000-8000-000000000001') then
    raise exception 'trigger did not create the account row';
  end if;
end $$;

-- Act as that user.
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select public.set_username('  Tim  ');
do $$
begin
  if (select username from public.accounts where id = auth.uid()) <> 'Tim' then
    raise exception 'set_username did not trim and store';
  end if;
  if not public.forge_account_active() then
    raise exception 'account should be active';
  end if;
end $$;

select public.set_username('');
do $$
begin
  if (select username from public.accounts where id = auth.uid()) is not null then
    raise exception 'blank username should clear';
  end if;
end $$;

-- Direct writes are refused by RLS (no policy).
do $$
begin
  begin
    update public.accounts set username = 'hacker' where id = auth.uid();
    if (select username from public.accounts where id = auth.uid()) = 'hacker' then
      raise exception 'direct update should not have taken effect';
    end if;
  exception when insufficient_privilege then
    null; -- also fine
  end;
end $$;

select public.request_account_deletion();
do $$
begin
  if public.forge_account_active() then
    raise exception 'account should be inactive after the request';
  end if;
  -- The row is still readable (select policy) so the flag can be shown.
  if (select deletion_requested_at from public.accounts where id = auth.uid()) is null then
    raise exception 'deletion_requested_at not set';
  end if;
end $$;

reset role;
rollback;

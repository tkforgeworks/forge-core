-- Smoke test for templates/entries.sql. Run with the template prepended,
-- inside one transaction that rolls back:
--   { echo 'begin;'; cat supabase/templates/entries.sql supabase/smoke/entries.sql; echo 'rollback;'; } | <run on the project>
-- Needs the forge_accounts migration applied (forge_account_active()).

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at,
        confirmation_token, recovery_token, email_change_token_new, email_change, email_change_token_current,
        phone_change, phone_change_token, reauthentication_token, raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous)
values ('00000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'smoke2@example.com', '', now(), now(),
        '', '', '', '', '', '', '', '', '{}', '{}', false, false),
       ('00000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'smoke3@example.com', '', now(), now(),
        '', '', '', '', '', '', '', '', '{}', '{}', false, false);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

-- Own rows: insert, upsert newer, tombstone.
insert into public.entries (id, user_id, kind, data, updated_at)
values ('10000000-0000-4000-8000-000000000001', auth.uid(), 'tasting_note', '{"name":"Comté"}', '2026-10-18T10:00:00Z');
insert into public.entries (id, user_id, kind, data, updated_at)
values ('10000000-0000-4000-8000-000000000001', auth.uid(), 'tasting_note', '{"name":"Comté 24"}', '2026-10-18T11:00:00Z')
on conflict (id) do update set data = excluded.data, updated_at = excluded.updated_at, deleted_at = excluded.deleted_at;
do $$
begin
  if (select data->>'name' from public.entries where id = '10000000-0000-4000-8000-000000000001') <> 'Comté 24' then
    raise exception 'upsert did not replace';
  end if;
end $$;
update public.entries set data = '{}', deleted_at = now(), updated_at = now()
  where id = '10000000-0000-4000-8000-000000000001';

-- Another user's row is invisible and cannot be written to.
do $$
begin
  begin
    insert into public.entries (id, user_id, kind, data, updated_at)
    values ('10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000003', 'tasting_note', '{}', now());
    raise exception 'inserting for another user should fail';
  exception when insufficient_privilege then null;
  end;
end $$;

-- A tombstone must have empty data.
do $$
begin
  begin
    insert into public.entries (id, user_id, kind, data, updated_at, deleted_at)
    values ('10000000-0000-4000-8000-000000000003', auth.uid(), 'tasting_note', '{"x":1}', now(), now());
    raise exception 'tombstone with data should fail the check';
  exception when check_violation then null;
  end;
end $$;

-- Access ends the moment deletion is requested.
select public.request_account_deletion();
do $$
begin
  if (select count(*) from public.entries) <> 0 then
    raise exception 'rows should be invisible once deletion is requested';
  end if;
end $$;

reset role;

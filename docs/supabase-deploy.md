# Deploying forge_core's Supabase files from an app

The app repo owns the Supabase project; forge_core ships the SQL, Edge
Functions and templates the project needs. This is the manual runbook until
an org `deploy-supabase.yml` exists.

## 1. Sync the files (every time the forge_core pin moves)

From the app's root:

```sh
dart run forge_core:sync_supabase
```

copies `supabase/migrations/*_forge_*.sql`, `supabase/functions/forge-*`,
`supabase/functions/_shared/` and `supabase/templates/` from the pinned
package into the app's `supabase/` folder and writes
`supabase/forge_core.lock` (version + file hashes). The app's own migration
(its `entries` table, from `supabase/templates/entries.sql`) lives beside
them with a later timestamp. Commit it all.

Keep the copies honest with one test:

```dart
import 'package:forge_core/sync_check.dart';

test('supabase files match the pinned forge_core', () async {
  expect(await forgeSupabaseDrift(), isEmpty);
});
```

`dart run forge_core:sync_supabase --check` does the same from the shell.

## 2. Database

Either link once and push (needs the database password):

```sh
supabase link --project-ref <ref>
supabase db push
```

or run each new migration through the Management API with a project-scoped
access token (Database + Migrations read-write) and record it:

```sql
-- after running the migration file:
insert into supabase_migrations.schema_migrations (version, statements, name)
values ('<timestamp>', array['<file contents>'], '<name>');
```

cheesy-scribe's project already has every forge migration recorded this way,
so `db push` from the app will only apply the app's own.

## 3. Secrets, Vault and functions

```sh
REF=<ref>
supabase secrets set \
  FORGE_PURGE_TOKEN=<random> \
  FORGE_WEB_DELETE_SECRET=<random, shared with the website> \
  "FORGE_MAIL_FROM=<App> <accounts@tkforgeworks.com>" \
  "FORGE_APP_NAME=<App>" \
  FORGE_SITE_URL=https://tkforgeworks.com/privacy/<app>/delete-account \
  RESEND_API_KEY=<key> \
  --project-ref "$REF"
```

```sql
select vault.create_secret('https://<ref>.supabase.co', 'forge_project_url');
select vault.create_secret('<the FORGE_PURGE_TOKEN value>', 'forge_purge_token');
```

```sh
for f in forge-purge forge-delete-request forge-delete-confirm; do
  supabase functions deploy "$f" --project-ref "$REF" --use-api --no-verify-jwt
done
```

`--use-api` bundles server-side (no Docker); `--no-verify-jwt` because the
callers are the database and the website, not users. No `supabase link` is
needed for these.

## 4. Dashboard-only settings

Auth → Email Templates (paste `supabase/templates/*.html`; subjects in that
folder's README), SMTP (Resend), Providers (Google with the web client;
email with confirmation; manual linking on), URL configuration (Site URL and
the app's `<applicationId>://auth-callback` redirect).

## 5. Verify

`select jobname, schedule from cron.job` shows `forge-purge` and
`forge-prune-deletion-tokens`; `supabase functions list --project-ref` shows
the three functions; the smoke files under forge-core's `supabase/smoke/`
run clean against the project (they roll back); `docs/deletion.md` has the
end-to-end check for the purge and the web path.

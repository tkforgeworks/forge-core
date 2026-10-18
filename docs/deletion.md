# Account deletion: how it works and how to deploy it

Google Play requires in-app deletion plus a web deletion URL as soon as
anyone can create an account, so `forge_core` ships deletion in the same
release as sign-in.

## The flow

1. **The app** calls `core.accounts.deleteAccount()`. It runs the database
   function `request_account_deletion()` (sets `accounts.deletion_requested_at`;
   from that moment `forge_account_active()` is false and every policy
   refuses the account's rows, even for a token that has not expired) and
   then signs out on every device. The app decides what happens to its local
   copy (cheesy-scribe keeps it unless the user chose to erase).
2. **The database** fires `forge_on_deletion_requested` on that update, which
   calls `forge_request_purge()`: it reads the project URL and the shared
   purge token from Vault and POSTs to the `forge-purge` Edge Function
   through `pg_net`. A `pg_cron` job (`forge-purge`, every 15 minutes) calls
   the same function while any account stays flagged, so a failed purge is
   retried until it succeeds.
3. **The purge function** checks the shared token, then for each flagged
   account deletes the user's Storage objects (every bucket, prefix
   `<user_id>/`, walking folders), the user's Vault secrets if an app stores
   any, and finally the auth user, which cascades to `accounts` and every
   app table that follows the cascade rule. It logs ids only.

Nothing is kept: no anonymised copy, no soft-delete beyond the flag that
exists only until the purge runs. The privacy policy states the purge
window (minutes under normal conditions; the retry covers outages).

## The web path

Google Play's deletion URL points at the app's page on the website
(`/privacy/<app>/delete-account/`). Its form posts the address to a website
Pages Function, which forwards `{email}` to the **forge-delete-request**
Edge Function with a shared header secret (`FORGE_WEB_DELETE_SECRET`). That
function asks the database for a token (`forge_create_deletion_token`:
random, stored only as a SHA-256 hash in `forge_private.deletion_tokens`,
24-hour expiry, one outstanding per account) and, if the address has an
account, emails a confirmation link through Resend. The response is `200
{ok:true}` whether or not the address exists, so the form cannot be used to
discover accounts. The link opens **forge-delete-confirm**, which consumes
the token (`forge_confirm_deletion`: valid, unexpired, unused) and sets
`accounts.deletion_requested_at`, so the same purge runs; the visitor lands
back on the website page with `?status=done` or `?status=invalid`. Consumed
and stale tokens are pruned nightly (`forge-prune-deletion-tokens`).

The website holds no Supabase key; only the shared header secret. The two
database functions are callable by the project's secret key alone.

Per-project secrets for the two functions: `FORGE_WEB_DELETE_SECRET` (same
value on the website), `RESEND_API_KEY`, `FORGE_MAIL_FROM` (`"App
<accounts@example.com>"`), `FORGE_APP_NAME`, `FORGE_SITE_URL` (the
delete-account page). Deploy both with `--no-verify-jwt`.

Verify: `supabase/smoke/web_deletion.sql` (rolls back) covers token issue,
hash-only storage, bad / consumed / expired tokens, pruning and the grant;
then post a real address to `forge-delete-request` with the header secret
and follow the link in the mail.

## Deploying it to a project

Once per project, after the `forge_accounts` migration. The commands use the
Supabase CLI with a project ref and need no `supabase link`.

```sh
REF=<project-ref>
TOKEN=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')

# 1. The function's secret (names starting with SUPABASE_ are reserved).
supabase secrets set FORGE_PURGE_TOKEN="$TOKEN" --project-ref "$REF"

# 2. The same token and the project URL in Vault, for pg_net.
#    (run as SQL on the project)
select vault.create_secret('https://'||'<ref>'||'.supabase.co', 'forge_project_url');
select vault.create_secret('<the token>', 'forge_purge_token');

# 3. The function, bundled server-side; no JWT check because the caller is
#    the database, not a user.
supabase functions deploy forge-purge --project-ref "$REF" --use-api --no-verify-jwt

# 4. The migration (supabase/migrations/*_forge_purge.sql): trigger + cron.
```

Verify: insert a throwaway `auth.users` row **the way GoTrue does** (the
token columns `confirmation_token`, `recovery_token`, `email_change*`,
`phone_change*`, `reauthentication_token` as `''`, the metadata columns as
`'{}'`; a row with NULLs there makes the admin API fail with "Database error
loading user"), `update public.accounts set deletion_requested_at = now()
where id = …`, wait a few seconds, confirm the user is gone and `select *
from net._http_response order by id desc limit 1` shows a 200 from the
function (207 lists per-account failures in the body). `select * from cron.job where jobname =
'forge-purge'` shows the schedule.

Rotating the token: set a new `FORGE_PURGE_TOKEN` secret, then
`select vault.update_secret(id, '<new>') from vault.secrets where name =
'forge_purge_token'`.

# Supabase files shipped with forge_core

What an app copies into its own `supabase/` folder at the forge_core tag it
pins (`dart run forge_core:sync_supabase`, which also writes
`supabase/forge_core.lock`) and deploys per `docs/supabase-deploy.md`.
Policy lives here; apps never edit the copies, and `forgeSupabaseDrift()`
from `package:forge_core/sync_check.dart` in each app's tests fails if they
differ.

| Folder | Contents |
| --- | --- |
| `migrations/` | `*_forge_accounts.sql` (the `accounts` table, trigger, `forge_account_active()`, `set_username()`, `request_account_deletion()`), `*_forge_purge.sql` (purge trigger + `pg_cron` retry via `pg_net`), `*_forge_web_deletion.sql` (`forge_private.deletion_tokens`, `forge_create_deletion_token()`, `forge_confirm_deletion()`, nightly prune) |
| `functions/` | Edge Functions, all deployed with `--no-verify-jwt`: `forge-purge` (shared token in `FORGE_PURGE_TOKEN` and Vault), `forge-delete-request` (website → token + Resend mail), `forge-delete-confirm` (link → flag); `_shared/mail.ts` renders and sends the mail |
| `templates/` | The auth email templates, pasted into the dashboard |
| `smoke/` | SQL smoke tests that run against a project and roll back |

Migration files carry a timestamp prefix so the CLI orders them with an
app's own; an app's `entries` migration (from `templates/entries.sql`,
FC-8) comes after them.

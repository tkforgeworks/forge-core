# Supabase files shipped with forge_core

What an app copies into its own `supabase/` folder at the forge_core tag it
pins (`dart run forge_core:sync_supabase`, FC-11) and deploys with the
Supabase CLI. Policy lives here; apps never edit the copies, and a drift
check in each app's tests fails if they differ.

| Folder | Contents |
| --- | --- |
| `migrations/` | `*_forge_accounts.sql` (the `accounts` table, trigger, `forge_account_active()`, `set_username()`, `request_account_deletion()`), `*_forge_purge.sql` (purge trigger + `pg_cron` retry via `pg_net`); later the web-deletion token table |
| `functions/` | Edge Functions: `forge-purge` (deployed with `--no-verify-jwt`; shared token in `FORGE_PURGE_TOKEN` and Vault), web deletion request and confirm (FC-10) |
| `templates/` | The auth email templates, pasted into the dashboard |
| `smoke/` | SQL smoke tests that run against a project and roll back |

Migration files carry a timestamp prefix so the CLI orders them with an
app's own; an app's `entries` migration (from `templates/entries.sql`,
FC-8) comes after them.

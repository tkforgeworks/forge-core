# Data model: accounts and the rules every app table follows

`forge_core` installs one shared table, `public.accounts`, and three
functions. Apps add their own tables for user data (cheesy-scribe's
`entries`, FC-8) and follow the rules below so deletion and access control
work the same everywhere.

## `accounts`

| Column | Meaning |
| --- | --- |
| `id` | `auth.users.id`; `on delete cascade` so the purge takes the row with the user |
| `username` | What the user typed on the account page; null until then; at most 40 characters |
| `created_at` | "Member since" |
| `deletion_requested_at` | Set by `request_account_deletion()`; the purge removes the row; never cleared |

- A row appears **by trigger** on `auth.users` insert, so no account exists
  without one. Existing users are backfilled when the migration runs.
- The client can **select its own row** and nothing else: no insert,
  update or delete policy. Writes go through security-definer functions
  that act on `auth.uid()`:
  - `set_username(text)`: trims, clears on blank, refuses > 40 and refuses
    when the account is pending deletion.
  - `request_account_deletion()`: sets the flag (idempotent);
    `deleteAccount()` calls it and signs out everywhere. The flag's trigger
    starts the purge and a cron job retries it: see `docs/deletion.md`.
- `forge_account_active()` is true while the caller's account has no
  deletion flag. It is `security definer` so it can read `accounts` from
  inside another table's policy.

## Rules for an app's own tables

```sql
create table public.entries (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  -- …
);
alter table public.entries enable row level security;
create policy "entries: own rows" on public.entries
  for all to authenticated
  using ((select auth.uid()) = user_id and public.forge_account_active())
  with check ((select auth.uid()) = user_id and public.forge_account_active());
```

1. **Cascade.** Every user-owned table declares `user_id … references
   auth.users (id) on delete cascade`. Postgres's default (`no action`)
   would block the purge instead of deleting the rows.
2. **Active check.** Every policy includes `forge_account_active()`, so a
   token that is still valid stops working the instant deletion is
   requested.
3. **Storage.** Files live under `<bucket>/<user_id>/…`; the purge walks
   every bucket and deletes that prefix through the Storage API.
4. **Wrap `auth.uid()` in `(select …)`** so Postgres evaluates it once per
   statement rather than per row.

## `entries` (the app's user data)

`supabase/templates/entries.sql` is the one table shape an app copies into
its own migrations (after the forge_accounts one) for everything the user
creates: `id` and `updated_at` are **client-supplied** so a device can
create offline and push later with the newest change winning; `kind`
separates an app's types inside one table; `data` is the app's JSON;
`deleted_at` is a tombstone with `data = '{}'` enforced by a check, kept so
other devices learn about the deletion. The policy is the rule above
(`own rows` + `forge_account_active()`), and
`(user_id, updated_at, id)` is indexed for the sync's key listing.
`supabase/smoke/entries.sql` exercises it (upsert replaces, another user's
row is refused, a tombstone must be empty, access ends on deletion) and
rolls back.

## In Dart

`core.accounts` (`ForgeAccounts`): `getAccount()`, `watchAccount()` (re-read
on every auth change), `setUsername()`. `core.entries<T>(kind:, fromJson:,
toJson:)` (`ForgeEntriesRepository<T>`): `upsertAll`, `listKeys({since})`
(paged, oldest change first), `fetchByIds`, `markDeleted(ids, at)`; these
four are exactly what an app-side last-write-wins sync needs. Every call
returns a `ForgeResult` (`ForgeOk(value)` or `ForgeFailed(ForgeDataError,
message)`) and never throws. `FakeForgeAccounts` and
`FakeForgeEntriesRepository` in `package:forge_core/testing.dart` follow a
`FakeForgeAuth`; the latter's `remoteUpsert` plays a second device.

## Verifying the SQL

No local Postgres (Docker is too heavy on the dev box), so SQL is checked
against the real project through the Management API's query endpoint with
a project-scoped access token (Database + Migrations read-write): apply a
migration, then run its smoke file, which creates a throwaway auth user,
exercises everything as that user, and rolls back. The entries template is
checked the same way with the template prepended inside one rolled-back
transaction. Migrations applied this way are also recorded in
`supabase_migrations.schema_migrations` so an app's later `supabase db
push` sees them as applied.

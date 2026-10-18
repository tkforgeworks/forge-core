# forge-core — Claude Reference

## What this is

`forge-core` is the public repo for the Flutter package `forge_core`: the
sign-in, account and data plumbing every tkforgeworks app shares, built on
Supabase. Apps consume it as a git dependency pinned to a release tag. Its
sibling `forge-ui` carries the brand look; the two packages never depend on
each other. Current phase: repo ready (FC-2), spec revised for the first real
consumer (cheesy-scribe 0.3.0, FC-1); v0.1.0 code starts with FC-3.

**The spec is `docs/forge-ui_forge-core_Shared_Flutter_Packages_Spec.md`
and this repo holds the canonical copy** (decided 2026-10-17). forge-ui's
`docs/` keeps a pointer to it, not a copy. Spec changes land here only.

## Stack & commands

| Task | Command |
|---|---|
| Install | `flutter pub get` |
| Format check | `dart format --output=none --set-exit-if-changed .` |
| Analyze | `flutter analyze` |
| Test | `flutter test` |

`dart format` ignores `analysis_options.yaml` excludes, so every `.dart` file
in the repo (including any under `docs/`) must be formatted.

## Repo & process conventions (org standard)

- Branching (org standard, `tkforgeworks/.github/docs/branching-and-release.md`):
  `main` is the released state; work accumulates on the current release branch
  `vX.Y.Z/main` (currently `v0.1.0/main`; `v0.0.1` was a setup-only batch
  that shipped no tag); topic branches PR **into the release branch**,
  never into `main`; the release branch reaches `main` via a release PR.
- `main` is protected by the org repository ruleset: PR-only, no force-push or
  deletion, **no bypass actors** (not even admins). Required check: `ci / ci`.
  Release branches (`v*/main`) have a second ruleset: no force-push/deletion,
  no required check.
  Standard: `tkforgeworks/.github/docs/branch-protection-ruleset.md`.
- CI consumes the shared reusable workflow
  `tkforgeworks/.github/.github/workflows/ci-flutter.yml@main`
  (`flutter-version: '3.47.5'`, the same pin as forge-ui and cheesy-scribe;
  move all three together). Don't hand-roll steps that belong in the shared
  workflow — change it there.
- **Jira project `FC`** (`https://tkforgeworks.atlassian.net/browse/FC`,
  created 2026-10-17; forge-ui is `FU`). Commit subjects are the changelog:
  `FC-N: Imperative summary`; bug fixes `FC-N: Fix ...`. Branches
  `vX.Y.Z/FC-N-short-topic`. Move a ticket to *In Progress* when its branch
  opens. **Never close a ticket unless asked** — comment "Actions taken" +
  commit hash and leave it for the human to verify. Work before FC-1 carries
  no key (the `org-standards.yml` deviation for that was removed in FC-1).
- Releases (FC-2): `.github/workflows/release.yml` consumes the org
  `release-flutter.yml` with both platform builds off and `ticket-prefix:
  FC` (repo variable `JIRA_BASE_URL` links subjects), so a release is a tag
  and a GitHub release with notes and no files. On `vX.Y.Z/main`,
  `scripts/release/bump-version.sh rc` publishes prerelease `vX.Y.Z-rc.N`;
  `bump-version.sh final` opens the release PR, and merging it into `main`
  publishes `vX.Y.Z`. **Never hand-edit the version or push tags.**
  `pubspec.yaml` holds the upcoming version (`0.1.0+1` now; the build
  number means nothing for a package but the script needs it) with the
  floor `sdk: ^3.13.2`, `flutter: ">=3.47.2"` so apps on Flutter 3.47.2
  still resolve it. The bump scripts are the vendored org copies (same as
  forge-ui's); don't edit them here.
- License: **Apache-2.0** (`LICENSE` is the verbatim Apache text — never
  edit it). Image assets (`.svg`/`.png`/etc.) are **all rights reserved** via
  `NOTICE`. `pubspec.yaml` has no license field; pub reads `LICENSE`.
  Standard: `tkforgeworks/.github/docs/licensing.md`.
- `.github/org-standards.yml` records the last org standards check and this
  repo's intentional deviations.
- Update this file as the last step of closing any ticket that changed
  conventions, architecture, or status.

## Architecture decisions (locked)

Reasoning and dates are in the spec's Decisions table; the 2026-10-17 rows
come from cheesy-scribe's planning ticket CHEESE-57.

- `forge-core` never depends on `forge-ui` and holds no UI styling; apps wire
  `forge-ui` screen callbacks to `forge-core`. Keeps Supabase out of the UI
  package and styling out of this one.
- No Supabase URL or keys in this repo; the app passes its client in. Apps
  receive their URL, `sb_publishable_…` key and Google web client ID as
  `--dart-define` values (`ForgeSupabaseConfig.fromEnvironment()`), never
  committed. The `sb_secret_…` key lives only server-side (Edge Function
  secrets, Vault). Legacy `anon`/`service_role` keys are not used.
- **Providers in v0.1: Google (native, Android) and email/password**, with
  required email confirmation, forgot-password, Resend as the project's
  custom SMTP, and identity linking (`linkIdentityWithIdToken` for Google,
  `updateUser` to add a password). Apple sign-in and everything it needs
  (.p8, Vault token, revocation, rotation job) wait for the first iOS app.
- **Sign-in is optional for the apps**: it only turns on backup. The package
  never reads or writes app storage; what happens to local data on sign-out
  or deletion is the app's call (cheese keeps it, with an erase option).
- **v0.1 ships sign-in and deletion together.** Google Play requires in-app
  deletion plus a web deletion URL as soon as testers can create accounts.
- Every user-owned table's policy is `auth.uid() = user_id and
  forge_account_active()`, so access ends the moment
  `accounts.deletion_requested_at` is set, even for an unexpired token.
- `accounts` rows are created by a trigger on `auth.users`. The client reads
  only its own row and writes only through security-definer functions
  (`request_account_deletion()`, `set_username(text)`). The username is
  never prefilled from the provider.
- The purge is attempted when the flag is set and retried by `pg_cron`
  (through `pg_net`, key in Vault) every 15 minutes. Storage objects are
  deleted through the Storage API, recursively under `<bucket>/<user_id>/`,
  walking every bucket with no per-app config.
- Web-deletion confirmation tokens are stored hashed in a private schema.
  The web page and form live on the website at
  `tkforgeworks.com/privacy/<app>/delete-account/` as a Pages Function in
  front of this repo's request and confirm Edge Functions; the website holds
  no Supabase secret.
- `entries` takes client-supplied `id` and `updated_at` and has a
  `deleted_at` tombstone; the repository helper offers `upsertAll`, a
  paginated `listKeys`, `fetchByIds` and `markDeleted`. **Sync itself is
  app-side** (last-write-wins manifest diff) and is promoted here only when
  a second app syncs.
- The SQL and Edge Functions under `supabase/` are copied into each app at
  its pinned tag by `bin/sync_supabase.dart`; a drift check in the app's
  tests fails if they differ.
- Rule of three applies to ambiguous reuse only; high-reuse screens are
  built in forge-ui first (that is forge-ui's rule, recorded in the spec).

Layout: `lib/forge_core.dart` is the only public library and exports
everything under `lib/src/` (`config/`, `auth/`, `forge_core.dart`);
`lib/testing.dart` holds the fakes apps import in tests. Tests mirror it
under `test/`; `docs/` holds the setup guides. Public names are prefixed
`Forge`. Supabase types never appear in the public API: `ForgeSession`,
`ForgeAuthState`, `ForgeAuthResult` (sealed: success / cancelled /
failure(`ForgeAuthError`)) are the plain types. Sign-in providers are
abstracted behind sources (`GoogleIdTokenSource`) so the auth logic is unit
tested with a scripted source and a `GoTrueClient` over `http`'s
`MockClient` (no network, no platform plugin; give it an in-memory
`GotrueAsyncStorage` or the PKCE calls assert, and build each mocked
`http.Response` with `request: request` or postgrest-dart's parser hits a
null check); the plugin wrapper itself is thin and verified on a device.
Data calls return `ForgeResult<T>` (`ForgeOk` / `ForgeFailed(ForgeDataError)`)
and auth calls `ForgeAuthResult`; nothing public throws. `supabase/templates/` holds the auth
mail templates apps paste into the dashboard; `bin/sync_supabase.dart`
(FC-11) will copy them alongside the SQL and functions.

## Current status

2026-10-17: spec revised for cheesy-scribe 0.3.0 in FC-1 (course corrections
from CHEESE-57 and Tim's decisions); the Oct 10 Apple-first milestones are
superseded. Jira project `FC` created. Supabase: Tim created the project
(empty); the org goes Pro from the start.

2026-10-18: FC-2 repo readiness: release pipeline adopted, `pubspec.yaml`
at `0.1.0+1` with the lower SDK floor, Dependabot `pub-minor-patch` group,
the three merged `v0.1.0/*` topic branches deleted, and the placeholder
test replaced by `ForgeSupabaseConfig` (`lib/src/config/`: the three
`--dart-define` names, `isConfigured`, `hasGoogle`, key-free `toString`)
with its tests. FC-3: `ForgeCore`, `ForgeAuth` session stream,
`FakeForgeAuth`; shipped as `v0.1.0-rc.1` (pipeline proven, notes link FC
tickets). FC-4: `signInWithGoogle()` via `PluginGoogleIdTokenSource`
(google_sign_in 7, Credential Manager, one nonce per process hashed for
Google and raw for Supabase, no access token so no second consent prompt),
`ForgeAuthResult`/`ForgeAuthError`, `docs/google-cloud-setup.md`. Tim's GCP
and Supabase setup is done (Web client + three Android clients, provider
on, redirect allow list); the consent screen stays in Testing until the
first tester RC. Shipped as `v0.1.0-rc.2`. FC-5: email/password
(`signUpWithEmail` → `ForgeAuthEmailSent` under confirmation,
`signInWithEmail`, `resendConfirmation`, `sendPasswordReset`,
`updatePassword`), `ForgeAuthError` email cases mapped from GoTrue's error
codes in `mapAuthException`, `ForgeSupabaseConfig.authRedirectUrl` (the
app's custom scheme, sent as `redirect_to`), branded templates under
`supabase/templates/`, `docs/email-setup.md` (SMTP via Resend, provider
settings, Site URL, manifest intent filter). Tim's SMTP setup is pending
(he wants Google verified first), so the real mail flow is first exercised
in CHEESE-61. Real-device verification of both providers happens there.
Shipped as `v0.1.0-rc.3`. FC-6: `linkGoogle()` (`linkIdentityWithIdToken`
on the current session; `identityAlreadyLinked`, `misconfigured` when
manual linking is off), `unlinkIdentity()` (refuses the last method before
any request; deletes by `ForgeIdentity.identityId`, then re-reads the
user), `setPassword()` = `updatePassword()`; `ForgeIdentity.identityId`
added. Tim finished the Supabase setup (SMTP via Resend, email provider,
Site URL, manual linking, pg_cron/pg_net/Vault, CLI at
`~/.supabase/bin`, on PATH via `.bashrc`; its token sits in the system
keyring, so agent shells can run `supabase` commands but cannot read the
token for the Management API). Shipped as `v0.1.0-rc.4`. FC-7: the
`accounts` migration (`supabase/migrations/20261018120000_forge_accounts.sql`:
table, trigger on `auth.users`, backfill, select-own-row policy,
`forge_account_active()`, `set_username(text)`,
`request_account_deletion()`, grants), `supabase/smoke/forge_accounts.sql`
(a rollback-only exercise of all of it as a throwaway user), `ForgeResult`
/ `ForgeDataError` for the data side, `ForgeAccount`, `ForgeAccounts`
(`getAccount`, `watchAccount` re-reading on every auth change,
`setUsername` via RPC then re-read), `FakeForgeAccounts`, `docs/data-model.md`.
Shipped as `v0.1.0-rc.5`. **SQL verification path:** no local Postgres, so
SQL runs against the cheesy-scribe project (ref `pqcpiggcmuspmbdhwiij`,
us-east-1) through the Management API query endpoint
(`POST /v1/projects/<ref>/database/query`, body `{query, read_only}`) with
Tim's project-scoped access token in `~/.supabase/access-token` (Database
+ Migrations + Edge Functions + Edge Function Secrets read-write, Project
Settings read; 7-day expiry, Tim regenerates). The accounts migration was
applied that way on 2026-10-18 and recorded in
`supabase_migrations.schema_migrations` (version `20261018120000`, name
`forge_accounts`) so an app's later `supabase db push` treats it as
applied; `smoke/forge_accounts.sql` passed. FC-8: `supabase/templates/
entries.sql` (client-supplied `id`/`updated_at`, `kind`, `data`,
`deleted_at` tombstone with an empty-data check, `(user_id, updated_at,
id)` index, own-rows + active policy; verified with `smoke/entries.sql`
inside a rolled-back transaction), `ForgeEntry`/`ForgeEntryKey`,
`ForgeEntriesRepository` (`upsertAll`, paged `listKeys`, `fetchByIds`,
`markDeleted`) via `core.entries<T>()`, `FakeForgeEntriesRepository`,
shared `forgeGuard`/`forgeDataErrorOf` in `supabase_errors.dart`. Shipped
as `v0.1.0-rc.6`. FC-9: `deleteAccount()` (RPC `request_account_deletion`
then global sign-out), `supabase/migrations/20261018130000_forge_purge.sql`
(`forge_request_purge()` reads `forge_project_url` + `forge_purge_token`
from Vault and `net.http_post`s the function; `forge_on_deletion_requested`
trigger fires it on the flag; `pg_cron` job `forge-purge` every 15 min),
`supabase/functions/forge-purge/index.ts` (shared-token auth, admin client
from `SUPABASE_SECRET_KEYS`, Storage prefix walk, optional per-user Vault
secrets via `forge_delete_user_secrets` RPC if an app defines it,
`auth.admin.deleteUser`; 200 or 207 with per-account failures),
`docs/deletion.md` runbook. **Deployed to the cheesy-scribe project on
2026-10-18**: secret `FORGE_PURGE_TOKEN` set via `supabase secrets set
--project-ref`, Vault entries created, function deployed with
`supabase functions deploy forge-purge --project-ref … --use-api
--no-verify-jwt` (no `supabase link` needed; the CLI's keyring token works
for these), migration applied and recorded; a throwaway user was purged end
to end. Gotcha: a raw `insert into auth.users` must set the token columns
to `''` and metadata to `'{}'` or GoTrue's admin API fails with "Database
error loading user". Shipped as `v0.1.0-rc.7`. FC-10: web deletion.
`20261018140000_forge_web_deletion.sql` (`forge_private.deletion_tokens`
in a schema PostgREST does not expose; `forge_create_deletion_token(email)`
returns a raw token and stores its SHA-256 with a 24 h expiry, null for an
unknown address; `forge_confirm_deletion(token)` consumes it and flags the
account; nightly `forge-prune-deletion-tokens`; both callable by
`service_role` only), Edge Functions `forge-delete-request` (website →
shared `FORGE_WEB_DELETE_SECRET` header → token → Resend mail via
`_shared/mail.ts`; always `200 {ok:true}`) and `forge-delete-confirm`
(`?token=` → 303 to `FORGE_SITE_URL/?status=done|invalid`). **Deployed to
the cheesy-scribe project** with `FORGE_WEB_DELETE_SECRET` (copy for the
website step at `~/.supabase/forge-web-delete-secret.cheesy-scribe`, mode
600), `FORGE_APP_NAME`, `FORGE_SITE_URL`; **`RESEND_API_KEY` and
`FORGE_MAIL_FROM` are still Tim's to set** (`supabase secrets set …
--project-ref pqcpiggcmuspmbdhwiij`), so the mail step is unverified until
then; everything else (auth, token issue, confirm, flag, purge) was
exercised live. The website page and Pages Function are TKFW-83. The
ticket map for v0.1.0 is FC-11..FC-12 (see CHEESE-57's 2026-10-18 comment
for the order).

## Next actions

1. **v0.1.0** (spec milestone 3), FC tickets in dependency order: FC-3
   (done) client wrapper + session stream, FC-4 (done) Google sign-in,
   FC-5 (done) email/password, FC-6 (done) identity linking, FC-7 (done),
   FC-8 (done), FC-9 (done, deployed), FC-10 (done, deployed; mail secrets
   pending)
   `accounts` migration + functions, FC-8 `entries` template + repository
   helper, FC-9 `deleteAccount()` + purge + `pg_cron`, FC-10 web request
   and confirm functions, FC-11 `bin/sync_supabase.dart` + drift check,
   FC-12 privacy templates. Cut an RC as soon as FC-3 lands (proves the
   pipeline) and after each ticket cheesy-scribe `v0.3.0/main` needs.
2. forge-ui v0.2 (FU-2..6) ships the sign-in panel/screen, account
   settings, typed confirm sheet and provider branding alongside, so shape
   the public API with those callbacks in mind (see the spec's
   `ForgeAccountSettings` sketch).

## Open items (repo and process)

- **`v0.0.1/main` still exists.** The `release-branches` ruleset blocks
  deleting any `v*/main` branch; the org `branch-protection-ruleset.md` has
  the disable–delete–re-enable runbook (used in cheesy-scribe and forge-ui
  on 2026-10-16). Toggling the ruleset needs Tim's explicit yes (FC-2 left
  it).
- **Dependabot targets `main`**, which bypasses the release-branch flow. The
  org pattern (cheesy-scribe CHEESE-53): leave its PRs open against `main`
  and bundle the updates on the release branch before the final bump.
- **Supabase extensions.** Confirmed on the cheesy-scribe project on
  2026-10-18: `pg_cron` 1.6.4, `pg_net` 0.20.4, `supabase_vault` 0.3.1.

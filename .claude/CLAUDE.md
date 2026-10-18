# forge-core — Claude Reference

## What this is

`forge-core` is the public repo for the Flutter package `forge_core`: the
sign-in, account and data plumbing every tkforgeworks app shares, built on
Supabase. Apps consume it as a git dependency pinned to a release tag. Its
sibling `forge-ui` carries the brand look; the two packages never depend on
each other. Current phase: repo setup done, spec revised for the first real
consumer (cheesy-scribe 0.3.0, FC-1 on 2026-10-17); no package code yet.

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
- Releases: not set up yet. The plan is the org tagless pipeline
  (`release-flutter.yml` with both platform builds off, plus the vendored
  `scripts/release/bump-version.{ps1,sh}`), adopted in the first v0.1.0 code
  PR. **Never hand-edit the version or push tags** once it is in place.
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

## Current status

As of 2026-10-17: org standards setup is on `main` (the `v0.0.1` batch), both
rulesets are active, `v0.1.0/main` is cut, and the Jira project `FC` exists.
The package is an empty skeleton with one placeholder test. The spec was
revised for cheesy-scribe 0.3.0 in FC-1 (course corrections from CHEESE-57
and Tim's decisions of 2026-10-17); the Oct 10 Apple-first milestones are
superseded. Supabase: Tim has created the project (empty) and the org goes
Pro from the start.

## Next actions

1. **Repo readiness** (own tickets): adopt the release pipeline (forge-ui PR
   #6 is the model), set `pubspec.yaml` to `0.1.0+1` with the floor
   `sdk: ^3.13.2` / `flutter: ">=3.47.2"` (CI's 3.47.5 Dart is 3.13.4, but
   a lower floor costs nothing), add a `pub` Dependabot group, delete the
   merged topic branches and `v0.0.1/main` (ruleset-toggle runbook), replace
   the placeholder test.
2. **v0.1.0** (spec milestone 3), as FC tickets ordered by dependency:
   config + client wrapper and session stream; Google sign-in; email/password
   with confirmation and reset (templates, deep link); identity linking;
   `accounts` migration, trigger, `forge_account_active()`, `set_username()`;
   `entries` shape and the repository helper with sync listing;
   `deleteAccount()` + purge function + `pg_cron` retry; request and confirm
   Edge Functions; `bin/sync_supabase.dart` + drift check; privacy template
   and inventory. Cut RCs as each lands; cheesy-scribe `v0.3.0/main`
   consumes them.
3. forge-ui v0.2 (FU) ships the sign-in panel/screen, account settings,
   typed confirm sheet and provider branding alongside, so shape the public
   API with those callbacks in mind (see the spec's `ForgeAccountSettings`
   sketch).

## Open items (repo and process)

- **Release pipeline** not adopted yet (see Next actions 1).
- **`v0.0.1/main` still exists.** The `release-branches` ruleset blocks
  deleting any `v*/main` branch; the org `branch-protection-ruleset.md` has
  the disable–delete–re-enable runbook (used in cheesy-scribe and forge-ui
  on 2026-10-16).
- **Dependabot targets `main`**, which bypasses the release-branch flow. The
  org pattern (cheesy-scribe CHEESE-53): leave its PRs open against `main`
  and bundle the updates on the release branch before the final bump.
- **Placeholder test.** `test/forge_core_test.dart` exists only because
  `flutter test` fails with no tests. Replace it with real tests in v0.1.0.
- **Supabase extensions.** Confirm `pg_cron`, `pg_net` and Vault are
  available on the real project before the purge migration lands.

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
everything under `lib/src/` (`config/` so far). Tests mirror it under
`test/`. Public names are prefixed `Forge`.

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
with its tests. No RC cut yet: the first one proves the pipeline when FC-3
lands. The ticket map for v0.1.0 is FC-3..FC-12 (see CHEESE-57's 2026-10-18
comment for the order).

## Next actions

1. **v0.1.0** (spec milestone 3), FC tickets in dependency order: FC-3
   client wrapper + session stream (extends `ForgeSupabaseConfig`), FC-4
   Google sign-in, FC-5 email/password, FC-6 identity linking, FC-7
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
- **Supabase extensions.** Confirm `pg_cron`, `pg_net` and Vault are
  available on the real project before the purge migration lands.

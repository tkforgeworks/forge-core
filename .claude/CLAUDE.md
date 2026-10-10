# forge-core — Claude Reference

## What this is

`forge-core` is the public repo for the Flutter package `forge_core`: the
sign-in, account and data plumbing every tkforgeworks app shares, built on
Supabase. Apps consume it as a git dependency pinned to a release tag. Its
sibling `forge-ui` carries the brand look; the two packages never depend on
each other. Current phase: repo setup done and the v1 spec settled
(2026-10-10); no package code yet. The spec is
`docs/forge-ui_forge-core_Shared_Flutter_Packages_Spec.md`. The same file
lives in `forge-ui/docs/`; the two copies must stay identical, so any spec
change lands in both repos together.

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
  `tkforgeworks/.github/.github/workflows/ci-flutter.yml@main`.
  Don't hand-roll steps that belong in the shared workflow — change it there.
- **Commit subjects are the changelog.** Imperative summary; bug fixes start
  with `Fix ...`.
- **No Jira project yet.** A project and key for forge-core are an open item.
  Until one exists, commit subjects carry no ticket key and topic branches are
  `vX.Y.Z/<short-topic>`. Once it exists: subjects become
  `<KEY>-N: Imperative summary`, branches `vX.Y.Z/<KEY>-N-short-topic`, and
  the deviation in `.github/org-standards.yml` is removed.
- Releases: not set up yet. The plan is the org tagless pipeline
  (`release-flutter.yml` with both platform builds off, plus the vendored
  `scripts/release/bump-version.{ps1,sh}`) when `v0.1.0/main` is cut.
  **Never hand-edit the version or push tags** once it is in place.
- License: **Apache-2.0** (`LICENSE` is the verbatim Apache text — never
  edit it). Image assets (`.svg`/`.png`/etc.) are **all rights reserved** via
  `NOTICE`. `pubspec.yaml` has no license field; pub reads `LICENSE`.
  Standard: `tkforgeworks/.github/docs/licensing.md`.
- `.github/org-standards.yml` records the last org standards check and this
  repo's intentional deviations.
- Update this file as the last step of closing any ticket that changed
  conventions, architecture, or status.

## Architecture decisions (locked)

- `forge-core` never depends on `forge-ui` and holds no UI styling; apps wire
  `forge-ui` screen callbacks to `forge-core`. Keeps Supabase out of the UI
  package and styling out of this one.
- No Supabase URL or keys in this repo; the app passes its client in. The
  repo is public and each app owns its own Supabase project.
- Code is promoted into the package only when a second app needs it (rule of
  three), so the package doesn't grow speculative API.
- Every user-owned table's policy is `auth.uid() = user_id and
  forge_account_active()`, so access ends the moment
  `accounts.deletion_requested_at` is set, even for an unexpired token.
- `accounts` rows are created by a trigger on `auth.users`. The client reads
  only its own row and writes only through security-definer functions
  (`request_account_deletion()`, and one that sets `display_name`).
- The purge is attempted when the flag is set and retried by `pg_cron`
  (through `pg_net`) every 15 minutes.
- User files in Storage live under `<bucket>/<user_id>/...`; the purge walks
  every bucket, with no per-app config.
- The Apple refresh token is a Supabase Vault secret; web-deletion
  confirmation tokens are stored hashed in a private schema.
- No sync helper in v1. The web deletion page lives in the website repo;
  this repo ships only the Edge Functions behind it.

## Current status

As of 2026-10-10: org standards setup is on `main` (the `v0.0.1` batch), both
rulesets are active, and `v0.1.0/main` is cut. The package is an empty
skeleton with one placeholder test. The spec pass is done: the owner decided
every gap on 2026-10-10 and the decisions are written into the spec (its
Decisions table lists them).

## Next actions

1. Start v0.1.0 work (spec milestone 3): native Google and Apple sign-in,
   session state, the jsonb repository helper, and the `accounts` table with
   its trigger and `forge_account_active()`. The first topic PR also sets
   `pubspec.yaml` to `0.1.0+1` and adopts the release pipeline (see open
   items).
2. forge-ui v0.2 ships the sign-in screen alongside this repo's v0.1, and
   forge-ui v0.3 the account settings page alongside v0.2, so shape the
   public API with those callbacks in mind.
3. First consumer: the cheese app adopts this package when it adds accounts
   and sync (its epic CHEESE-11), not before. It adopts forge-ui earlier, in
   its 0.1.1 (CHEESE-48).

## Open items (repo and process)

- **Jira project.** None exists for forge-core; the owner will set one up
  later. Then update the conventions above and remove the deviation in
  `.github/org-standards.yml`.
- **Release pipeline.** Adopt at the start of v0.1.0 work, the way forge-ui
  did (its PR #6 is the model): a `release.yml` calling
  `release-flutter.yml@main` with `build-windows: false` and
  `build-android: false`, and the vendored
  `scripts/release/bump-version.{ps1,sh}`. No `ticket-prefix` and no
  `JIRA_BASE_URL`: the input is optional since `tkforgeworks/.github` PR #15,
  and the release notes are then the plain commit subjects. forge-ui's
  `v0.1.0-rc.1` (2026-10-10) proved the workflow with both builds off. Apps
  pin an exact tag; release candidates are for adoption.
- **`v0.0.1/main` still exists.** The `release-branches` ruleset blocks
  deleting any `v*/main` branch, while the org branching doc says to delete
  finished release branches. Removing it means temporarily disabling the
  ruleset; that is the owner's call, and the conflict is worth raising in
  `tkforgeworks/.github`.
- **Dependabot targets `main` by default**, which bypasses the release-branch
  flow. Decide whether to set `target-branch` in `.github/dependabot.yml`
  (the org template does not).
- **Placeholder test.** `test/forge_core_test.dart` exists only because
  `flutter test` fails with no tests. Replace it with real tests in v0.1.0.

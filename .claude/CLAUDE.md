# forge-core — Claude Reference

## What this is

`forge-core` is the public repo for the Flutter package `forge_core`: the
sign-in, account and data plumbing every tkforgeworks app shares, built on
Supabase. Apps consume it as a git dependency pinned to a release tag. Its
sibling `forge-ui` carries the brand look; the two packages never depend on
each other. Current phase: repo setup done, spec being finalized, no package
code yet. The spec is `docs/forge-ui_forge-core_Shared_Flutter_Packages_Spec.md`.

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
  `vX.Y.Z/main` (currently `v0.0.1/main`, a setup-only batch that ships no
  tag; `v0.1.0/main` follows); topic branches PR **into the release branch**,
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

## Current status

Org standards setup landed in the `v0.0.1` batch. Next: work through the open
gaps in the spec and settle the v1 design before any package code is written.

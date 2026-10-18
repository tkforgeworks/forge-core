#!/usr/bin/env bash
# Bumps pubspec.yaml for a release candidate or a stable release and pushes
# the commit; CI does the rest. The pubspec adapter for the org's
# rc-tag.js / release-tag.js. Same behaviour as bump-version.ps1 — keep them
# in step. Canonical copy lives in tkforgeworks/.github/scripts/release/ —
# vendor both files into the consuming repo's scripts/release/.
#
# No git tag is created here — release.yml creates it server-side when it
# publishes, so this works under branch protection.
#
#   rc     On a release branch vX.Y.Z/main: set version to X.Y.Z-rc.N+BUILD
#          (N = one past the highest existing rc tag or the current rc,
#          BUILD = current BUILD + 1), commit "Release candidate X.Y.Z-rc.N",
#          push. CI publishes the prerelease.
#   final  On the release branch: set version to X.Y.Z+BUILD (BUILD + 1),
#          commit "X.Y.Z", push, open the release PR into the default branch
#          if one is not already open. CI cuts the stable release on merge.
#
# The base version comes from the branch name (vX.Y.Z/main) — pubspec.yaml
# carries the upcoming version from the moment the branch is cut, unlike
# package.json in the npm flow, so there is no patch/minor/major to choose.
# Pass a second argument to override the base when the branch is not named
# that way.
#
# Usage: scripts/release/bump-version.sh <rc|final> [X.Y.Z]
set -euo pipefail

mode="${1:-}"
override="${2:-}"
if [[ "$mode" != "rc" && "$mode" != "final" ]]; then
  echo "Usage: $0 <rc|final> [X.Y.Z]" >&2
  exit 1
fi
if [[ -n "$override" && ! "$override" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version override must be X.Y.Z" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
pubspec=pubspec.yaml

branch="$(git rev-parse --abbrev-ref HEAD)"
default_branch="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
default_branch="${default_branch:-main}"
if [[ "$branch" == "$default_branch" ]]; then
  echo "Releases are cut from a release branch (vX.Y.Z/main), never from $default_branch — check out the release branch first" >&2
  exit 1
fi

current="$(sed -n 's/^version:[[:space:]]*//p' "$pubspec" | tr -d '[:space:]')"
if [[ ! "$current" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(-rc\.([0-9]+))?\+([0-9]+)$ ]]; then
  echo "pubspec.yaml version '$current' is not X.Y.Z[-rc.N]+BUILD" >&2
  exit 1
fi
current_base="${BASH_REMATCH[1]}"
current_rc="${BASH_REMATCH[3]:-0}"
build="${BASH_REMATCH[4]}"

if [[ -n "$override" ]]; then
  base="$override"
elif [[ "$branch" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)/main$ ]]; then
  base="${BASH_REMATCH[1]}"
else
  base="$current_base"
fi
build=$((build + 1))

# Tags are created remotely by CI: refresh before numbering the RC.
git fetch --tags --quiet origin || echo "Could not fetch tags — RC numbering uses local tags only" >&2

if [[ "$mode" == "rc" ]]; then
  highest=0
  while IFS= read -r tag; do
    [[ "$tag" =~ -rc\.([0-9]+)$ ]] && (( BASH_REMATCH[1] > highest )) && highest="${BASH_REMATCH[1]}"
  done < <(git tag --list "v$base-rc.*")
  n=$(( (highest > current_rc ? highest : current_rc) + 1 ))
  next="$base-rc.$n"
  message="Release candidate $next"
else
  if [[ -n "$(git tag --list "v$base")" ]]; then
    echo "Tag v$base already exists — $base has shipped" >&2
    exit 1
  fi
  next="$base"
  message="$next"
fi

full="$next+$build"
echo "Bumping $current → $full"
sed -i.bak -E "s/^version:[[:space:]]*.*/version: $full/" "$pubspec" && rm -f "$pubspec.bak"
git add "$pubspec"
git commit -m "$message"

echo "Pushing $branch"
git push -u origin "$branch"

if [[ "$mode" == "rc" ]]; then
  echo "release.yml will build and publish the prerelease (tag v$next is created by CI)"
else
  open="$(gh pr list --head "$branch" --base "$default_branch" --json number --jq length)"
  if (( open > 0 )); then
    echo "Pull request already exists — pushed update"
  else
    echo "Creating pull request into $default_branch"
    gh pr create --base "$default_branch" --title "Release $next" --body "Release $next — merging cuts the stable release."
  fi
fi

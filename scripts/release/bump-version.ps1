#Requires -Version 7
<#
.SYNOPSIS
  Bumps pubspec.yaml for a release candidate or a stable release and pushes
  the commit; CI does the rest. The pubspec adapter for the org's
  rc-tag.js / release-tag.js. Same behaviour as bump-version.sh — keep them
  in step. Canonical copy lives in tkforgeworks/.github/scripts/release/ —
  vendor both files into the consuming repo's scripts/release/.

.DESCRIPTION
  No git tag is created here — release.yml creates it server-side when it
  publishes, so this works under branch protection.

  rc     On a release branch vX.Y.Z/main: set version to X.Y.Z-rc.N+BUILD
         (N = one past the highest existing rc tag or the current rc, BUILD
         = current BUILD + 1), commit "Release candidate X.Y.Z-rc.N", push.
         CI publishes the prerelease.
  final  On the release branch: set version to X.Y.Z+BUILD (BUILD + 1),
         commit "X.Y.Z", push, open the release PR into the default branch
         if one is not already open. CI cuts the stable release on merge.

  The base version comes from the branch name (vX.Y.Z/main) — pubspec.yaml
  carries the upcoming version from the moment the branch is cut, unlike
  package.json in the npm flow, so there is no patch/minor/major to choose.
  Pass -Version to override the base when the branch is not named that way.

.EXAMPLE
  scripts/release/bump-version.ps1 rc
  scripts/release/bump-version.ps1 final
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet('rc', 'final')][string]$Mode,
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $root
$pubspec = Join-Path $root 'pubspec.yaml'

$branch = (git rev-parse --abbrev-ref HEAD).Trim()
$defaultBranch = try {
    (git symbolic-ref --short refs/remotes/origin/HEAD 2>$null) -replace '^origin/', ''
} catch { 'main' }
if (-not $defaultBranch) { $defaultBranch = 'main' }
if ($branch -eq $defaultBranch) {
    throw "Releases are cut from a release branch (vX.Y.Z/main), never from $defaultBranch — check out the release branch first"
}

$current = (Select-String -Path $pubspec -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
if ($current -notmatch '^(\d+\.\d+\.\d+)(?:-rc\.(\d+))?\+(\d+)$') {
    throw "pubspec.yaml version '$current' is not X.Y.Z[-rc.N]+BUILD"
}
$currentBase, $currentRc, $build = $Matches[1], [int]($Matches[2] ?? 0), [int]$Matches[3]

$base = if ($Version) { $Version }
elseif ($branch -match '^v(\d+\.\d+\.\d+)/main$') { $Matches[1] }
else { $currentBase }
$build += 1

# Tags are created remotely by CI: refresh before numbering the RC.
try { git fetch --tags --quiet origin } catch { Write-Warning 'Could not fetch tags — RC numbering uses local tags only' }

if ($Mode -eq 'rc') {
    $highestTagRc = 0
    foreach ($tag in (git tag --list "v$base-rc.*")) {
        if ($tag -match '-rc\.(\d+)$' -and [int]$Matches[1] -gt $highestTagRc) { $highestTagRc = [int]$Matches[1] }
    }
    $next = "$base-rc.$([Math]::Max($highestTagRc, $currentRc) + 1)"
    $message = "Release candidate $next"
} else {
    if (git tag --list "v$base") { throw "Tag v$base already exists — $base has shipped" }
    $next = $base
    $message = $next
}

$full = "$next+$build"
Write-Host "Bumping $current → $full"
(Get-Content $pubspec -Raw) -replace '(?m)^version:\s*\S+', "version: $full" |
    Set-Content -Path $pubspec -NoNewline
git add pubspec.yaml
git commit -m $message
if ($LASTEXITCODE) { throw 'git commit failed' }

Write-Host "Pushing $branch"
git push -u origin $branch
if ($LASTEXITCODE) { throw 'git push failed' }

if ($Mode -eq 'rc') {
    Write-Host "release.yml will build and publish the prerelease (tag v$next is created by CI)"
} else {
    $open = gh pr list --head $branch --base $defaultBranch --json number --jq length
    if ([int]$open -gt 0) {
        Write-Host 'Pull request already exists — pushed update'
    } else {
        Write-Host "Creating pull request into $defaultBranch"
        gh pr create --base $defaultBranch --title "Release $next" --body "Release $next — merging cuts the stable release."
        if ($LASTEXITCODE) { throw 'gh pr create failed' }
    }
}

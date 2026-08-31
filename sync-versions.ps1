<#
.SYNOPSIS
    Regenerates versions.json from every resource's own fxmanifest.lua -
    fxmanifest.lua stays the single source of truth for a resource's
    version, this script just mirrors it into the shared manifest so the
    two can never silently drift apart.

.DESCRIPTION
    Run this after bumping any resource's `version` in fxmanifest.lua.
    It scans ..\tebex for folders containing a fxmanifest.lua - both
    immediate children and one level inside a grouping folder such as
    tebex/inventory - pulls each
    `version '...'` string, and writes versions.json keyed by
    the FOLDER name (not the manifest's own `name` field - folder name is
    what GetCurrentResourceName() actually returns at runtime, which is
    what every resource's version_check.lua looks itself up by).

    Prints a summary of what changed (added/bumped/removed) so you can
    see at a glance what a `git push` would actually publish. Does NOT
    touch git itself - see push-versions.ps1 (or the README) for that
    part once git/gh are available in this environment.

.EXAMPLE
    ./sync-versions.ps1
#>

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$tebexDir = Join-Path (Split-Path $scriptDir -Parent) 'tebex'
$manifestPath = Join-Path $scriptDir 'versions.json'

if (-not (Test-Path -LiteralPath $tebexDir)) {
    throw "Could not find tebex/ next to version-check-manifest/ (looked at: $tebexDir)"
}

$oldVersions = @{}
if (Test-Path -LiteralPath $manifestPath) {
    $oldJson = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($prop in $oldJson.PSObject.Properties) {
        $oldVersions[$prop.Name] = $prop.Value
    }
}

$newVersions = [ordered]@{}
$skipped = @()

# Resources are not all immediate children of tebex/ - some are grouped a
# level deeper (tebex/inventory/cobra-inventory, tebex/inventory/qb-inventory,
# tebex/inventory/qs-inventory). Scanning only the top level silently DROPPED
# those from versions.json on every run, since a key that is not rediscovered
# is treated as removed.
#
# So: any directory up to two levels under tebex/ that actually contains a
# fxmanifest.lua is a resource. A grouping folder (no manifest of its own) is
# not reported as skipped - it was never a resource to begin with.
$resourceDirs = @()
Get-ChildItem -LiteralPath $tebexDir -Directory | ForEach-Object {
    if (Test-Path -LiteralPath (Join-Path $_.FullName 'fxmanifest.lua')) {
        $resourceDirs += $_
    } else {
        # Grouping folder - look one level in.
        Get-ChildItem -LiteralPath $_.FullName -Directory | ForEach-Object {
            if (Test-Path -LiteralPath (Join-Path $_.FullName 'fxmanifest.lua')) {
                $resourceDirs += $_
            }
        }
    }
}

$resourceDirs | Sort-Object Name | ForEach-Object {
    $resourceName = $_.Name
    if ($resourceName -eq 'vendor-original-reference-DO-NOT-SHIP') { return }

    $fxPath = Join-Path $_.FullName 'fxmanifest.lua'

    $content = Get-Content -LiteralPath $fxPath -Raw
    # Anchored to start-of-line so this matches `version '1.2.0'` but not
    # `fx_version 'cerulean'` (an unanchored match would catch the tail
    # end of "fx_version" too, since it also ends in "version '...'").
    $match = [regex]::Match($content, "(?m)^version\s+'([^']+)'")
    if (-not $match.Success) {
        $skipped += "$resourceName (no version '...' line found)"
        return
    }

    $newVersions[$resourceName] = $match.Groups[1].Value
}

# ---- Diff summary ----
$added     = @()
$bumped    = @()
$unscanned = @()

foreach ($key in $newVersions.Keys) {
    if (-not $oldVersions.ContainsKey($key)) {
        $added += "  + $key -> $($newVersions[$key])"
    } elseif ($oldVersions[$key] -ne $newVersions[$key]) {
        $bumped += "  ~ $key -> $($oldVersions[$key]) -> $($newVersions[$key])"
    }
}
# Keys this scan did not find are REPORTED, never deleted.
#
# Not every resource lives under tebex/ - a dozen of them (cobra-fire,
# cobra-robbery, cobra-justice, cobra-callouts and friends) sit directly in
# the parent folder, and others are not on this machine at all. An earlier
# version of this script rebuilt versions.json from the scan alone, which
# silently dropped all of them and downgraded cobra-notify to the version of
# an unrelated copy that happened to be under tebex/.
#
# So the manifest is MERGED, not regenerated: a scanned version wins for
# resources that were found, and everything else is carried through
# untouched. Removing a resource is a deliberate act - edit versions.json
# by hand.
foreach ($key in $oldVersions.Keys) {
    if (-not $newVersions.Contains($key)) {
        $unscanned += "  . $key (kept at $($oldVersions[$key]) - not found under tebex/)"
        $newVersions[$key] = $oldVersions[$key]
    }
}

# Keep the file's alphabetical order stable now that carried-through keys
# have been appended to the end of the scan results.
$sorted = [ordered]@{}
foreach ($key in ($newVersions.Keys | Sort-Object)) { $sorted[$key] = $newVersions[$key] }
$newVersions = $sorted

# ---- Write file (only if something actually changed) ----
$changed = ($added.Count -gt 0) -or ($bumped.Count -gt 0)

if ($changed) {
    $json = $newVersions | ConvertTo-Json -Depth 2
    # Windows PowerShell 5.1's Set-Content has no utf8NoBOM option (that's
    # PS7+ only) and plain 'UTF8' writes a BOM, which some JSON parsers
    # choke on - write via .NET directly instead for a clean BOM-less file.
    [System.IO.File]::WriteAllText($manifestPath, $json, (New-Object System.Text.UTF8Encoding $false))
    Write-Output "versions.json updated ($($newVersions.Count) resource(s)):"
    $added  | ForEach-Object { Write-Output $_ }
    $bumped | ForEach-Object { Write-Output $_ }
} else {
    Write-Output "versions.json already up to date ($($newVersions.Count) resource(s)) - no changes."
}

if ($unscanned.Count -gt 0) {
    Write-Output ""
    Write-Output "Carried through unchanged (not found under tebex/):"
    $unscanned | ForEach-Object { Write-Output $_ }
}

if ($skipped.Count -gt 0) {
    Write-Output ""
    Write-Output "Skipped (no version found):"
    $skipped | ForEach-Object { Write-Output "  ! $_" }
}

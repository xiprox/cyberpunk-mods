# Zips a mod for release: runs the mod's own tools/stage.ps1, which builds, tests, and lays the mod out as the game folder
# is, then zips that layout as <zip>-<version>.zip, with "zip" from the mod's release.json. The release workflow runs it
# too, so a zip made here is the zip a release ships.
#   powershell -File tools/package-mod.ps1 -Mod headset
param(
    [Parameter(Mandatory = $true)][string]$Mod,
    [string]$Version,
    [string]$OutDir
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root "mods\$Mod"
$meta = Get-Content (Join-Path $dir 'release.json') -Raw | ConvertFrom-Json
if (-not $Version) { $Version = (Get-Content (Join-Path $dir 'version.txt') -TotalCount 1).Trim() }
if (-not $OutDir) { $OutDir = Join-Path $dir 'build\package' }

$stage = Join-Path $dir 'build\package-stage'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
& (Join-Path $dir 'tools\stage.ps1') -Out $stage

New-Item -ItemType Directory -Force $OutDir | Out-Null
$zip = Join-Path (Resolve-Path $OutDir) "$($meta.zip)-$Version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
# Windows' own tar writes forward slashes, which Linux tools need; the tar Git puts on PATH can't make a zip.
$top = @(Get-ChildItem $stage | ForEach-Object Name)
& "$env:SystemRoot\System32\tar.exe" -a -cf $zip -C $stage @top
if ($LASTEXITCODE -ne 0) { throw 'tar failed' }
$zip

# Links the game's CET mods folder to this repository's cet/NightCoopTweaks
# (a directory junction, no admin needed), so an edit here is in the game after
# CET's "Reload All Mods". -Unlink takes the link away and leaves the files here.
param(
    [string]$Game = "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077",
    [switch]$Unlink
)
$ErrorActionPreference = 'Stop'

$source = (Resolve-Path (Join-Path $PSScriptRoot "..\cet\NightCoopTweaks")).Path
$mods = Join-Path $Game "bin\x64\plugins\cyber_engine_tweaks\mods"
$link = Join-Path $mods "NightCoopTweaks"

if (-not (Test-Path $mods)) {
    throw "No CET mods folder at $mods. Pass -Game with your game folder."
}

$existing = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
$isOurs = $existing -and $existing.LinkType -eq 'Junction' -and (@($existing.Target)[0] -eq $source)

if ($Unlink) {
    if (-not $existing) { "Not linked: $link"; return }
    if (-not $isOurs) { throw "$link isn't a link to $source; left alone." }
    # Removes the junction itself; the files it points at stay.
    [System.IO.Directory]::Delete($link, $false)
    "Unlinked $link"
    return
}

if ($isOurs) { "Already linked: $link -> $source"; return }
if ($existing) { throw "$link already exists and isn't a link to $source; move it away first." }

New-Item -ItemType Junction -Path $link -Target $source | Out-Null
"Linked $link -> $source"

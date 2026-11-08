# Installs the mod (mod\) and the dev harness (dev\) into the game, only with the game closed. -ModOnly leaves the
# dev harness out. Partners never get dev\: the crew gets the mod's three folders through the log collector's Mods
# tab (RECORD.md, 2026-11-06 evening), listed at the end.
param([switch]$ModOnly)
$ErrorActionPreference = 'Stop'
$g = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077'
$p = Split-Path -Parent $PSScriptRoot
if (Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue) {
    throw "The game is running: close it first."
}
$roots = if ($ModOnly) { @('mod') } else { @('mod', 'dev') }
foreach ($root in $roots) {
    # Only the game's own folders: dev\ also holds runs\ and captures\.
    Get-ChildItem "$p\$root" -Directory | Where-Object { 'bin', 'r6', 'archive', 'red4ext' -contains $_.Name } | ForEach-Object {
        Copy-Item $_.FullName $g -Recurse -Force
    }
    "installed $root\"
}
# The twin looks moved into archive\pc\mod\vehiclecustomizer\ (2026-11-06 evening); loose copies would load twice.
foreach ($rel in 'archive\pc\mod\vehiclecustomizer.archive', 'archive\pc\mod\vehiclecustomizer.archive.xl') {
    if (Test-Path "$g\$rel") {
        Remove-Item "$g\$rel"
        "removed the loose $rel (it's in archive\pc\mod\vehiclecustomizer\ now)"
    }
}
""
"For the crew, share these three folders in the log collector's Mods tab:"
"  r6\scripts\VehicleCustomizer"
"  r6\tweaks\vehiclecustomizer"
"  archive\pc\mod\vehiclecustomizer"

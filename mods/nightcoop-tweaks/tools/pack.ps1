# Zips cet/NightCoopTweaks into dist/NightCoopTweaks-<version>.zip, laid out as
# the game folder is, so a partner extracts it into their Cyberpunk 2077 folder.
# The version is VERSION in init.lua. Files CET writes next to the mod (logs,
# its database) stay out.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$source = Join-Path $repo "cet\NightCoopTweaks"
$version = [regex]::Match((Get-Content -Raw (Join-Path $source "init.lua")), 'local VERSION = "([^"]+)"').Groups[1].Value
if (-not $version) { throw "No VERSION in init.lua" }
$dist = Join-Path $repo "dist"
$out = Join-Path $dist "NightCoopTweaks-$version.zip"
$prefix = "bin/x64/plugins/cyber_engine_tweaks/mods/NightCoopTweaks/"
$skip = '\.log$|^db\.sqlite3$|^settings\.json$'

New-Item -ItemType Directory -Force $dist | Out-Null
if (Test-Path $out) {
    Remove-Item -LiteralPath $out
    "Replacing ${out}: raise VERSION in init.lua if friends already have this one"
}

$zip = [System.IO.Compression.ZipFile]::Open($out, 'Create')
try {
    Get-ChildItem -LiteralPath $source -Recurse -File | Where-Object { $_.Name -notmatch $skip } | ForEach-Object {
        # Forward slashes: zips with backslash paths unpack wrong in some mod managers
        $entry = $prefix + $_.FullName.Substring($source.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entry) | Out-Null
        $entry
    }
}
finally {
    $zip.Dispose()
}
"Wrote $out"

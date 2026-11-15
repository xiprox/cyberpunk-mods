# Builds NightCoop Voice, runs its tests, and lays it out in -Out as the game folder is, for tools/package-mod.ps1 at
# the root to zip. The release workflow runs the same script, so a release ships what passed here.
#   powershell -File tools/stage.ps1 -Out build/package-stage
param([Parameter(Mandatory = $true)][string]$Out)
$ErrorActionPreference = 'Stop'
$mod = Split-Path -Parent $PSScriptRoot
$build = Join-Path $mod 'build'

& (Join-Path $mod 'tools\fetch_deps.ps1')
& (Join-Path $mod '..\..\tools\fetch-red4ext-sdk.ps1') | Out-Null
# No -G, so a fresh build folder gets the newest Visual Studio; an existing one keeps its own.
cmake -S $mod -B $build -A x64
if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed' }
cmake --build $build --config Release --target voice_test NightCoopVoice
if ($LASTEXITCODE -ne 0) { throw 'build failed' }
# GitHub's build machines, which set CI, have no audio devices, so there the tests that open them are skipped.
$testArguments = if ($env:CI) { @('--no-devices') } else { @() }
& (Join-Path $build 'Release\voice_test.exe') @testArguments
if ($LASTEXITCODE -ne 0) { throw 'voice_test failed' }
cmake --install $build --config Release --prefix $Out
if ($LASTEXITCODE -ne 0) { throw 'CMake install failed' }

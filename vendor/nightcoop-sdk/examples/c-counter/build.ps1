# Builds counter.cpp into build\NightCoopCounterExample.dll with MSVC (cl.exe from a Visual Studio 2022 x64 environment).
#
#   .\build.ps1 -Red4extSdk C:\src\RED4ext.SDK\include
#   .\build.ps1 -Red4extSdk C:\src\RED4ext.SDK\include -NightCoopSdk C:\src\nightcoop\sdk\include
#
# -Red4extSdk   the include folder of RED4ext.SDK (the one that contains the RED4ext\ folder). The SDK is header only.
# -NightCoopSdk the folder with nightcoop_sdk.h (default: ..\..\include, next to this example)
# -OutDir       where the dll goes (default: .\build)
param(
    [Parameter(Mandatory = $true)][string]$Red4extSdk,
    [string]$NightCoopSdk = (Join-Path $PSScriptRoot '..\..\include'),
    [string]$OutDir = (Join-Path $PSScriptRoot 'build'),
    [string]$Name = 'NightCoopCounterExample'
)

$ErrorActionPreference = 'Stop'

$Red4extSdk = (Resolve-Path $Red4extSdk).Path
$NightCoopSdk = (Resolve-Path $NightCoopSdk).Path
if (-not (Test-Path (Join-Path $Red4extSdk 'RED4ext\RED4ext.hpp'))) {
    throw "RED4ext\RED4ext.hpp not found in $Red4extSdk (pass the include folder of RED4ext.SDK)"
}
if (-not (Test-Path (Join-Path $NightCoopSdk 'nightcoop_sdk.h'))) {
    throw "nightcoop_sdk.h not found in $NightCoopSdk"
}

# Visual Studio's environment (vcvars64.bat) through vswhere.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found: install Visual Studio 2022 with the C++ workload' }
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) { throw 'No Visual Studio with the C++ x64 tools found' }
$vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

# The GPU headers of RED4ext.SDK want D3D12MemAlloc, which sits next to its include folder.
$includes = @("/I`"$Red4extSdk`"", "/I`"$NightCoopSdk`"")
$vendor = Join-Path (Split-Path $Red4extSdk -Parent) 'vendor\D3D12MemAlloc'
if (Test-Path $vendor) { $includes += "/I`"$vendor`"" }

$source = Join-Path $PSScriptRoot 'counter.cpp'
$dll = Join-Path $OutDir "$Name.dll"
$cl = "cl.exe /nologo /std:c++20 /EHsc /O2 /MD /utf-8 /DWIN32_LEAN_AND_MEAN /DNOMINMAX /LD $($includes -join ' ') " +
      "`"$source`" /Fo`"$OutDir\\`" /Fe`"$dll`" /link /INCREMENTAL:NO"

# A small batch file keeps the quoting simple: set up the compiler environment, then compile.
$bat = Join-Path $OutDir 'build-temp.cmd'
Set-Content -Path $bat -Value @('@echo off', "call `"$vcvars`" >nul", $cl) -Encoding ASCII
try {
    & cmd.exe /c $bat
    if ($LASTEXITCODE -ne 0) { throw "cl.exe failed with exit code $LASTEXITCODE" }
}
finally {
    Remove-Item $bat -ErrorAction SilentlyContinue
}

Write-Host "Built $dll"

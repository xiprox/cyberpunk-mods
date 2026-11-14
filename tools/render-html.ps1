# Renders an HTML page to a PNG of an exact size with headless Edge, such as a mod's 1300x372 Nexus Mods header.
#   powershell -File tools/render-html.ps1 -Html header.html -Out mods/headset/header.png
param(
    [Parameter(Mandatory = $true)][string]$Html,
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$Width = 1300,
    [int]$Height = 372
)
$ErrorActionPreference = 'Stop'
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw 'Microsoft Edge not found' }
$page = ([Uri](Resolve-Path $Html).Path).AbsoluteUri
$png = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out)
if (Test-Path $png) { Remove-Item -Force $png }

# A profile of its own, or Edge hands the job to an Edge already running and returns before the file exists.
# Gray text smoothing, since ClearType's red and blue edges suit an LCD screen, not an image.
$profileDir = Join-Path ([IO.Path]::GetTempPath()) ("render-html-" + [guid]::NewGuid().ToString('N'))
$arguments = @('--headless=new', '--disable-gpu', '--disable-lcd-text', '--hide-scrollbars', '--no-first-run',
    '--force-device-scale-factor=1', "--window-size=$Width,$Height", '--virtual-time-budget=8000',
    "--user-data-dir=$profileDir", "--screenshot=$png", $page)
Start-Process -FilePath $edge -ArgumentList $arguments -Wait -WindowStyle Hidden
for ($i = 0; $i -lt 20 -and -not (Test-Path $png); $i++) { Start-Sleep -Milliseconds 500 }
Remove-Item -Recurse -Force $profileDir -ErrorAction SilentlyContinue
if (-not (Test-Path $png)) { throw 'Edge wrote no image' }

Add-Type -AssemblyName System.Drawing
$image = [Drawing.Image]::FromFile($png)
"$png, $($image.Width)x$($image.Height)"
$image.Dispose()

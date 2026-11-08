# Screenshots for the Shop scouting window's capture key (scout.lua, Page Down). The key writes
# capture-<time>.json and capture-request.txt into the dev mod's CET folder; this watcher, running beside the game,
# saves the game window as dev/captures/<time>.jpg and moves the JSON next to it. Steam's F12 doesn't work when the
# game is started from its executable, which is how the tools start it.
# Run with: powershell -File tools/capture-watcher.ps1   (waits for the game, stops when it closes)
param([int]$WaitForGameMinutes = 10)

$g = "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
$cet = "$g\bin\x64\plugins\cyber_engine_tweaks\mods\VehicleCustomizerDev"
$out = Join-Path (Split-Path -Parent $PSScriptRoot) "dev\captures"
New-Item -ItemType Directory -Force $out | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CaptureWindow
{
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
'@
[CaptureWindow]::SetProcessDPIAware() | Out-Null

function Save-Capture([string]$stamp) {
    $proc = Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $proc) { "  $stamp no game window"; return }
    $front = [CaptureWindow]::GetForegroundWindow() -eq $proc.MainWindowHandle
    $r = New-Object CaptureWindow+RECT
    [CaptureWindow]::GetWindowRect($proc.MainWindowHandle, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    if ($w -le 0 -or $h -le 0) { "  $stamp game window has no size"; return }
    $full = New-Object System.Drawing.Bitmap $w, $h
    $gr = [System.Drawing.Graphics]::FromImage($full)
    $gr.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size $w, $h))
    # 2048 wide: enough to read a scene, small enough to look at.
    $scale = [Math]::Min(1.0, 2048.0 / $w)
    $small = New-Object System.Drawing.Bitmap ([int]($w * $scale)), ([int]($h * $scale))
    $g2 = [System.Drawing.Graphics]::FromImage($small)
    $g2.InterpolationMode = 'HighQualityBicubic'
    $g2.DrawImage($full, 0, 0, $small.Width, $small.Height)
    $small.Save("$out\$stamp.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $g2.Dispose(); $small.Dispose(); $gr.Dispose(); $full.Dispose()
    "  $stamp.jpg" + $(if (-not $front) { " (the game wasn't in front; the picture may show something else)" } else { "" })
}

"watching $cet for captures; pictures go to $out"
$deadline = (Get-Date).AddMinutes($WaitForGameMinutes)
while (-not (Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue)) {
    if ((Get-Date) -gt $deadline) { "no game started; stopping"; exit }
    Start-Sleep -Seconds 2
}
"game is running"
while (Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue) {
    $req = "$cet\capture-request.txt"
    if (Test-Path $req) {
        $stamp = (Get-Content $req -Raw -ErrorAction SilentlyContinue)
        Remove-Item $req -ErrorAction SilentlyContinue
        if ($stamp) {
            $stamp = $stamp.Trim()
            "$(Get-Date -Format HH:mm:ss) capture $stamp"
            Save-Capture $stamp
            if (Test-Path "$cet\capture-$stamp.json") { Move-Item "$cet\capture-$stamp.json" "$out\$stamp.json" -Force }
        }
    }
    Start-Sleep -Milliseconds 150
}
"game closed; stopping"

# Runs one automated in-game test with nobody at the PC (vehicle-customizer/RECORD.md).
#   powershell -File tools/run-autotest.ps1 -Job dump
# Installs dev/ (and mod/ when it exists) over the game folder, switches the test on for this run only
# (VehicleCustomizerDev.autotest and .job in r6/tweaks/vehiclecustomizerdev/autotest.yaml), launches the game
# through Steam with the start screen skipped, and lets the main menu continue the newest save. The CET runner
# then works through the job and writes autotest-report.txt; whenever it asks for a "SHOT <name>", this script
# saves a picture of the game's window alone (not the rest of the desktop). After "DONE" or the time limit it
# closes the game, takes the test flag out again, and copies the report, pictures and any files the job wrote
# into dev/runs/<time>/. Prints how long loading and the job took and adds that to dev/runs/durations.csv.
# Refuses to start while the game is running.
param(
    [string]$Job = "dump",
    # Handed to the job as VehicleCustomizerDev.arg (job "buy": which cars, and "screen" to buy with the screen open).
    [string]$Arg = "",
    [int]$TimeoutSeconds = 420,
    [switch]$KeepGameOpen
)

$ErrorActionPreference = "Stop"
$g = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077'
$p = Split-Path -Parent $PSScriptRoot
$cet = "$g\bin\x64\plugins\cyber_engine_tweaks\mods\VehicleCustomizerDev"
$flag = "$g\r6\tweaks\vehiclecustomizerdev\autotest.yaml"
$run = Join-Path $p ("dev\runs\" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss") + "_" + $Job)

if (Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue) {
    throw "The game is running; close it first."
}
New-Item -ItemType Directory -Force $run | Out-Null

# Install: the dev harness and the mod; then the flag for this run.
foreach ($root in 'dev', 'mod') {
    if (Test-Path "$p\$root") {
        # Only the game's own folders: dev\ also holds runs\ and captures\.
        Get-ChildItem "$p\$root" -Directory | Where-Object { 'bin', 'r6', 'archive', 'red4ext' -contains $_.Name } | ForEach-Object {
            Copy-Item $_.FullName $g -Recurse -Force
        }
    }
}
# The twin looks moved into archive\pc\mod\vehiclecustomizer\ (2026-11-06 evening); loose copies would load twice.
foreach ($rel in 'archive\pc\mod\vehiclecustomizer.archive', 'archive\pc\mod\vehiclecustomizer.archive.xl') {
    if (Test-Path "$g\$rel") {
        Remove-Item "$g\$rel"
        "removed the loose $rel (it's in archive\pc\mod\vehiclecustomizer\ now)"
    }
}
# The old test (test/) comes out once the mod is in: its service would also take twin rebuilds of any Hella and
# its wrap would refuse resets beside the engine's. Moved into test\removed-from-game\, logs and all, not
# deleted; its TweakXL copies (r6\tweaks\vehiclecustomizertest) stay, so the save keeps those records.
$keep = Join-Path $p "test\removed-from-game"
foreach ($rel in 'r6\scripts\VehicleCustomizerTest', 'bin\x64\plugins\cyber_engine_tweaks\mods\VehicleCustomizerTest',
                 'archive\pc\mod\vehiclecustomizertest.archive', 'archive\pc\mod\vehiclecustomizertest.archive.xl') {
    if (Test-Path "$g\$rel") {
        $dest = Join-Path $keep $rel
        if (Test-Path $dest) { throw "test\removed-from-game already has $rel; look at both before going on." }
        New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
        Move-Item "$g\$rel" $dest
        "moved the old test's $rel out of the game into test\removed-from-game"
    }
}
New-Item -ItemType Directory -Force (Split-Path $flag) | Out-Null
@"
# Written by tools/run-autotest.ps1 for one run; removed when it ends.
VehicleCustomizerDev.autotest: true
VehicleCustomizerDev.job: "$Job"
VehicleCustomizerDev.arg: "$Arg"
"@ | Set-Content -Encoding utf8 $flag
Remove-Item "$cet\autotest-report.txt", "$cet\autotest-go.txt" -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GameWindow
{
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    // Space, down and up, to the game when it is in front: the start screen's and the loading screen's "press to
    // continue" are native, and the game takes keys only while it's in front (2026-11-07: neither window messages nor
    // the game's Session/Loading DebugAutoSkipLoadingTimeout get past it). So the game has to be in front after the
    // save loads; the user keeps it there during a run.
    public static bool TapSpace(IntPtr hWnd)
    {
        SetForegroundWindow(hWnd);
        System.Threading.Thread.Sleep(150);
        if (GetForegroundWindow() != hWnd) return false;
        keybd_event(0x20, 0x39, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(60);
        keybd_event(0x20, 0x39, 2, UIntPtr.Zero);
        return true;
    }
}
'@
[GameWindow]::SetProcessDPIAware() | Out-Null

function Save-Shot([string]$name) {
    $proc = Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $proc) { "  no game window for $name"; return }
    # The game only puts new frames on screen while it's in front: the second suite run's pictures all showed the
    # start screen, the last frame before it lost focus, while the world behind it ran the whole test.
    [GameWindow]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 1500
    # The picture copies the screen where the game's window is, so with another window in front it shows that window
    # and whatever of the game peeks out; that's still worth having (one showed the loading screen's prompt behind the
    # user's window, 2026-11-07), and the user doesn't mind.
    if ([GameWindow]::GetForegroundWindow() -ne $proc.MainWindowHandle) { "  the game isn't in front for $name; the picture shows what's in front of it" }
    $r = New-Object GameWindow+RECT
    [GameWindow]::GetWindowRect($proc.MainWindowHandle, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    if ($w -le 0 -or $h -le 0) { "  game window has no size for $name"; return }
    $full = New-Object System.Drawing.Bitmap $w, $h
    $gr = [System.Drawing.Graphics]::FromImage($full)
    $gr.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size $w, $h))
    # Scaled to 2048 wide, enough to see a car and small enough to read back.
    $scale = [Math]::Min(1.0, 2048.0 / $w)
    $small = New-Object System.Drawing.Bitmap ([int]($w * $scale)), ([int]($h * $scale))
    $g2 = [System.Drawing.Graphics]::FromImage($small)
    $g2.InterpolationMode = 'HighQualityBicubic'
    $g2.DrawImage($full, 0, 0, $small.Width, $small.Height)
    $safe = ($name -replace '[^A-Za-z0-9_.-]', '_')
    $small.Save("$run\$safe.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
    # And the middle of the view at full resolution, where the suite puts the car.
    $cw = [int]($w * 0.4); $ch = [int]($h * 0.6)
    $close = $full.Clone((New-Object System.Drawing.Rectangle ([int](($w - $cw) / 2)), ([int]($h * 0.25)), $cw, $ch), $full.PixelFormat)
    $close.Save("$run\${safe}_close.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $close.Dispose(); $g2.Dispose(); $small.Dispose(); $gr.Dispose(); $full.Dispose()
    "  shot $safe.jpg"
}

"launching for job '$Job' at $(Get-Date -Format HH:mm:ss); run folder $run"
# Straight from the executable, with Steam already running: a steam://run link with arguments made Steam
# drop the launch (first run, 2026-11-06), and -skipStartScreen spares the "press any key" screen.
Start-Process "$g\bin\x64\Cyberpunk2077.exe" -ArgumentList "-skipStartScreen" -WorkingDirectory "$g\bin\x64"
$start = Get-Date
$seen = 0
$done = $false
$continued = $false
$started = $false
$loadedAt = $null
$doneAt = $null
$result = ""
$nextStartupShot = 45
$nextTap = 20
while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
    Start-Sleep -Seconds 1
    $elapsed = [int]((Get-Date) - $start).TotalSeconds
    $report = "$cet\autotest-report.txt"
    # Only lines the runner has finished: an empty or half-written file isn't read yet.
    $lines = if ((Test-Path $report) -and (Get-Item $report).Length -gt 0) { @(Get-Content $report) } else { @() }
    for ($i = $seen; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        "  $line"
        # Case matters: "done waiting for ..." in a step's line once passed for the end (first suite run).
        if ($line -cmatch '^\d\d:\d\d:\d\d SHOT (.+)$') { Save-Shot $Matches[1] }
        if ($line -cmatch '^\d\d:\d\d:\d\d DONE (.*)$') { $done = $true; $doneAt = Get-Date; $result = $Matches[1] }
        if ($line -cmatch '^\d\d:\d\d:\d\d (main menu continued|a save loaded|world loaded)') { $continued = $true }
        if ($line -cmatch '^\d\d:\d\d:\d\d world loaded' -and -not $started) { $started = $true; $loadedAt = Get-Date }
    }
    $seen = $lines.Count
    if ($done) { break }
    # A tap of Space every 5 s past the start screen, then every 3 s past the end of the loading screen, which
    # also waits for a key ("press to continue") while the world already runs behind it: the first suite runs
    # tested a car nobody could see. Stops when the job starts; in the world a tap is a jump. A tap reaches the game
    # only while it's in front, so a run needs the game in front after the save loads (TapSpace).
    if (-not $started -and $elapsed -ge $nextTap) {
        $nextTap = $elapsed + $(if ($continued) { 3 } else { 5 })
        $proc = Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if ($proc) {
            $ok = [GameWindow]::TapSpace($proc.MainWindowHandle)
            "  tapped Space at $elapsed s" + $(if ($ok) { "" } else { " (the game wasn't in front; skipped)" })
        }
    }
    # By 40 s the taps have closed the start screen (it was gone by 45 s in every run); the game can't tell
    # scripts so, so this file does, and the runner lets the main menu press Continue.
    if (-not $continued -and $elapsed -ge 40 -and -not (Test-Path "$cet\autotest-go.txt")) {
        Set-Content -Path "$cet\autotest-go.txt" -Value "start screen gone" -Encoding ascii
        "  told the runner the start screen is gone at $elapsed s"
    }
    # Until the save has loaded, a picture every 45 s shows where startup is.
    if (-not $continued -and $elapsed -ge $nextStartupShot) {
        Save-Shot ("startup_" + $elapsed + "s")
        $nextStartupShot += 45
    }
    if (-not (Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue) -and $elapsed -gt 60) {
        "  the game is gone (closed or crashed) after $elapsed s"
        break
    }
}
if (-not $done) {
    "TIMED OUT or stopped before DONE"
    Save-Shot "end"
}

if (-not $KeepGameOpen) {
    Start-Sleep -Seconds 2
    Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue | Stop-Process -Force
    $w = 0; while ((Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue) -and $w -lt 30) { Start-Sleep 1; $w++ }
    Remove-Item $flag, "$cet\autotest-go.txt" -ErrorAction SilentlyContinue
    "game closed; test flag removed"
} else {
    # The game read the flag at startup, so taking the file away now only keeps the next launch a normal one.
    Remove-Item $flag, "$cet\autotest-go.txt" -ErrorAction SilentlyContinue
    $proc = Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($proc) { [GameWindow]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null }
    "game left open and in front; test flag file removed (this session still runs with it: the save lock stays unless the job lifted it)"
}
foreach ($f in Get-ChildItem $cet -File | Where-Object { $_.Name -match '^autotest-report\.txt$|\.jsonl$' }) {
    Copy-Item $f.FullName $run -Force
}
# The game's own logs of this launch: script compile and the engine's notes, the catalog's flats, the archive.
foreach ($log in 'r6\logs\redscript_rCURRENT.log', 'bin\x64\plugins\cyber_engine_tweaks\cyber_engine_tweaks.log') {
    if (Test-Path "$g\$log") { Copy-Item "$g\$log" $run -Force }
}
# NightCoop's log (the engine's notes as they came, written live) and its crash log (a crash's place and stack).
foreach ($log in 'red4ext\plugins\NightCoop\nightcoop.log', 'red4ext\plugins\NightCoop\nightcoop-crash.log') {
    if ((Test-Path "$g\$log") -and (Get-Item "$g\$log").LastWriteTime -ge $start) { Copy-Item "$g\$log" $run -Force }
}
foreach ($dir in 'red4ext\plugins\TweakXL', 'red4ext\plugins\ArchiveXL') {
    Get-ChildItem "$g\$dir" -Filter *.log -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $start } |
        ForEach-Object { Copy-Item $_.FullName $run -Force }
}
"report and files in $run"

# How long it took, printed and added to dev\runs\durations.csv (one line per run), so any job's usual time can be
# looked up. "load" is launch to the world loaded (with the loading screen's key), "job" is the world loaded to
# DONE (with any wait for the user, like the session job's for hosting), "total" is launch to everything copied.
function Span($a, $b) { if ($a -and $b) { [int]($b - $a).TotalSeconds } else { $null } }
function Words($s) { if ($null -eq $s) { "?" } elseif ($s -ge 60) { "{0} min {1} s" -f [int][Math]::Floor($s / 60), ($s % 60) } else { "$s s" } }
$loadSecs = Span $start $loadedAt
$jobSecs = Span $loadedAt $doneAt
$totalSecs = Span $start (Get-Date)
"took $(Words $totalSecs) in all: $(Words $loadSecs) to load the save, $(Words $jobSecs) for the job"
[pscustomobject]@{
    started = $start.ToString("yyyy-MM-dd HH:mm:ss")
    job     = $Job
    arg     = $Arg
    result  = $(if ($done) { $result } else { "timed out or stopped" })
    load_s  = $loadSecs
    job_s   = $jobSecs
    total_s = $totalSecs
} | Export-Csv -Path (Join-Path $p "dev\runs\durations.csv") -Append -NoTypeInformation -Encoding UTF8

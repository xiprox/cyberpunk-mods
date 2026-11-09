# Compiles one mod's redscript beside the installed mods, on a separate hidden desktop, so an error dialog from scc
# can't appear over the running game. The game's own cache isn't touched: the output goes to the temp folder.
#   powershell -File tools/check-scripts.ps1 -Mod nightcoop-voice
param(
    [Parameter(Mandatory = $true)][ValidateSet('nightcoop-voice', 'vehicle-customizer', 'headset')][string]$Mod,
    [int]$Seconds = 90
)
$g = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077'
$p = Join-Path (Split-Path -Parent $PSScriptRoot) "mods\$Mod"
$s = Join-Path $env:TEMP "cp77-scc-$Mod"
New-Item -ItemType Directory -Force $s | Out-Null
# scc builds on the game's own script cache, which it expects to find in the cache folder it's given.
Copy-Item "$g\r6\cache\final.redscripts" "$s\final.redscripts" -Force
Copy-Item "$g\r6\cache\final.redscripts" "$s\final.redscripts.bk" -Force

# Each mod's script folders are compiled from the source here and their installed copies skipped, so the source is
# what's checked. $warn picks which warnings to show: the installed mods' own are noise when checking this one.
$ours = @()
$skipPlugins = @()
$warn = 'WARN'
switch ($Mod) {
    'nightcoop-voice' {
        $ours = @(Get-Item "$p\game\scripts")
        $skipPlugins = @('NightCoopVoice')
        $warn = 'WARN.*NightCoopVoice|NightCoopVoice.*(error|WARN)'
    }
    'headset' {
        $ours = @(Get-Item "$p\game\scripts")
        $skipPlugins = @('Headset')
        $warn = 'WARN.*HeadsetNative|HeadsetNative.*(error|WARN)'
    }
    'vehicle-customizer' {
        foreach ($root in 'test', 'dev', 'mod') {
            if (Test-Path "$p\$root\r6\scripts") { $ours += Get-ChildItem "$p\$root\r6\scripts" -Directory }
        }
    }
}
$names = $ours | ForEach-Object Name
$pluginRoot = "$g\red4ext\plugins\"
$list = @(Get-ChildItem "$g\red4ext\plugins" -Recurse -Filter *.reds | Where-Object {
    $skipPlugins -notcontains ($_.FullName.Substring($pluginRoot.Length) -split '\\')[0]
} | ForEach-Object FullName)
$list += Get-ChildItem "$g\r6\scripts" -Directory | Where-Object { $names -notcontains $_.Name } | ForEach-Object FullName
$list += Get-ChildItem "$g\r6\scripts" -File -Filter *.reds | ForEach-Object FullName
$list += $ours | ForEach-Object FullName
$paths = "$s\paths.txt"
[IO.File]::WriteAllLines($paths, [string[]]$list)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class HiddenRun
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO
    {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION
    {
        public IntPtr hProcess, hThread;
        public int dwProcessId, dwThreadId;
    }

    [DllImport("user32", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateDesktopW(string name, IntPtr device, IntPtr mode, int flags, uint access, IntPtr attributes);
    [DllImport("user32", SetLastError = true)]
    static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string app, string command, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env,
        string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32", SetLastError = true)]
    static extern uint WaitForSingleObject(IntPtr handle, uint ms);
    [DllImport("kernel32", SetLastError = true)]
    static extern bool GetExitCodeProcess(IntPtr handle, out uint code);
    [DllImport("kernel32", SetLastError = true)]
    static extern bool TerminateProcess(IntPtr handle, uint code);
    [DllImport("kernel32", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);

    public static string Run(string name, string app, string command, string dir, int seconds)
    {
        const uint GENERIC_ALL = 0x10000000;
        IntPtr desktop = CreateDesktopW(name, IntPtr.Zero, IntPtr.Zero, 0, GENERIC_ALL, IntPtr.Zero);
        if (desktop == IntPtr.Zero) return "no desktop, error " + Marshal.GetLastWin32Error();
        try
        {
            var si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            si.lpDesktop = name;
            PROCESS_INFORMATION pi;
            if (!CreateProcessW(app, command, IntPtr.Zero, IntPtr.Zero, false, 0x08000000, IntPtr.Zero, dir, ref si, out pi))
                return "could not start, error " + Marshal.GetLastWin32Error();
            string result;
            if (WaitForSingleObject(pi.hProcess, (uint)seconds * 1000u) == 0)
            {
                uint code;
                GetExitCodeProcess(pi.hProcess, out code);
                result = "exit code " + code;
            }
            else
            {
                TerminateProcess(pi.hProcess, 1);
                result = "TIMED OUT, which usually means an error dialog: read the log";
            }
            CloseHandle(pi.hThread);
            CloseHandle(pi.hProcess);
            return result;
        }
        finally
        {
            CloseDesktop(desktop);
        }
    }
}
'@

$scc = "$g\engine\tools\scc.exe"
$empty = Join-Path $s 'empty'
New-Item -ItemType Directory -Force $empty | Out-Null
$cmd = "`"$scc`" -compile `"$empty`" -customCacheDir `"$s`" -compilePathsFile `"$paths`""
"scc: " + [HiddenRun]::Run('cp77_scc_check_' + ($Mod -replace '-', '_'), $scc, $cmd, "$g\engine\tools", $Seconds)
"--- log"
Get-Content "$s\logs\redscript_rCURRENT.log" -Tail 400 | Select-String -Pattern "ERROR|$warn|Compilation complete|Output successfully|failed" | Select-Object -Last 25 | ForEach-Object { $_.Line }

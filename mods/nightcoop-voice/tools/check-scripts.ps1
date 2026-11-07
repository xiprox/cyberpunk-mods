# Compiles the mod's scripts beside the installed mods, on a separate hidden desktop, so an error dialog from scc can't
# appear over the running game. The game's own cache isn't touched: the output goes to the temp folder.
param([int]$Seconds = 90)
$g = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077'
$p = Split-Path -Parent $PSScriptRoot
$s = Join-Path $env:TEMP 'nightcoop-voice-scc'
New-Item -ItemType Directory -Force $s | Out-Null
$list = Get-ChildItem "$g\red4ext\plugins" -Recurse -Filter *.reds | Where-Object { $_.FullName -notmatch '\\NightCoopVoice\\' } | ForEach-Object FullName
$list += "$p\game\scripts"
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

    public static string Run(string app, string command, string dir, int seconds)
    {
        const uint GENERIC_ALL = 0x10000000;
        const string name = "nightcoop_voice_check";
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
$cmd = "`"$scc`" -compile `"$g\r6\scripts`" -customCacheDir `"$s`" -compilePathsFile `"$paths`""
"scc: " + [HiddenRun]::Run($scc, $cmd, "$g\engine\tools", $Seconds)
"--- log"
Get-Content "$g\r6\logs\redscript_rCURRENT.log" -Tail 400 | Select-String -Pattern 'ERROR|WARN.*NightCoopVoice|NightCoopVoice.*(error|WARN)|Compilation complete|Output successfully|failed' | Select-Object -Last 25 | ForEach-Object { $_.Line }

# ASoftware watchOS: the automatic quick save, as the Android app's for iOS 26 (AutoSave.java).
# Start-watchOS.ps1 starts it, hidden, after a cold start with quick boot on, on a disk with no save yet
# (a save already there is the way back, and only closing the window replaces it). After a start the watch
# works through its own start-up (the face after about 6 to 9 minutes, longer the first time), and its
# slow first minutes are not worth booting through again. Once the face is on the screen (a QMP
# screendump bigger than -FaceBytes: the Apple logo is 3.4 KB, a face 22-30 KB) for -FaceSeconds, at
# least -MinSeconds after the start, and nobody is using the watch (its window not in front, or no
# mouse or keyboard input on this PC for -IdleSeconds), it saves the machine as the quick boot state,
# asoft-quick, as closing the window does. A start after a crash, a forced stop or a power cut then
# goes on from a settled watch instead of a cold start. Once per cold start; it ends when QEMU ends.
# (QEMU's CPU use is no sign of settling on the watch: measured 2.7-3.6 of 4 cores both before the
# face and 138 minutes after the start.) What it did: -Log.
param(
    [Parameter(Mandatory = $true)][int]$QemuPid,
    [string]$Disk = '',
    [string]$Log = '',
    [int]$QmpPort = 4473,
    [int]$MinSeconds = 900,
    [int]$FaceSeconds = 300,
    [int]$FaceBytes = 12000,
    [int]$Every = 30,
    [int]$IdleSeconds = 120,
    # GB a saved state takes on the disk's drive (measured: 3.74 GiB): the save is skipped without that plus 1 GB free
    [double]$StateGB = 4.0
)
$ErrorActionPreference = 'Stop'
function Note([string]$text) {
    $line = "$(Get-Date -Format s) $text"
    if ($Log) { try { Add-Content -Path $Log -Value $line -Encoding UTF8 } catch { } } else { Write-Host $line }
}
Add-Type -Namespace ASoft -Name WatchIdle -MemberDefinition @'
[DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
[StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
[DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
/// <summary>ms since the last mouse or keyboard input on this PC's session</summary>
public static uint IdleMs() {
    LASTINPUTINFO i = new LASTINPUTINFO(); i.cbSize = (uint)Marshal.SizeOf(i);
    return GetLastInputInfo(ref i) ? unchecked((uint)Environment.TickCount - i.dwTime) : 0;
}
/// <summary>the process whose window is in front (0: none)</summary>
public static uint ForegroundPid() { uint p = 0; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; }
'@
# One QMP command, its "return" (as JSON) or error as text; $null when QMP did not answer
function Qmp([hashtable]$cmd, [int]$timeoutMs = 15000) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $QmpPort)
        $c.ReceiveTimeout = $timeoutMs; $c.SendTimeout = 15000
        try {
            $r = New-Object System.IO.StreamReader($c.GetStream())
            $w = New-Object System.IO.StreamWriter($c.GetStream()); $w.AutoFlush = $true
            [void]$r.ReadLine()
            $w.WriteLine('{"execute":"qmp_capabilities"}'); [void]$r.ReadLine()
            $w.WriteLine(($cmd | ConvertTo-Json -Compress -Depth 4))
            while ($true) {
                $l = $r.ReadLine()
                if ($null -eq $l) { return $null }
                $o = $l | ConvertFrom-Json
                if ($o.PSObject.Properties['return']) { return ($o.return | ConvertTo-Json -Compress -Depth 4) }
                if ($o.PSObject.Properties['error']) { return "error: $($o.error.desc)" }
            }
        } finally { $c.Close() }
    } catch { return $null }
}
# The screen's PNG size in bytes (0 when QMP did not answer)
$shot = Join-Path $(if ($Log) { Split-Path $Log } else { $env:TEMP }) "autosave-screen-$QemuPid.png"
function Screen-Bytes {
    Remove-Item $shot -ErrorAction SilentlyContinue
    $said = Qmp @{ execute = 'screendump'; arguments = @{ filename = ($shot -replace '\\', '/'); format = 'png' } }
    if ($null -eq $said -or -not (Test-Path $shot)) { return 0 }
    $n = (Get-Item $shot).Length
    Remove-Item $shot -ErrorAction SilentlyContinue
    $n
}

$p = Get-Process -Id $QemuPid -ErrorAction SilentlyContinue
if (-not $p) { Note "QEMU (pid $QemuPid) is not running"; exit 0 }
$t0 = $p.StartTime
Note (("watching QEMU pid ${QemuPid}: a save once the face has been on the screen for {0} s, {1} s after the start, " +
       "and nobody is using the watch (its window not in front, or {2} s without input)") -f $FaceSeconds, $MinSeconds, $IdleSeconds)
$lastCpu = $p.TotalProcessorTime.TotalSeconds; $lastT = Get-Date
$face = $null
while ($true) {
    Start-Sleep -Seconds $Every
    $p.Refresh()
    if ($p.HasExited) { Note 'QEMU ended before the save: no save (closing the window saves the watch)'; exit 0 }
    $now = Get-Date
    $cpu = $p.TotalProcessorTime.TotalSeconds
    $cores = ($cpu - $lastCpu) / [Math]::Max(1, ($now - $lastT).TotalSeconds)
    $lastCpu = $cpu; $lastT = $now
    $up = ($now - $t0).TotalSeconds
    if (-not $face) {
        $bytes = Screen-Bytes
        if ($bytes -gt $FaceBytes) { $face = $now; Note ("the face is on the screen after {0:N0} s ({1} bytes)" -f $up, $bytes) }
        continue
    }
    if ($up -lt $MinSeconds -or ($now - $face).TotalSeconds -lt $FaceSeconds) { continue }
    $idle = [ASoft.WatchIdle]::IdleMs() / 1000
    $front = [ASoft.WatchIdle]::ForegroundPid() -eq [uint32]$QemuPid
    if ($front -and $idle -lt $IdleSeconds) { continue }
    if ($Disk) {
        $root = [IO.Path]::GetPathRoot($Disk)
        $free = ([IO.DriveInfo]::new($root)).AvailableFreeSpace / 1e9
        if ($free -lt $StateGB + 1) { Note ("ready, but {0:N1} GB free on {1}: a state needs about {2} GB, no save" -f $free, $root, $StateGB); exit 0 }
    }
    Note ("ready after {0:N0} s ({1:N2} cores; window in front: {2}, {3:N0} s without input): saving" -f $up, $cores, $front, $idle)
    $s0 = Get-Date
    # (HMP savevm prints nothing when it worked, its error otherwise)
    $said = Qmp @{ execute = 'human-monitor-command'; arguments = @{ 'command-line' = 'savevm asoft-quick' } } 900000
    if ($null -eq $said) { Note 'QMP did not answer: no save'; exit 1 }
    $text = try { [string]($said | ConvertFrom-Json) } catch { $said }
    if ($text.Trim()) { Note "the save failed: $($text.Trim())"; exit 1 }
    Note ("saved as asoft-quick in {0:N1} s: a start after a crash goes on from here" -f ((Get-Date) - $s0).TotalSeconds)
    exit 0
}

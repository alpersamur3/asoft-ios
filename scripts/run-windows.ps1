# ASoftware iOS: boot iOS 16 in a QEMU window on Windows (native QEMU, no WSL at run time).
#   powershell -ExecutionPolicy Bypass -File scripts\run-windows.ps1 [-Cpus 4] [-Kernel PATH] [-Keep]
# The window shows the ramfb scanout of the framebuffer; the kernel log goes to
# <out>\run\serial.txt. Guest writes are discarded unless -Keep is given.
param(
    # Everything that is not in the repo: QEMU, the iOS disks, runs, the .ipa folder.
    # ASOFT_WORK names it; default work\ in the repo.
    [string]$Work = $(if ($env:ASOFT_WORK) { $env:ASOFT_WORK } else { "$PSScriptRoot\..\work" }),
    # 4, not 8: each broadcast TLB flush stops every vCPU, and with 8 the boot was slower
    # (bench 2026-10-21: lock screen 100-118 s with 4 vs 128-164 s with 8)
    [int]$Cpus = 4,
    # Our QEMU build, the one iOS 26 runs on too (qemu-sptm's asoft branch, README.md "QEMU"): the
    # GTK console refreshes at most every 30 ms (the stock one redrew at the monitor's 144 Hz with
    # the BQL held), and with window-close=off closing the window powers iOS down (0003). An older
    # install's QEMU 11.1.2 (work\qemu\v11.1.2-asoft) when there is no newer one; the installed QEMU
    # when neither is there.
    # 0004 titles the window with -name alone ("ASoftware iOS")
    [string]$Qemu = $(if (Test-Path "$Work\qemu\qemu-system-aarch64.exe") { "$Work\qemu\qemu-system-aarch64.exe" }
                      else { "$Work\qemu\v11.1.2-asoft\qemu-system-aarch64.exe" }),
    # 0102 tells QEMU when iOS turns the display off (side bar: Screen off, Wake); 0103 sets the
    # clock from the host's after a pause or a quick boot; 0104 issues and consumes sandbox
    # extension tokens, so TCC grants hold (assetsd no longer aborts at every boot)
    [string]$Kernel = "$PSScriptRoot\..\xnu\out-0104\kernel.development.sweet",
    # New user disks start from v5. Layers, each an overlay on the one before (never write a layer
    # that others sit on): the base image as built; v2, its LaunchServices database rebuilt with
    # kernel 0099 so wallpaper posters and widgets are registered; v3, asoftinstalld that starts at
    # boot; v4, the asoftinstalld that also sets the time zone and keeps the display from dimming;
    # v5, tools/sweet-root-tweaks.py again (no driverkitd, no crash-looping plug-ins)
    # The installer's disk is ios16-base.qcow2 (installer/Install-ASoftware.ps1).
    [string]$Disk = $(if (Test-Path "$Work\root\ios16-base.qcow2") { "$Work\root\ios16-base.qcow2" }
                      else { "$Work\root\ios16-root-20H392-v5.qcow2" }),
    # gl=on: the GPU scales the 1080x2400 frame; plain gtk scales it on the QEMU main loop and
    # made the whole boot ~3.4x slower (scripts/dev/bench.py, 2026-10-21)
    # show-cursor: QEMU hides the host pointer over an absolute (tablet) input and expects the
    # guest to draw one; iOS draws none, so without it you cannot see where you click.
    # window-close=off with our QEMU (0003): closing the window presses the power key and iOS
    # syncs, unmounts and turns QEMU off (kernel 0100, ~10 s); closing it again quits at once.
    # sidebar=on (0006): Home, Lock, Volume, Screenshot, Install .ipa, Shut down beside the screen.
    # show-menubar=off: the side bar has what QEMU's menus offered here (Ctrl+Alt+M shows them)
    [string]$Display = 'gtk,gl=on,show-cursor=on,window-close=off,sidebar=on,show-menubar=off',
    # keepon: no auto-lock blackout. Keys in the window: F1 Home, F2 side button, F3/F4 volume, every
    # other key a hardware keyboard (kernel 0096+); mouse = touch
    [string]$ExtraArgs = 'sweetfb_noconsole=1 sweetfb_keepon=1',
    [int]$QmpPort = 4445,       # scripts\dev\qmp.py PORT screendump shot.png
    # Where -snapshot keeps its overlay (QEMU uses %TEMP%, i.e. C:): next to the disks, so the
    # copy-on-write traffic stays on their drive (bench 2026-10-21: lock screen 166 -> 150 s)
    [string]$TmpDir = "$Work\tmp",
    # -Persist: keep what iOS writes (settings, apps) in $UserDisk, a qcow2 overlay on $Disk; the
    # base image stays as built. -Reset deletes the overlay first (back to the base state).
    # -Keep instead writes straight into $Disk.
    [switch]$Persist,
    [switch]$Reset,
    [string]$UserDisk = "$Work\root\ios16-user.qcow2",
    [switch]$Keep,
    # Quick boot (our QEMU's 0009), with -Persist: closing the window saves the machine's state
    # (memory and devices, about 3 GB) in $UserDisk, as its snapshot asoft-quick, and the next
    # start resumes it in seconds. -NoQuickBoot boots iOS every time. A save is resumed once; then it
    # stays as a way back (-LoadState asoft-quick) until the next close saves again.
    [switch]$NoQuickBoot,
    # Drop .ipa files here while iOS runs (or use the side bar's Install .ipa): asoftinstalld (in
    # the v3 disk) fetches them through scripts\ipa-server.py and installs them; results land in
    # Installed\ or Failed\ with a .log
    [string]$IpaDir = "$Work\ipa",
    # iOS's time zone (IANA name, Europe/Istanbul), region (TR) and clock (24 or 12); default the
    # PC's. asoftinstalld applies each when it differs from what it applied last, so a change
    # made in iOS's Settings stays until the PC's own setting changes
    [string]$TimeZone = '',
    [string]$Region = '',
    [ValidateSet('', '12', '24')] [string]$Clock = '',
    # -LoadState NAME: resume that saved state of the user disk (the side bar's Save state makes them,
    # state-<time>) instead of the quick boot's, or asoft-quick (go back to the quick save); -Persist
    # only. A state that does not load is kept.
    [string]$LoadState = '',
    # -NoNet: no network card (QEMU's user-mode network is on by default)
    [switch]$NoNet
)
$ErrorActionPreference = 'Stop'
# A native tool's stderr lines are notes, not failures: Windows PowerShell 5.1 turns them into
# errors when the script's output is redirected, which 'Stop' would end the script on. Its exit
# code ($LASTEXITCODE) says how it went.
function Invoke-Tool {
    $ErrorActionPreference = 'Continue'
    $rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
    & $args[0] @rest
}
New-Item -ItemType Directory -Force $TmpDir | Out-Null
$env:TMP = $env:TEMP = $TmpDir
if (-not (Test-Path $Kernel)) {
    # not downloaded yet (CI): the newest kernel there is
    $newest = Get-ChildItem "$PSScriptRoot\..\xnu\out-*\kernel.development.sweet" -ErrorAction SilentlyContinue |
        Sort-Object { $_.Directory.Name } | Select-Object -Last 1
    if (-not $newest) { throw "No kernel: $Kernel" }
    Write-Host "Kernel $Kernel not there, using $($newest.FullName)"
    $Kernel = $newest.FullName
}
if (Test-Path $Qemu) {
    $env:QEMU_SYSTEM_AARCH64 = $Qemu   # read by tools\qemu-sweet.py
} else {
    # a stock QEMU has neither option
    $Display = $Display -replace ',window-close=off', '' -replace ',sidebar=on', ''
}

# Two QEMUs writing one disk would wreck it (QEMU's image locking does not work on Windows)
$written = if ($Persist) { $UserDisk } elseif ($Keep) { $Disk } else { '' }
if ($written) {
    $name = [IO.Path]::GetFileName($written)
    $other = Get-CimInstance Win32_Process -Filter "Name like 'qemu-system%'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($name) } | Select-Object -First 1
    if ($other) { throw "iOS is already running on $written (QEMU process $($other.ProcessId)); close that window first" }
}

# qemu-img of our build (next to its exe), else of an installed QEMU
$qemuImg = Join-Path (Split-Path $Qemu) 'qemu-img.exe'
if (-not (Test-Path $qemuImg)) { $qemuImg = 'C:\Program Files\qemu\qemu-img.exe' }

if ($Persist) {
    if ($Reset -and (Test-Path $UserDisk)) { Remove-Item $UserDisk; Remove-Item "$UserDisk.quick-used" -ErrorAction SilentlyContinue }
    if (-not (Test-Path $UserDisk)) {
        # Next to the base image the backing path is relative, so WSL tools (qemu-nbd) open it too
        $backing = if ((Split-Path $UserDisk) -eq (Split-Path $Disk)) { Split-Path $Disk -Leaf } else { $Disk }
        Invoke-Tool $qemuImg create -q -f qcow2 -b $backing -F qcow2 $UserDisk
        if ($LASTEXITCODE) { throw "qemu-img could not create $UserDisk" }
        Write-Host "New user disk $UserDisk (on $Disk)"
    }
    $Disk = $UserDisk
    $Keep = $true
}

# Quick boot: resume the state the window saved when it was closed, if no start resumed it yet.
# Once one has, the disk goes on from there and the state stays as the way back (-LoadState
# asoft-quick), until the next close saves again: <UserDisk>.quick-used names it by its id and time
# (no time zone in them). A start without quick boot (-NoQuickBoot) and tools/asoft-disk.sh, which
# writes to the disk, keep it as the way back too.
$quickBoot = $Persist -and -not $NoQuickBoot -and (Test-Path $Qemu) -and $Display -like 'gtk*'
$quickSnapshot = 'asoft-quick'
# A saved state of the user disk (qemu-img's JSON: id, date-sec, date-nsec), or $null
function Get-State([string]$name) {
    if (-not (Test-Path $UserDisk)) { return $null }
    try {
        $j = (Invoke-Tool $qemuImg info --output=json -U $UserDisk 2>$null) -join "`n" | ConvertFrom-Json
        @($j.snapshots) | Where-Object { $_ -and $_.name -ceq $name } | Select-Object -First 1
    } catch { $null }
}
function Quick-Key {
    $s = Get-State $quickSnapshot
    if ($s) { "$($s.id) $($s.'date-sec') $($s.'date-nsec')" } else { '' }
}
# The quick save's key when no start resumed it yet, else ''
function Get-QuickState {
    $k = Quick-Key
    $used = "$(Get-Content "$UserDisk.quick-used" -TotalCount 1 -ErrorAction SilentlyContinue)".Trim()
    if ($k -and $k -cne $used) { $k } else { '' }
}
function Keep-WayBack {
    $k = Quick-Key
    if ($k) { Set-Content -Path "$UserDisk.quick-used" -Value $k -Encoding ASCII }
}
$savedState = if ($Persist -and (Test-Path $UserDisk)) { Get-QuickState }
if ($LoadState) {
    if (-not $Persist -or -not (Test-Path $UserDisk)) { throw '-LoadState needs -Persist and its user disk' }
    if (-not (Get-State $LoadState)) { throw "no saved state $LoadState on $UserDisk" }
    $savedState = $null
}
if ($savedState -and -not $quickBoot) {
    $savedState = $null
    Write-Host 'Quick boot is off: iOS boots, and the saved state stays as a way back (-LoadState asoft-quick)'
}
# Notes in FILE once QEMU's QMP (127.0.0.1:PORT) says the machine runs (a state it resumes has
# loaded), from a runspace in the background while qemu-sweet.py waits for QEMU
function Watch-Running([int]$port, [string]$file) {
    $ps = [PowerShell]::Create()
    $null = $ps.AddScript({
        param($port, $file)
        $until = (Get-Date).AddMinutes(10)
        while ((Get-Date) -lt $until) {
            $c = New-Object Net.Sockets.TcpClient
            try {
                if ($c.ConnectAsync('127.0.0.1', $port).Wait(1000)) {
                    # no greeting while QEMU loads the state: its main loop stands still
                    $c.ReceiveTimeout = 3000
                    $r = New-Object IO.StreamReader($c.GetStream())
                    $w = New-Object IO.StreamWriter($c.GetStream()); $w.AutoFlush = $true
                    $null = $r.ReadLine()
                    $w.WriteLine('{"execute":"qmp_capabilities"}'); $null = $r.ReadLine()
                    $w.WriteLine('{"execute":"query-status"}')
                    for ($i = 0; $i -lt 5; $i++) {
                        $l = $r.ReadLine()
                        if ($l -cmatch '"return"') {
                            if ($l -cmatch '"running":\s*true') { Set-Content $file 'running'; return }
                            break
                        }
                    }
                }
            } catch { } finally { $c.Close() }
            Start-Sleep -Seconds 2
        }
    }).AddArgument($port).AddArgument($file)
    $null = $ps.BeginInvoke()
    $ps
}
if ($quickBoot) { $Display += ',quick-boot=on' }

$repo = Resolve-Path "$PSScriptRoot\.."
$out = "$Work\runs\win-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Force $out | Out-Null

$bootArgs = "debug=0xc serial=3 cpus=$Cpus keepsyms=1 -enable_kprintf_spam -noprogress " +
    "rd=vblkroot0 vblkrw=1 rootrw=1 unentitled_ios_sim_launch=1 ignition_level=1 " +
    "wdt_test=no_user_checkin launchd_unsecure_cache=1 wdt=-1 sweetfb_hz=30 " +
    # launchd kills an extension that has not checked in within a few seconds; under emulation the
    # default wallpaper's poster extension needs longer (it decodes HEIC images in software)
    "launchd_disable_all_timeouts=1 $ExtraArgs"
if (-not $TimeZone) {
    # The PC's zone, Windows ID to IANA name through the ICU that comes with Windows 10 1903+
    try {
        Add-Type -Namespace Asoft -Name Icu -MemberDefinition @'
[DllImport("icu.dll", CharSet = CharSet.Unicode)]
public static extern int ucal_getTimeZoneIDForWindowsID(string winid, int len, string region,
    System.Text.StringBuilder id, int capacity, ref int status);
'@
        $id = New-Object System.Text.StringBuilder 64
        $status = 0
        $n = [Asoft.Icu]::ucal_getTimeZoneIDForWindowsID([TimeZoneInfo]::Local.Id, -1, $null, $id, 64, [ref]$status)
        if ($status -le 0 -and $n -gt 0) { $TimeZone = $id.ToString(0, $n) }
    } catch {
        Write-Host "PC time zone not found ($($_.Exception.Message)); iOS keeps its own"
    }
}
# -cmatch: a case-insensitive -match lowercases with the PC's culture, and in Turkish the I of
# Istanbul becomes a dotless ı, which [a-z] does not hold
if ($TimeZone -cmatch '^[A-Za-z0-9_+/-]+$') { $bootArgs += " asoft_tz=$TimeZone" }
# Region and clock from the PC's region format (Settings > Time & language > Region):
# tr-TR -> TR, a short time pattern with H (HH:mm) -> 24-hour
$culture = Get-Culture
if (-not $Region) { $Region = ($culture.Name -split '-')[-1] }
if (-not $Clock) { $Clock = if ($culture.DateTimeFormat.ShortTimePattern -cmatch 'H') { '24' } else { '12' } }
if ($Region -cmatch '^([A-Z]{2}|[0-9]{3})$') { $bootArgs += " asoft_region=$Region" }
$bootArgs += " asoft_clock=$Clock"

Push-Location $repo
$ipaServer = $null
try {
    # The Python the installer put next to the app, else an installed 3.12; python.exe
    # itself, not the py launcher, so that stopping it stops the script
    $python = "$PSScriptRoot\..\python\python.exe"
    if (-not (Test-Path $python)) { $python = py -3.12 -c 'import sys; print(sys.executable)' }
    if ($IpaDir) {
        $ipaServer = Start-Process $python -WindowStyle Hidden -PassThru `
            -ArgumentList "`"$PSScriptRoot\ipa-server.py`"", '--dir', "`"$IpaDir`""
        $env:ASOFT_IPA_DIR = $IpaDir   # the side bar's Install .ipa copies there
        Write-Host "Drop .ipa files into $IpaDir to install them"
    }
    # The iPhone X device tree mkadt.py takes /product from: the installer extracts it from the
    # IPSW into the work folder (a checkout may have it in research\ipsw-x instead)
    if (Test-Path "$Work\firmware\d22ap.adt") { $env:ASOFT_DEVICE_TREE = "$Work\firmware\d22ap.adt" }
    Invoke-Tool $python tools\mkadt.py "$out\qemu.adt" --qemu --highmem
    if ($LASTEXITCODE) { throw 'mkadt.py could not make the device tree' }
    Invoke-Tool $python tools\mkpayload.py $Kernel "$out\qemu.adt" "$out\payload.bin" --cmdline $bootArgs
    $qemuArgs = @("$out\payload.bin", "$out\run", '--disk', $Disk, '--smp', $Cpus,
        '--display', $Display, '--qemu-log', 'guest_errors,unimp', '--qmp-tcp', $QmpPort,
        '--name', 'ASoftware iOS')
    if (-not $Keep) { $qemuArgs += '--snapshot' }
    if ($NoNet) { $qemuArgs += '--net', 'none' }
    # From here on the disk goes on from this start: a quick save, resumed now or not, is the way back
    if ($Persist) { Keep-WayBack }
    if ($LoadState) {
        Write-Host "Resuming the saved state $LoadState"
        Invoke-Tool $python tools\qemu-sweet.py @qemuArgs --loadvm $LoadState
        if ($LASTEXITCODE) { Write-Host "QEMU ended with $LASTEXITCODE; the saved state $LoadState is kept" }
    } elseif ($savedState) {
        Write-Host 'Resuming the state saved when the window was closed'
        $ran = "$out\running"
        $watch = Watch-Running $QmpPort $ran
        Invoke-Tool $python tools\qemu-sweet.py @qemuArgs --loadvm $quickSnapshot
        $code = $LASTEXITCODE
        $watch.Stop(); $watch.Dispose()
        # QEMU failed before the machine ran: the state could not be resumed (another QEMU build,
        # other options). It goes, and iOS boots.
        if ($code -and -not (Test-Path $ran)) {
            Write-Host 'The saved state could not be resumed; booting iOS'
            Invoke-Tool $qemuImg snapshot -d $quickSnapshot $UserDisk
            Remove-Item "$UserDisk.quick-used" -ErrorAction SilentlyContinue
            Invoke-Tool $python tools\qemu-sweet.py @qemuArgs
        }
    } else {
        Invoke-Tool $python tools\qemu-sweet.py @qemuArgs
    }
} finally {
    if ($ipaServer -and -not $ipaServer.HasExited) { Stop-Process -Id $ipaServer.Id -Force }
    Pop-Location
}
Write-Host "Kernel log: $out\run\serial.txt"

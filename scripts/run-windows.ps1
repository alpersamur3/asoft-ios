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
    # Our QEMU 11.1.2 build (qemu/patches, .github/workflows/qemu-win.yml): the GTK
    # console refreshes at most every 30 ms (the stock one redrew at the monitor's 144 Hz with the
    # BQL held), and with window-close=off closing the window powers iOS down (0003). Falls back
    # to the installed QEMU when the build is not there.
    # 0004 titles the window with -name alone ("ASoftware iOS"); --version says "(ASoftware)"
    [string]$Qemu = "$Work\qemu\v11.1.2-asoft\qemu-system-aarch64.exe",
    # 0102 tells QEMU when iOS turns the display off (side bar: Screen off, Wake)
    [string]$Kernel = "$PSScriptRoot\..\xnu\out-0102\kernel.development.sweet",
    # New user disks start from v4. Layers, each an overlay on the one before (never write a layer
    # that others sit on): the base image as built; v2, its LaunchServices database rebuilt with
    # kernel 0099 so wallpaper posters and widgets are registered; v3, asoftinstalld that starts at
    # boot; v4, the asoftinstalld that also sets the time zone and keeps the display from dimming
    [string]$Disk = "$Work\root\ios16-root-20H392-v4.qcow2",
    # gl=on: the GPU scales the 1080x2400 frame; plain gtk scales it on the QEMU main loop and
    # made the whole boot ~3.4x slower (scripts/dev/bench.py, 2026-10-21)
    # show-cursor: QEMU hides the host pointer over an absolute (tablet) input and expects the
    # guest to draw one; iOS draws none, so without it you cannot see where you click.
    # window-close=off with our QEMU (0003): closing the window presses the power key and iOS
    # syncs, unmounts and turns QEMU off (kernel 0100, ~10 s); closing it again quits at once.
    # sidebar=on (0006): Home, Lock, Volume, Screenshot, Install .ipa, Shut down beside the screen
    [string]$Display = 'gtk,gl=on,show-cursor=on,window-close=off,sidebar=on',
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
    # Drop .ipa files here while iOS runs (or use the side bar's Install .ipa): asoftinstalld (in
    # the v3 disk) fetches them through scripts\ipa-server.py and installs them; results land in
    # Installed\ or Failed\ with a .log
    [string]$IpaDir = "$Work\ipa",
    # iOS's time zone as an IANA name (Europe/Istanbul); default the PC's. asoftinstalld sets it
    [string]$TimeZone = ''
)
$ErrorActionPreference = 'Stop'
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

if ($Persist) {
    if ($Reset -and (Test-Path $UserDisk)) { Remove-Item $UserDisk }
    if (-not (Test-Path $UserDisk)) {
        # Next to the base image the backing path is relative, so WSL tools (qemu-nbd) open it too
        $backing = if ((Split-Path $UserDisk) -eq (Split-Path $Disk)) { Split-Path $Disk -Leaf } else { $Disk }
        # qemu-img of our build (qemu/build-windows.sh), else of an installed QEMU
        $qemuImg = Join-Path (Split-Path $Qemu) 'qemu-img.exe'
        if (-not (Test-Path $qemuImg)) { $qemuImg = 'C:\Program Files\qemu\qemu-img.exe' }
        & $qemuImg create -q -f qcow2 -b $backing -F qcow2 $UserDisk
        if ($LASTEXITCODE) { throw "qemu-img could not create $UserDisk" }
        Write-Host "New user disk $UserDisk (on $Disk)"
    }
    $Disk = $UserDisk
    $Keep = $true
}

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

Push-Location $repo
$ipaServer = $null
try {
    # python.exe itself, not the py launcher, so that stopping it stops the script
    $python = py -3.12 -c 'import sys; print(sys.executable)'
    if ($IpaDir) {
        $ipaServer = Start-Process $python -WindowStyle Hidden -PassThru `
            -ArgumentList "`"$PSScriptRoot\ipa-server.py`"", '--dir', "`"$IpaDir`""
        $env:ASOFT_IPA_DIR = $IpaDir   # the side bar's Install .ipa copies there
        Write-Host "Drop .ipa files into $IpaDir to install them"
    }
    py -3.12 tools\mkadt.py "$out\qemu.adt" --qemu --highmem
    py -3.12 tools\mkpayload.py $Kernel "$out\qemu.adt" "$out\payload.bin" --cmdline $bootArgs
    $qemuArgs = @("$out\payload.bin", "$out\run", '--disk', $Disk, '--smp', $Cpus,
        '--display', $Display, '--qemu-log', 'guest_errors,unimp', '--qmp-tcp', $QmpPort,
        '--name', 'ASoftware iOS')
    if (-not $Keep) { $qemuArgs += '--snapshot' }
    py -3.12 tools\qemu-sweet.py @qemuArgs
} finally {
    if ($ipaServer -and -not $ipaServer.HasExited) { Stop-Process -Id $ipaServer.Id -Force }
    Pop-Location
}
Write-Host "Kernel log: $out\run\serial.txt"

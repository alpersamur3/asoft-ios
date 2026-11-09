# iOS 26 in a window: the research VM (pvg=reims, the guest's Metal on the host GPU) with the
# ASoftware GTK window and side bar, as the iOS 16 build has.
#   Mouse: touch (click = tap, drag = swipe), wheel: swipe, F1 Home, F2 side button,
#   F3/F4 volume, Ctrl+V types the clipboard, Ctrl+S screenshot, F11 full screen.
# Everything is read from one work folder (-Work, or $env:ASOFT26_WORK), laid out as the build
# steps in README.md leave it:
#   fw\bootkc, fw\sptm, fw\txm    cloudOS 26.4b firmware, unwrapped
#   dtree-smp4, dtree-smp8         the device tree for 4 or 8 vCPUs
#   root.tc                        the trust cache for the root disk
#   rd-shell.hfs                   the shell ramdisk
#   root.qcow2                     the iOS 26 disk (iOS 26's own wallpaper)
#   root-collections.qcow2/.tc     optional: the Collections wallpaper disk (README.md, step 5.3.6)
#   qemu\                          qemu-sptm built for Windows, with reims-vgpu's DLLs
# Outputs (serial, logs) go to <Work>\runs\<Name>. QMP 127.0.0.1:4453 and HMP 4452 stay open
# for tools; the guest's serial console is on 127.0.0.1:4451.
# The disk, as the iOS 16 launcher: by default iOS writes to a throwaway overlay (-snapshot),
# -Persist keeps its changes in a user overlay on the base image, -Keep writes the base image.
#   Start-iOS26.ps1 [-Work D:\ios26] [-Name w1] [-Wallpaper ios26|collections] [-Persist [-Reset]] [-Keep] [-NoQuickBoot]
#                   [-Net] [-Page4K] [-NoGl] [-Cpu max,pauth-impdef=on] [-Smp 4|8] [-NoIpa]
#                   [-InstallIpa app.ipa]
#                   [-TimeZone Europe/Istanbul] [-Region TR] [-Clock 24|12]   (default: the PC's)
#                   [-RamMiB 6144] [-LoadState state-20261109-101500]
# .ipa: the side bar's "Install .ipa..." (or dropping files into <Work>\ipa, or -InstallIpa) installs
# the app by direct placement on the NEXT start (Install-Ipa.ps1); after the button, restart iOS.
param(
    [string]$Work = $env:ASOFT26_WORK,
    [string]$Name = 'w1',
    # The base disk and its trust cache. -Wallpaper ios26 (default): root.qcow2, iOS 26's own
    # wallpaper (MercuryPoster, drawn by the guest's Metal on the host GPU; needs metal2vulkan's
    # `windows` branch at 56705098 or later). -Wallpaper collections: root-collections.qcow2, the
    # iOS 17 Collections wallpaper of build step 5.3.6, lighter on the guest's CPU. -Disk/-Tc name
    # another pair.
    [ValidateSet('ios26', 'collections')][string]$Wallpaper = 'ios26',
    [string]$Disk = '',
    [string]$Tc = '',
    # -Persist: keep what iOS writes (settings, apps) in $UserDisk, a qcow2 overlay on $Disk; the
    # base image stays as built. -Reset deletes the overlay first (back to the base state).
    # -Keep instead writes straight into $Disk. Neither: a throwaway overlay in $TmpDir.
    [switch]$Persist,
    [switch]$Reset,
    # (one per base disk: an overlay holds its base's name, and each base has its own trust cache)
    [string]$UserDisk = '',
    [switch]$Keep,
    [string]$TmpDir = 'tmp',
    # -Net: a virtio-net NIC on QEMU's user-mode network (10.0.2.15, NAT, no inbound). Whether
    # this kernel drives it has not been checked yet; off until it is.
    [switch]$Net,
    # -Page4K: 4K softmmu pages (QEMU's default). Without it the guest's 16K pages are kept
    # whole in QEMU's TLB: one page walk per page instead of four (lock screen 135 -> 110-120 s)
    [switch]$Page4K,
    [switch]$NoGl,
    # pauth-impdef: TCG's cheap pointer-authentication algorithm instead of QARMA5 (iOS 26 is
    # arm64e: PAC instructions in every function); -Cpu max for the architected one
    [string]$Cpu = 'max,pauth-impdef=on',
    # vCPUs: 4 or 8 (dtree-smpN from dt-root26smp.py --cpus N)
    [ValidateSet(4, 8)][int]$Smp = 4,
    # .ipa installs: the side bar's "Install .ipa..." copies files into $IpaDir (default <Work>\ipa);
    # each .ipa there is installed by direct placement on the next start (the disk can't be written
    # while iOS runs). -NoIpa turns it off.
    [string]$IpaDir = '',
    [switch]$NoIpa,
    # Quick boot, on a disk that keeps what iOS writes (-Persist, -Keep or an apps overlay): closing
    # the window saves the machine's state (memory and devices, about 3.7 GB) in that disk, as its
    # snapshot asoft-quick, and the next start resumes it in seconds. -NoQuickBoot boots iOS every time.
    [switch]$NoQuickBoot,
    # -InstallIpa path.ipa: install this .ipa (direct placement) into the apps overlay and boot it.
    [string]$InstallIpa = '',
    # iOS's time zone (IANA name, Europe/Istanbul), region (TR) and clock (24 or 12); default the
    # PC's. Each is applied when it differs from what was applied to the disk last, so a change
    # made in iOS's Settings stays until the PC's own setting changes (below, "The PC's time")
    [string]$TimeZone = '',
    [string]$Region = '',
    [ValidateSet('', '12', '24')] [string]$Clock = '',
    # Always On Display: with dtree-smpN-aod in the work folder (the installer's apps step makes it
    # with the disk's libMobileGestalt patch) iOS goes to its Always On Display at the side button
    # (F2) and the first click there wakes it (Home). -NoAod boots the plain tree (a disk without
    # the patch must: backboardd asserts otherwise).
    [switch]$NoAod,
    # -RamMiB N: the guest's RAM (QEMU takes it from the device tree: scripts\dt-ram.ps1 writes
    # <tree>-<N>m next to it). A saved state loads only into the RAM it was made with.
    [int]$RamMiB = 0,
    # -LoadState NAME: resume that saved state of the disk (the side bar's Save state makes them,
    # state-<time>; ASoftware.exe lists them) instead of the quick boot's; it needs -Persist or -Keep,
    # and the vCPUs and RAM it was saved with. A state that does not load is kept, not deleted.
    [string]$LoadState = '',
    # more QEMU options, as they are (e.g. -Extra '-msg','timestamp=on','-trace','usb_consumer_*')
    [string[]]$Extra = @()
)
$ErrorActionPreference = 'Stop'
if (-not $Work) { $Work = Join-Path $PSScriptRoot 'work' }
$Work = (Resolve-Path $Work).Path
function In-Work([string]$p) { if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $Work $p } }
$base = @{ ios26 = @('root.qcow2', 'root.tc', 'root26-user.qcow2')
           collections = @('root-collections.qcow2', 'root-collections.tc', 'root-collections-user.qcow2') }[$Wallpaper]
if (-not $Disk) { $Disk = $base[0] }
if (-not $Tc) { $Tc = $base[1] }
if (-not $UserDisk) { $UserDisk = $base[2] }
$Disk = In-Work $Disk
$Tc = In-Work $Tc
$UserDisk = In-Work $UserDisk
$TmpDir = In-Work $TmpDir
$dtree = "dtree-smp$Smp"
$aod = -not $NoAod -and (Test-Path (Join-Path $Work "$dtree-aod"))
if ($aod) { $dtree += '-aod' }
foreach ($f in @('fw\bootkc', 'fw\sptm', 'fw\txm', $dtree, 'rd-shell.hfs')) {
    if (-not (Test-Path (Join-Path $Work $f))) { throw "missing $f in $Work (see README.md, Build)" }
}
# another RAM size: the tree with it, made once next to the tree (again when the tree is newer)
if ($RamMiB) {
    $dtRam = Join-Path $PSScriptRoot 'scripts\dt-ram.ps1'
    $has = & $dtRam -In (Join-Path $Work $dtree) -Read
    if ([int]$has -ne $RamMiB) {
        $sized = "$dtree-$($RamMiB)m"
        $src = Get-Item (Join-Path $Work $dtree)
        $dst = Join-Path $Work $sized
        if (-not (Test-Path $dst) -or (Get-Item $dst).LastWriteTime -lt $src.LastWriteTime) {
            & $dtRam -In $src.FullName -Out $dst -MiB $RamMiB
        }
        $dtree = $sized
        Write-Host "Guest RAM $RamMiB MiB ($dtree)"
    }
}
foreach ($f in @($Disk, $Tc)) { if (-not (Test-Path $f)) { throw "missing $f" } }
$exe = Join-Path $Work 'qemu\qemu-system-aarch64w.exe'
if (-not (Test-Path $exe)) { $exe = Join-Path $Work 'qemu\qemu-system-aarch64.exe' }
$userTc = ($Tc -replace '\.tc$', '') + '-user.tc'
if ($Persist -and $Reset) {
    foreach ($f in @($UserDisk, $userTc)) { if (Test-Path $f) { Remove-Item $f } }
}
$qemuImg = Join-Path (Split-Path $exe) 'qemu-img.exe'
if (-not (Test-Path $qemuImg)) { $qemuImg = 'C:\Program Files\qemu\qemu-img.exe' }
$quickSnapshot = 'asoft-quick'
function Get-QuickState([string]$disk) {
    if ((Test-Path $disk) -and (Test-Path $qemuImg)) {
        & $qemuImg snapshot -l -U $disk | Where-Object { "$_" -cmatch "\s$quickSnapshot\s" }
    }
}
function Remove-QuickState([string]$disk) {
    if (Get-QuickState $disk) { & $qemuImg snapshot -d $quickSnapshot $disk }
}
# .ipa installs by direct placement (the live installd path needs an APFS Data volume; this disk is
# HFS+). ASOFT_IPA_DIR is set so the side bar's "Install .ipa..." is enabled; it copies files into
# $IpaDir. The disk cannot be written while iOS runs, so each .ipa there (and -InstallIpa) is
# installed on the NEXT start into an apps overlay (Install-Ipa.ps1: the .app into /Applications +
# trust cache + LaunchServices rebuild), booted and kept. So after the button, close and reopen
# iOS; installed apps persist in the apps overlay. -NoIpa turns all this off.
if (-not $NoIpa) {
    if (-not $IpaDir) { $IpaDir = In-Work 'ipa' }
    New-Item -ItemType Directory -Force $IpaDir | Out-Null
    $env:ASOFT_IPA_DIR = $IpaDir
    $appsDisk = ($Disk -replace '\.qcow2$', '') + '-apps.qcow2'
    $appsTc = ($Tc -replace '\.tc$', '') + '-apps.tc'
    # Under -Persist an .ipa goes into the user overlay itself, on an apps overlay a run without
    # -Persist left, if any: one disk holds what iOS writes and the apps
    if ($Persist -and (Test-Path $appsDisk)) { $Disk = $appsDisk; $Tc = $appsTc }
    $queue = @(Get-ChildItem $IpaDir -Filter *.ipa -File -ErrorAction SilentlyContinue)
    if ($InstallIpa -and (Test-Path $InstallIpa)) { $queue += Get-Item $InstallIpa }
    if ($queue) {
        $installer = Join-Path $PSScriptRoot 'Install-Ipa.ps1'
        if (-not (Test-Path $installer)) { throw 'Install-Ipa.ps1 is not next to the launcher' }
        $inbox = (Resolve-Path $IpaDir).Path
        $into = if ($Persist) { @('-AppsDisk', $UserDisk, '-AppsTc', $userTc) } else { @() }
        Remove-QuickState $(if ($Persist) { $UserDisk } else { $appsDisk })
        foreach ($ipa in $queue) {
            Write-Host "Installing $($ipa.Name) (direct placement)..."
            & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Ipa $ipa.FullName -Work $Work -Disk $Disk -Tc $Tc @into
            $ok = ($LASTEXITCODE -eq 0)
            if ($ipa.DirectoryName -eq $inbox) {
                $done = Join-Path $IpaDir $(if ($ok) { 'Installed' } else { 'Failed' })
                New-Item -ItemType Directory -Force $done | Out-Null
                Move-Item $ipa.FullName (Join-Path $done $ipa.Name) -Force
            } elseif (-not $ok) {
                throw "Install-Ipa.ps1 failed for $($ipa.Name)"
            }
        }
    }
    if (-not $Persist -and (Test-Path $appsDisk)) { $Disk = $appsDisk; $Tc = $appsTc; $Keep = $true }
}
if ($Persist -and (Test-Path $userTc)) { $Tc = $userTc }
$O = Join-Path $Work "runs\$Name"
New-Item -ItemType Directory -Force $O | Out-Null

# Two QEMUs writing one disk would wreck it (QEMU's image locking does not work on Windows)
$written = if ($Persist) { $UserDisk } elseif ($Keep) { $Disk } else { '' }
if ($written) {
    $leaf = [IO.Path]::GetFileName($written)
    $other = Get-CimInstance Win32_Process -Filter "Name like 'qemu-system%'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($leaf) } | Select-Object -First 1
    if ($other) { throw "iOS is already running on $written (QEMU process $($other.ProcessId)); close that window first" }
}

# Quick boot: resume the state the window saved when it was closed, if any (QEMU deletes it once
# the machine runs). It belongs to the disk as it was then, so a start without quick boot drops it,
# and so does an .ipa install, above.
$quickBoot = $written -and -not $NoQuickBoot -and (Test-Path $qemuImg)
$savedState = if ($written) { Get-QuickState $written }
# -LoadState: that state instead (the quick boot's stays until the machine runs, then goes: the disk
# goes on from the loaded state)
if ($LoadState) {
    if (-not $written) { throw '-LoadState needs a disk that keeps its states (-Persist or -Keep)' }
    if (-not (& $qemuImg snapshot -l -U $written | Where-Object { "$_" -cmatch "^\s*\d+\s+$([regex]::Escape($LoadState))\s" })) {
        throw "no saved state $LoadState on $written"
    }
    $savedState = $null
}
if ($savedState -and -not $quickBoot) {
    Remove-QuickState $written
    $savedState = $null
    Write-Host 'Dropped the saved state (quick boot is off)'
}

# The PC's time: its time zone, region format and 12/24-hour clock, found as the iOS 16 launcher
# finds them. iOS 26 has no daemon to apply them at boot (iOS 16's asoftinstalld): once QEMU runs,
# scripts\guest-clock.py does it over the serial root shell, before SpringBoard reads them. Only
# the values that differ from what was applied to this disk last (<disk>.host.txt; a new overlay
# starts from its base's) are applied, and only on a cold boot: a saved state is dropped for it.
if (-not $TimeZone) {
    # Windows ID to IANA name through the ICU that comes with Windows 10 1903+
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
# tr-TR -> TR, a short time pattern with H (HH:mm) -> 24-hour
$culture = Get-Culture
if (-not $Region) { $Region = ($culture.Name -split '-')[-1] }
if (-not $Clock) { $Clock = if ($culture.DateTimeFormat.ShortTimePattern -cmatch 'H') { '24' } else { '12' } }
# -cmatch: a case-insensitive -match lowercases with the PC's culture, and in Turkish the I of
# Istanbul becomes a dotless ı, which [a-z] does not hold
$pcTime = [ordered]@{}
if ($TimeZone -cmatch '^[A-Za-z0-9_+/-]+$') { $pcTime.TimeZone = $TimeZone }
if ($Region -cmatch '^([A-Z]{2}|[0-9]{3})$') { $pcTime.Region = $Region }
$pcTime.Clock = $Clock
function Time-Mark([string]$disk) { ($disk -replace '\.qcow2$', '') + '.host.txt' }
# A disk's mark, else its base's (the apps overlay's, root.qcow2's): Key=Value lines
$markDisk = if ($written) { $written } else { $Disk }
if (-not (Test-Path $markDisk)) { Remove-Item (Time-Mark $markDisk) -ErrorAction SilentlyContinue }   # -Reset
$applied = @{}
$from = @($markDisk, $Disk, ($Disk -replace '-apps\.qcow2$', '.qcow2')) | Where-Object { Test-Path (Time-Mark $_) } | Select-Object -First 1
if ($from) {
    foreach ($l in Get-Content (Time-Mark $from)) { if ("$l" -cmatch '^(\w+)=(.*)$') { $applied[$Matches[1]] = $Matches[2] } }
    if ($written -and $from -ne $markDisk) { Copy-Item (Time-Mark $from) (Time-Mark $markDisk) }
}
$timeArgs = @()
foreach ($k in $pcTime.Keys) {
    if ($applied[$k] -cne $pcTime[$k]) { $timeArgs += @(@{ TimeZone = '--tz'; Region = '--region'; Clock = '--clock' }[$k], $pcTime[$k]) }
}
if ($timeArgs -and $LoadState) {
    Write-Host "The PC's time zone, region or clock is new to iOS: it takes it at the next start that is not a resume"
    $timeArgs = @()
}
if ($timeArgs -and $savedState) {
    Remove-QuickState $written
    $savedState = $null
    Write-Host "Dropped the saved state: the PC's time zone, region or clock is new to iOS, which takes it on a cold boot"
}

# qemu-img: next to the QEMU, an installed QEMU, or the WSL distro the disk was built in
function New-Overlay([string]$base, [string]$overlay) {
    # Next to the base image the backing path is relative, so WSL tools (qemu-nbd) open it too
    $backing = if ((Split-Path $overlay) -eq (Split-Path $base)) { Split-Path $base -Leaf } else { $base }
    $qemuImg = Join-Path (Split-Path $exe) 'qemu-img.exe'
    if (-not (Test-Path $qemuImg)) { $qemuImg = 'C:\Program Files\qemu\qemu-img.exe' }
    if (Test-Path $qemuImg) {
        & $qemuImg create -q -f qcow2 -b $backing -F qcow2 $overlay
    } else {
        $wsl = '/mnt/' + $overlay.Substring(0, 1).ToLower() + ($overlay.Substring(2) -replace '\\', '/')
        wsl -d ios-emu -u root -- qemu-img create -q -f qcow2 -b $backing -F qcow2 $wsl
    }
    if ($LASTEXITCODE) { throw "qemu-img could not create $overlay" }
}

$snapshot = @()
if ($Persist) {
    if (-not (Test-Path $UserDisk)) {
        New-Overlay $Disk $UserDisk
        Write-Host "New user disk $UserDisk (on $Disk)"
    }
    $Disk = $UserDisk
} elseif (-not $Keep) {
    # -snapshot keeps its overlay in %TEMP% (C:): next to the disks instead, so the copy-on-write
    # traffic stays on their drive
    New-Item -ItemType Directory -Force $TmpDir | Out-Null
    $env:TMPDIR = $TmpDir
    $env:TEMP = $TmpDir
    $env:TMP = $TmpDir
    $snapshot = @('-snapshot')
    Write-Host "Throwaway run: what iOS writes is dropped at exit (-Persist keeps it)"
}

$env:ASOFT_PAGE_BITS = if ($Page4K) { '12' } else { '14' }
$env:REIMS_VGPU_LOG = 'warn'
Remove-Item Env:REIMS_VGPU_TRACE -ErrorAction SilentlyContinue
$env:ASOFT_SUBTITLE = 'iOS 26.6.2 ' + [char]0x00B7 + ' GPU: host Vulkan'
# the window's Always On Display handling (qemu-sptm ui/gtk.c): F2 there takes iOS to it, a click wakes
if ($aod) { $env:ASOFT_AOD = '1'; Write-Host "Always On Display ($dtree): the side button (F2) takes iOS to it" }
else { Remove-Item Env:ASOFT_AOD -ErrorAction SilentlyContinue }
# no window-close=off: the research VM has no power key wired, closing quits
$display = 'gtk,show-cursor=on,sidebar=on,show-menubar=off,zoom-to-fit=on'
if (-not $NoGl) { $display += ',gl=on' }
if ($quickBoot) { $display += ',quick-boot=on' }

$boot = "serial=3 -v debug=0x14e cpus=$Smp rd=disk0s1 wdt=-1 keepsyms=1 -noprogress launchd_unsecure_cache=1 launchd_disable_all_timeouts=1 aks-endpoint=0 cpu_boot_timeout_secs=30"
$qargs = @(
    '-name', '"ASoftware iOS 26"',
    '-M', 'vresearch,fb=1179x2556,unauth-root=on,pvg=reims,aks-stub=on,amfi-lc-off=on,aks-crypt=on,acm-stub=on,hfs-dp-stub=on',
    '-bootkc', "`"$Work\fw\bootkc`"", '-sptm', "`"$Work\fw\sptm`"", '-txm', "`"$Work\fw\txm`"",
    '-dtree', "`"$Work\$dtree`"", '-tc', "`"$Tc`"", '-ramdisk', "`"$Work\rd-shell.hfs`"",
    '-args', "`"$boot`"",
    '-display', $display,
    '-monitor', 'tcp:127.0.0.1:4452,server=on,wait=off',
    '-parallel', 'none',
    '-chardev', "`"socket,id=con,host=127.0.0.1,port=4451,server=on,wait=off,logfile=$O\serial.log`"",
    '-serial', 'chardev:con', '-d', 'guest_errors,unimp', '-D', "`"$O\qemu.log`"",
    # tb-size: a 2 GiB code buffer (x86-64's maximum); the 1 GiB default refilled ~7 times in 13 min
    '-cpu', $Cpu, '-smp', "$Smp", '-accel', 'tcg,thread=multi,tb-size=2048',
    '-drive', "`"file=$Disk,if=none,id=root,cache=writeback,discard=unmap`"", '-device', 'virtio-blk-pci,drive=root',
    '-qmp', 'tcp:127.0.0.1:4453,server=on,wait=off',
    # the touchscreen's port reports PORTSC.DR: iOS takes it as the built-in digitizer
    '-device', 'qemu-xhci,id=xhci,conditional-intr-mapping=on,nonremovable=2',
    # idle-reports=off: iOS 26 gives the keyboard a 24 ms HID idle rate, so QEMU repeated the
    # unchanged report ~60x/s and iOS's HID driver spent ~168 s of CPU on it in the first 22 min
    # (notes/IOS26-BOOT-SERVICES.md). off stops the repeats. This is our own usb-kbd property
    # (qemu-sptm asoft 4eee4e5 and later); an older QEMU rejects it ("not found") and will not boot.
    '-device', 'usb-kbd,bus=xhci.0,port=1,id=ukbd,idle-reports=off',
    '-device', 'usb-touchscreen,bus=xhci.0,port=2,id=utouch',
    '-device', 'usb-consumer,bus=xhci.0,port=3,id=ucons'
) + $snapshot
if ($Net) { $qargs += @('-nic', 'user,model=virtio-net-pci') }
$qargs += $Extra
# QEMU's run state over QMP (127.0.0.1:PORT): true once the machine runs (a state it resumes has loaded);
# false while it loads (the main loop stands still and does not answer) or when it is not there
function Qmp-Running([int]$port) {
    $c = New-Object Net.Sockets.TcpClient
    try {
        if (-not $c.ConnectAsync('127.0.0.1', $port).Wait(1000)) { return $false }
        $c.ReceiveTimeout = 3000
        $r = New-Object IO.StreamReader($c.GetStream())
        $w = New-Object IO.StreamWriter($c.GetStream()); $w.AutoFlush = $true
        $null = $r.ReadLine()
        $w.WriteLine('{"execute":"qmp_capabilities"}'); $null = $r.ReadLine()
        $w.WriteLine('{"execute":"query-status"}')
        for ($i = 0; $i -lt 5; $i++) { $l = $r.ReadLine(); if ($l -cmatch '"return"') { return $l -cmatch '"running":\s*true' } }
        $false
    } catch { $false } finally { $c.Close() }
}
function Start-Qemu([string[]]$more) {
    Start-Process -FilePath $exe -ArgumentList ($qargs + $more) -PassThru -RedirectStandardError "$O\stderr.log" -RedirectStandardOutput "$O\stdout.log"
}
if ($LoadState) {
    Write-Host "Resuming the saved state $LoadState"
    $q = Start-Qemu @('-loadvm', $LoadState)
    $null = $q.Handle
    # until the machine runs, or QEMU ends (it is not deleted when it does not load: QEMU says why in
    # stderr.log)
    $until = (Get-Date).AddMinutes(5)
    while (-not $q.HasExited -and (Get-Date) -lt $until -and -not (Qmp-Running 4453)) { Start-Sleep -Seconds 2 }
    if ($q.HasExited -and $q.ExitCode) {
        $why = @(Get-Content "$O\stderr.log" -Tail 6 -ErrorAction SilentlyContinue) -join "`n"
        throw "the saved state $LoadState could not be resumed (QEMU exit $($q.ExitCode)); it is kept. $O\stderr.log:`n$why"
    }
} elseif ($savedState) {
    Write-Host 'Resuming the state saved when the window was closed'
    $q = Start-Qemu @('-loadvm', $quickSnapshot)
    $null = $q.Handle       # ExitCode, once it has ended, needs the handle taken
    # QEMU failed, the state still there: it could not be resumed (another QEMU build, other
    # options) and the machine never ran. Drop it and boot iOS instead.
    $until = (Get-Date).AddMinutes(5)
    while (-not $q.HasExited -and (Get-Date) -lt $until -and (Get-QuickState $written)) { Start-Sleep -Seconds 2 }
    if ($q.HasExited -and $q.ExitCode -and (Get-QuickState $written)) {
        Write-Host 'The saved state could not be resumed; booting iOS'
        Remove-QuickState $written
        $q = Start-Qemu @()
    }
} else {
    $q = Start-Qemu @()
}
if ($timeArgs) {
    # pythonw: no console window. It ends with QEMU; on success it writes the disk's mark
    $pyw = @((Join-Path $Work 'tools\python\pythonw.exe'), (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source) |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if ($pyw) {
        $a = @('-I', '-B', "`"$PSScriptRoot\scripts\guest-clock.py`"", '4451', '900', '--pid', $q.Id, '--log', "`"$O\host-time.log`"") + $timeArgs
        if ($written) { $a += @('--state', "`"$(Time-Mark $written)`"") }
        $null = Start-Process -FilePath $pyw -ArgumentList $a
        Write-Host "Giving iOS the PC's $($timeArgs -join ' ') over its console once it is up ($O\host-time.log)"
    } else {
        Write-Host "No Python (the installer's tools\python or pythonw.exe on PATH): iOS keeps its own time zone, region and clock"
    }
}
"started $exe pid $($q.Id) -> $O"

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
#   root-collections.qcow2/.tc     optional: the Collections wallpaper disk (README.md, step 3.6)
#   qemu\                          qemu-sptm built for Windows, with reims-vgpu's DLLs
# Outputs (serial, logs) go to <Work>\runs\<Name>. QMP 127.0.0.1:4453 and HMP 4452 stay open
# for tools; the guest's serial console is on 127.0.0.1:4451.
# The disk, as the iOS 16 launcher: by default iOS writes to a throwaway overlay (-snapshot),
# -Persist keeps its changes in a user overlay on the base image, -Keep writes the base image.
#   Start-iOS26.ps1 [-Work D:\ios26] [-Name w1] [-Wallpaper ios26|collections] [-Persist [-Reset]] [-Keep]
#                   [-Net] [-Page4K] [-NoGl] [-Cpu max,pauth-impdef=on] [-Smp 4|8]
param(
    [string]$Work = $env:ASOFT26_WORK,
    [string]$Name = 'w1',
    # The base disk and its trust cache. -Wallpaper ios26 (default): root.qcow2, iOS 26's own
    # wallpaper (MercuryPoster, drawn by the guest's Metal on the host GPU; needs metal2vulkan's
    # `windows` branch at 56705098 or later). -Wallpaper collections: root-collections.qcow2, the
    # iOS 17 Collections wallpaper of build step 3.6, lighter on the guest's CPU. -Disk/-Tc name
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
    [ValidateSet(4, 8)][int]$Smp = 4
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
foreach ($f in @('fw\bootkc', 'fw\sptm', 'fw\txm', "dtree-smp$Smp", 'rd-shell.hfs')) {
    if (-not (Test-Path (Join-Path $Work $f))) { throw "missing $f in $Work (see README.md, Build)" }
}
foreach ($f in @($Disk, $Tc)) { if (-not (Test-Path $f)) { throw "missing $f" } }
$O = Join-Path $Work "runs\$Name"
New-Item -ItemType Directory -Force $O | Out-Null
$exe = Join-Path $Work 'qemu\qemu-system-aarch64w.exe'
if (-not (Test-Path $exe)) { $exe = Join-Path $Work 'qemu\qemu-system-aarch64.exe' }

# Two QEMUs writing one disk would wreck it (QEMU's image locking does not work on Windows)
$written = if ($Persist) { $UserDisk } elseif ($Keep) { $Disk } else { '' }
if ($written) {
    $leaf = [IO.Path]::GetFileName($written)
    $other = Get-CimInstance Win32_Process -Filter "Name like 'qemu-system%'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($leaf) } | Select-Object -First 1
    if ($other) { throw "iOS is already running on $written (QEMU process $($other.ProcessId)); close that window first" }
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
    if ($Reset -and (Test-Path $UserDisk)) { Remove-Item $UserDisk }
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
# no window-close=off: the research VM has no power key wired, closing quits
$display = 'gtk,show-cursor=on,sidebar=on,show-menubar=off,zoom-to-fit=on'
if (-not $NoGl) { $display += ',gl=on' }
$boot = "serial=3 -v debug=0x14e cpus=$Smp rd=disk0s1 wdt=-1 keepsyms=1 -noprogress launchd_unsecure_cache=1 launchd_disable_all_timeouts=1 aks-endpoint=0 cpu_boot_timeout_secs=30"
$qargs = @(
    '-name', '"ASoftware iOS 26"',
    '-M', 'vresearch,fb=1179x2556,unauth-root=on,pvg=reims,aks-stub=on,amfi-lc-off=on,aks-crypt=on,acm-stub=on,hfs-dp-stub=on',
    '-bootkc', "`"$Work\fw\bootkc`"", '-sptm', "`"$Work\fw\sptm`"", '-txm', "`"$Work\fw\txm`"",
    '-dtree', "`"$Work\dtree-smp$Smp`"", '-tc', "`"$Tc`"", '-ramdisk', "`"$Work\rd-shell.hfs`"",
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
    '-device', 'usb-kbd,bus=xhci.0,port=1,id=ukbd',
    '-device', 'usb-touchscreen,bus=xhci.0,port=2,id=utouch',
    '-device', 'usb-consumer,bus=xhci.0,port=3,id=ucons'
) + $snapshot
if ($Net) { $qargs += @('-nic', 'user,model=virtio-net-pci') }
$q = Start-Process -FilePath $exe -ArgumentList $qargs -PassThru -RedirectStandardError "$O\stderr.log" -RedirectStandardOutput "$O\stdout.log"
"started $exe pid $($q.Id) -> $O"

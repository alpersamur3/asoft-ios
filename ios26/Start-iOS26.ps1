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
#   root.qcow2                     the iOS 26 disk
#   qemu\                          qemu-sptm built for Windows, with reims-vgpu's DLLs
# Outputs (serial, logs) go to <Work>\runs\<Name>. QMP 127.0.0.1:4453 and HMP 4452 stay open
# for tools; the guest's serial console is on 127.0.0.1:4451.
#   Start-iOS26.ps1 [-Work D:\ios26] [-Name w1] [-Disk root.qcow2] [-NoGl] [-Cpu max,pauth-impdef=on] [-Smp 4|8]
param(
    [string]$Work = $env:ASOFT26_WORK,
    [string]$Name = 'w1',
    [string]$Disk = 'root.qcow2',
    [string]$Tc = 'root.tc',
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
$Disk = In-Work $Disk
$Tc = In-Work $Tc
foreach ($f in @('fw\bootkc', 'fw\sptm', 'fw\txm', "dtree-smp$Smp", 'rd-shell.hfs')) {
    if (-not (Test-Path (Join-Path $Work $f))) { throw "missing $f in $Work (see README.md, Build)" }
}
foreach ($f in @($Disk, $Tc)) { if (-not (Test-Path $f)) { throw "missing $f" } }
$O = Join-Path $Work "runs\$Name"
New-Item -ItemType Directory -Force $O | Out-Null
$exe = Join-Path $Work 'qemu\qemu-system-aarch64w.exe'
if (-not (Test-Path $exe)) { $exe = Join-Path $Work 'qemu\qemu-system-aarch64.exe' }
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
    '-cpu', $Cpu, '-smp', "$Smp", '-accel', 'tcg,thread=multi',
    '-drive', "`"file=$Disk,if=none,id=root,cache=writeback,discard=unmap`"", '-device', 'virtio-blk-pci,drive=root',
    '-qmp', 'tcp:127.0.0.1:4453,server=on,wait=off',
    # the touchscreen's port reports PORTSC.DR: iOS takes it as the built-in digitizer
    '-device', 'qemu-xhci,id=xhci,conditional-intr-mapping=on,nonremovable=2',
    '-device', 'usb-kbd,bus=xhci.0,port=1,id=ukbd',
    '-device', 'usb-touchscreen,bus=xhci.0,port=2,id=utouch',
    '-device', 'usb-consumer,bus=xhci.0,port=3,id=ucons'
)
$q = Start-Process -FilePath $exe -ArgumentList $qargs -PassThru -RedirectStandardError "$O\stderr.log" -RedirectStandardOutput "$O\stdout.log"
"started $exe pid $($q.Id) -> $O"

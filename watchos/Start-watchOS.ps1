# ASoftware watchOS launcher: watchOS 27.2 (Apple Watch Series 9) in a drawn watch case, from the work
# folder Install-watchOS.ps1 built it in (the iOS 26 install's, with its watchos\ folder).
#   Start-watchOS.cmd [-Work D:\ios26] [-Snapshot] [-Name RUN] [-NoNet] [-Smp 4|8]
# The mouse is the touchscreen; the wheel over the watch, or a drag on the drawn crown, turns the
# Digital Crown; a click on the crown presses it (hold: Siri); the side button opens Control Center.
# Its own ports (serial console 4471, HMP 4472, QMP 4473): iOS 26 (4451-4453) can run beside it.
# Writes go to watchos\watch.qcow2 (watchos\rootw.qcow2 under it stays as the install made it);
# -Snapshot keeps them in a temporary file instead. -Smp 8: eight CPUs (the device tree dtree-w8, made
# from the iOS 26 install's dtree-smp8). Prints "started EXE pid N -> RUN FOLDER".
param(
    [string]$Work = '',
    [string]$Config = (Join-Path $env:LOCALAPPDATA 'ASoftware iOS 26\ios26.config.json'),
    [string]$Name = '',
    [string]$Disk = 'watchos\watch.qcow2',
    [string]$Tc = 'watchos\rootw.tc',
    [string]$Exe = '',
    [ValidateSet(4, 8)][int]$Smp = 4,
    [switch]$Snapshot,
    [switch]$NoNet,
    [switch]$Keep,
    [switch]$FirstBoot,
    [string[]]$Extra = @()
)
$ErrorActionPreference = 'Stop'
if (-not $Work) {
    if (Test-Path $Config) { try { $Work = [string](Get-Content $Config -Raw | ConvertFrom-Json).Work } catch { } }
}
$installIt = 'run Install-ASoftware.cmd and answer yes to watchOS (it is built on iOS 26), or watchos\Install-watchOS.cmd on an iOS 26 install'
if (-not $Work -or -not (Test-Path -LiteralPath ([IO.Path]::Combine($Work, 'watchos')))) {
    throw "no watchOS install found$(if ($Work) { " in $Work" }): $installIt (or give -Work)"
}
# absolute: QEMU starts in it, and the paths it is given must not be relative to it
$Work = (Resolve-Path -LiteralPath $Work).Path.TrimEnd('\')
function In-Work([string]$rel) { if ([IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $Work $rel } }
if (-not $Exe) {
    $Exe = In-Work 'qemu-watch\qemu-system-aarch64w.exe'
    if (-not (Test-Path $Exe)) { $Exe = In-Work 'qemu-watch\qemu-system-aarch64.exe' }
}
$dtree = if ($Smp -eq 8) { 'watchos\dtree-w8' } else { 'watchos\dtree-w' }
$goOn = 'run watchos\Install-watchOS.cmd (or Install-ASoftware.cmd) again: it goes on where it stopped'
$need = @($Exe, (In-Work 'watchos\bootkc-w'), (In-Work $dtree), (In-Work 'fw\sptm'), (In-Work 'fw\txm'),
          (In-Work 'rd-shell.hfs'), (In-Work $Disk), (In-Work $Tc))
if ($Disk -ceq 'watchos\watch.qcow2') { $need += @((In-Work 'watchos\rootw-p.qcow2'), (In-Work 'watchos\rootw.qcow2')) }
foreach ($n in $need) { if (-not (Test-Path $n)) { throw "$n is missing: $goOn" } }
# the install's own disk once its last disk step has finished on it (a redo of a disk step retires it);
# -FirstBoot: Install-watchOS.ps1's first boot, which comes before that step
if ($Disk -ceq 'watchos\watch.qcow2' -and -not $FirstBoot -and -not (Test-Path (In-Work 'watchos\watch.qcow2.ready'))) {
    throw "the watchOS install is not finished (watchos\watch.qcow2 has not been through its activation step): $goOn"
}
# one watch at a time: the ports are fixed
$busy = @(Get-NetTCPConnection -State Listen -LocalPort 4471, 4472, 4473 -ErrorAction SilentlyContinue)
if ($busy) { throw ("ports 4471-4473 are in use (pid {0}): is a watch running already?" -f (($busy | ForEach-Object OwningProcess | Sort-Object -Unique) -join ', ')) }

if (-not $Name) { $Name = Get-Date -Format 'yyyyMMdd-HHmmss' }
$O = In-Work "watchos\runs\$Name"
if (-not $Keep -and (Test-Path $O)) { Remove-Item $O -Recurse -Force }
New-Item -ItemType Directory -Force $O, (In-Work 'watchos\tmp') | Out-Null
$env:TMPDIR = In-Work 'watchos\tmp'; $env:TEMP = $env:TMPDIR; $env:TMP = $env:TMPDIR
$env:ASOFT_PAGE_BITS = '14'
$env:REIMS_VGPU_LOG = 'warn'
$env:ASOFT_SUBTITLE = 'watchOS 27.2 (24S118)'
$boot = "serial=3 -v debug=0x14e cpus=$Smp rd=disk0s1 wdt=-1 keepsyms=1 -noprogress launchd_unsecure_cache=1 " +
        'launchd_disable_all_timeouts=1 aks-endpoint=0 cpu_boot_timeout_secs=30'
function Q([string]$a) { '"' + $a + '"' }
$qargs = @(
    '-name', (Q 'ASoftware watchOS 27.2'),
    # ppi=326: the 41 mm Series 9's screen class (MobileGestalt's table needs 352x430 @2x at 326 ppi)
    '-M', 'vresearch,fb=352x430,ppi=326,unauth-root=on,pvg=reims,aks-stub=on,amfi-lc-off=on,aks-crypt=on,acm-stub=on,hfs-dp-stub=on',
    '-bootkc', (Q (In-Work 'watchos\bootkc-w')), '-sptm', (Q (In-Work 'fw\sptm')), '-txm', (Q (In-Work 'fw\txm')),
    '-dtree', (Q (In-Work $dtree)), '-tc', (Q (In-Work $Tc)), '-ramdisk', (Q (In-Work 'rd-shell.hfs')),
    '-args', (Q $boot),
    # the GTK side bar with the drawn watch: case, crown and side button, hanging from the window
    '-display', 'gtk,show-cursor=on,zoom-to-fit=on,gl=on,sidebar=on,show-menubar=off',
    '-monitor', 'tcp:127.0.0.1:4472,server=on,wait=off',
    '-parallel', 'none',
    '-chardev', (Q "socket,id=con,host=127.0.0.1,port=4471,server=on,wait=off,logfile=$O\serial.log"),
    '-serial', 'chardev:con', '-d', 'guest_errors,unimp', '-D', (Q "$O\qemu.log"),
    '-cpu', 'max,pauth-impdef=on', '-smp', "$Smp", '-accel', 'tcg,thread=multi,tb-size=2048',
    '-drive', (Q ("file=" + (In-Work $Disk) + ",if=none,id=root,cache=writeback,discard=unmap")), '-device', 'virtio-blk-pci,drive=root',
    '-qmp', 'tcp:127.0.0.1:4473,server=on,wait=off',
    '-device', 'qemu-xhci,id=xhci,conditional-intr-mapping=on,nonremovable=2',
    '-device', 'usb-kbd,bus=xhci.0,port=1,id=ukbd,idle-reports=off',
    '-device', 'usb-touchscreen,bus=xhci.0,port=2,id=utouch',
    # the side button is Consumer Help (0x95) on a watch; the crown's rotation is its own device
    '-device', 'usb-consumer,bus=xhci.0,port=3,id=ucons,power-usage=0x95',
    '-device', 'usb-crown,bus=xhci.0,port=4,id=ucrown'
)
if (-not $NoNet) { $qargs += @('-nic', 'user,model=virtio-net-pci') }
if ($Snapshot) { $qargs += '-snapshot' }
$qargs += $Extra
Set-Content "$O\cmdline.txt" ($qargs -join ' ')
$q = Start-Process -FilePath $Exe -ArgumentList $qargs -PassThru -WorkingDirectory $Work `
    -RedirectStandardError "$O\stderr.log" -RedirectStandardOutput "$O\stdout.log"
$null = $q.Handle
# a QEMU that refuses its arguments or a disk ends at once: say why (the .cmd window then stays open)
if ($q.WaitForExit(3000)) {
    $why = @(Get-Content "$O\stderr.log" -Tail 8 -ErrorAction SilentlyContinue) -join "`n"
    throw "QEMU ended at once (exit $($q.ExitCode)); $O\stderr.log:`n$why"
}
"started $Exe pid $($q.Id) -> $O"

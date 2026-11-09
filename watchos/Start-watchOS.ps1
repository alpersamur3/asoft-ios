# ASoftware watchOS launcher: watchOS 27.2 (Apple Watch Series 9) in a drawn watch case, from the work
# folder Install-watchOS.ps1 built it in (the iOS 26 install's, with its watchos\ folder).
#   Start-watchOS.cmd [-Work D:\ios26] [-Snapshot] [-Name RUN] [-NoNet] [-Smp 4|8] [-NoQuickBoot] [-NoAutoSave]
# The mouse is the touchscreen; the wheel over the watch, or a drag on the drawn crown, turns the
# Digital Crown; a click on the crown presses it (hold: Siri); the side button opens Control Center.
# Its own ports (serial console 4471, HMP 4472, QMP 4473): iOS 26 (4451-4453) can run beside it.
# Writes go to watchos\watch.qcow2 (watchos\rootw.qcow2 under it stays as the install made it);
# -Snapshot keeps them in a temporary file instead. -Smp 8: eight CPUs (the device tree dtree-w8, made
# from the iOS 26 install's dtree-smp8). Prints "started EXE pid N -> RUN FOLDER".
# Quick boot, as iOS 26's launcher: closing the window saves the machine (memory and devices) into
# watch.qcow2 as its snapshot asoft-quick, and the next start resumes it in seconds instead of booting
# (about 6 minutes to the face); QEMU deletes the state once the machine runs, so it is never resumed
# twice. After a cold start, Watch-AutoSave.ps1 (hidden) saves the same state once the watch is past
# its slow first minutes (the face shown for 5 minutes, 15 minutes after the start) and nobody is
# using it, so a crash or a power cut comes back to a settled watch too.
# -NoQuickBoot boots every time (and drops a saved state); -NoAutoSave keeps only the save at closing.
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
    [switch]$NoQuickBoot,
    [switch]$NoAutoSave,
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

# Quick boot (above). Not with -Snapshot (the disk is not written: a state on it stays for the next
# start) nor in Install-watchOS.ps1's first boot.
$diskPath = In-Work $Disk
$qemuImg = Join-Path (Split-Path $Exe) 'qemu-img.exe'
$quickSnapshot = 'asoft-quick'
# GB a saved state takes on the disk's drive (measured: 3.74 GiB): the first save needs that much free
$stateGB = 4.0
function Get-QuickState {
    if (-not (Test-Path $qemuImg)) { return $null }
    # (-U: QEMU may have the disk open, as while a state is being resumed)
    $ErrorActionPreference = 'Continue'
    @(& $qemuImg snapshot -l -U $diskPath 2>$null | Where-Object { "$_" -cmatch "\s$quickSnapshot\s" })
}
function Remove-QuickState {
    if (-not (Get-QuickState)) { return }
    $ErrorActionPreference = 'Continue'     # (Windows PowerShell 5.1 turns a native tool's stderr into errors)
    $null = & $qemuImg snapshot -d $quickSnapshot $diskPath 2>&1
}
$quickBoot = -not $Snapshot -and -not $NoQuickBoot -and -not $FirstBoot -and (Test-Path $qemuImg)
$savedState = if (-not $Snapshot) { Get-QuickState }
if ($quickBoot -and -not $savedState) {
    $free = ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($diskPath))).AvailableFreeSpace / 1e9
    if ($free -lt $stateGB + 1) {
        Write-Host ("{0:N1} GB free on {1}: a saved state needs about {2} GB, so quick boot is off this time" -f $free, [IO.Path]::GetPathRoot($diskPath), $stateGB) -ForegroundColor Yellow
        $quickBoot = $false
    }
}
if ($savedState -and -not $quickBoot) {
    # the disk goes on without it: resuming it later would undo what this run writes
    Remove-QuickState
    $savedState = $null
    Write-Host 'Dropped the saved state (quick boot is off)'
}

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
    '-display', ('gtk,show-cursor=on,zoom-to-fit=on,gl=on,sidebar=on,show-menubar=off' + $(if ($quickBoot) { ',quick-boot=on' } else { '' })),
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
function Start-Qemu([string[]]$more) {
    $p = Start-Process -FilePath $Exe -ArgumentList ($qargs + $more) -PassThru -WorkingDirectory $Work `
        -RedirectStandardError "$O\stderr.log" -RedirectStandardOutput "$O\stdout.log"
    $null = $p.Handle       # (ExitCode, once it has ended, needs the handle taken)
    $p
}
$resumed = $false
if ($savedState) {
    Write-Host 'Resuming the saved state (saved when the window was closed, or by itself after a start)'
    $q = Start-Qemu @('-loadvm', $quickSnapshot)
    # until the machine runs (QEMU then deletes the state) or QEMU ends: one that cannot load the state
    # (another QEMU build, other options) ends with the state still there; then drop it and boot
    $until = (Get-Date).AddMinutes(5)
    while (-not $q.HasExited -and (Get-Date) -lt $until -and (Get-QuickState)) { Start-Sleep -Seconds 2 }
    if ($q.HasExited -and (Get-QuickState)) {
        Write-Host "The saved state could not be resumed (exit $($q.ExitCode), $O\stderr-resume.log); booting watchOS" -ForegroundColor Yellow
        Move-Item "$O\stderr.log" "$O\stderr-resume.log" -Force -ErrorAction SilentlyContinue
        Remove-QuickState
        $q = Start-Qemu @()
    } else {
        $resumed = -not $q.HasExited
    }
} else {
    $q = Start-Qemu @()
}
# a QEMU that refuses its arguments or a disk ends at once: say why (the .cmd window then stays open)
if ($q.WaitForExit(3000)) {
    $why = @(Get-Content "$O\stderr.log" -Tail 8 -ErrorAction SilentlyContinue) -join "`n"
    throw "QEMU ended at once (exit $($q.ExitCode)); $O\stderr.log:`n$why"
}
if ($quickBoot -and -not $resumed -and -not $NoAutoSave) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', (Q (Join-Path $PSScriptRoot 'Watch-AutoSave.ps1')),
           '-QemuPid', "$($q.Id)", '-Disk', (Q $diskPath), '-Log', (Q "$O\autosave.log"), '-StateGB', "$stateGB")
    $null = Start-Process powershell.exe -ArgumentList $a -WindowStyle Hidden
    Write-Host ('After a cold start the watch is slow for its first minutes (the face after about 6 to 9). Its state ' +
                'is saved about 15 minutes after the start, once you are not using it, and again when you close ' +
                "the window: the next start goes on from there in seconds ($O\autosave.log).")
} elseif ($quickBoot) {
    Write-Host 'Quick boot: closing the window saves the watch; the next start goes on from there.'
}
"started $Exe pid $($q.Id) -> $O"

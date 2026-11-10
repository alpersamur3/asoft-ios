# ASoftware watchOS launcher: watchOS 27.2 (Apple Watch Series 9) in a drawn watch case, from the work
# folder Install-watchOS.ps1 built it in (the base it shares with iOS 26, with its watchos\ folder).
#   Start-watchOS.cmd [-Work D:\ios26] [-Snapshot] [-Name RUN] [-NoNet] [-Smp 4|8] [-NoQuickBoot] [-NoAutoSave]
# The mouse is the touchscreen; the wheel over the watch, or a drag on the drawn crown, turns the
# Digital Crown; a click on the crown presses it (hold: Siri); the side button opens Control Center.
# Its own ports (serial console 4471, HMP 4472, QMP 4473): iOS 26 (4451-4453) can run beside it.
# Writes go to watchos\watch.qcow2 (watchos\rootw.qcow2 under it stays as the install made it);
# -Snapshot keeps them in a temporary file instead. -Smp 8: eight CPUs (the device tree dtree-w8, made
# from the iOS 26 install's dtree-smp8). Prints "started EXE pid N -> RUN FOLDER".
#   [-RamMiB 3072]  the watch's RAM (QEMU takes it from the device tree: ..\ios26\scripts\dt-ram.ps1)
# Quick boot, as iOS 26's launcher (on unless -NoQuickBoot; -QuickBoot is accepted and does nothing):
# closing the window saves the machine (memory and devices) into watch.qcow2 as its snapshot asoft-quick,
# and the next start resumes it in seconds instead of booting (about 6 minutes to the face). After a cold
# start on a disk with no save yet, Watch-AutoSave.ps1 (hidden) saves the same state once the watch is past
# its slow first minutes (the face shown for 5 minutes, 15 minutes after the start) and nobody is using it,
# so a crash or a power cut comes back to a settled watch too. A save is resumed once; then it stays as a way back
# (-LoadState asoft-quick goes back to it) until the next save replaces it, and a start boots the watch
# from its disk as it was left. -NoQuickBoot boots every time (a save stays as the way back);
# -NoAutoSave keeps only the save at closing. [-LoadState NAME] resumes another saved state (the side
# bar's Save state makes them). A state loads only with its own vCPUs and RAM.
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
    [int]$RamMiB = 0,
    [switch]$QuickBoot,
    [switch]$NoQuickBoot,
    [switch]$NoAutoSave,
    [string]$LoadState = '',
    [string[]]$Extra = @()
)
$ErrorActionPreference = 'Stop'
if (-not $Work) {
    if (Test-Path $Config) { try { $Work = [string](Get-Content $Config -Raw | ConvertFrom-Json).Work } catch { } }
}
$installIt = 'install it with Install-ASoftware.cmd (watchOS alone needs only the base it shares with iOS 26, not iOS 26), or watchos\Install-watchOS.cmd -Work <folder>'
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
# another RAM size: the tree with it, made once next to the tree (again when the tree is newer)
if ($RamMiB) {
    $dtRam = Join-Path $PSScriptRoot '..\ios26\scripts\dt-ram.ps1'
    $has = & $dtRam -In (In-Work $dtree) -Read
    if ([int]$has -ne $RamMiB) {
        $src = Get-Item (In-Work $dtree)
        $dtree = "$dtree-$($RamMiB)m"
        if (-not (Test-Path (In-Work $dtree)) -or (Get-Item (In-Work $dtree)).LastWriteTime -lt $src.LastWriteTime) {
            & $dtRam -In $src.FullName -Out (In-Work $dtree) -MiB $RamMiB
        }
        Write-Host "Guest RAM $RamMiB MiB ($dtree)"
    }
}
# saved states: in the disk the watch writes (not with -Snapshot), through the watch QEMU's qemu-img
$qemuImg = @((Join-Path (Split-Path $Exe) 'qemu-img.exe'), (In-Work 'qemu\qemu-img.exe')) | Where-Object { Test-Path $_ } | Select-Object -First 1
function Has-State([string]$name) {
    if (-not $qemuImg) { return $false }
    $ErrorActionPreference = 'Continue'     # (Windows PowerShell 5.1 turns a native tool's stderr into errors)
    [bool](& $qemuImg snapshot -l -U (In-Work $Disk) 2>$null | Where-Object { "$_" -cmatch "^\s*\d+\s+$([regex]::Escape($name))\s" })
}
if ($LoadState -and $Snapshot) { throw '-LoadState resumes a state of the watch''s disk: not with -Snapshot' }
if ($LoadState -and -not (Has-State $LoadState)) { throw "no saved state $LoadState on $(In-Work $Disk)" }
# one watch at a time: the ports are fixed
$busy = @(Get-NetTCPConnection -State Listen -LocalPort 4471, 4472, 4473 -ErrorAction SilentlyContinue)
if ($busy) { throw ("ports 4471-4473 are in use (pid {0}): is a watch running already?" -f (($busy | ForEach-Object OwningProcess | Sort-Object -Unique) -join ', ')) }

# Quick boot (above). Not with -Snapshot (the disk is not written: a state on it stays for the next
# start) nor in Install-watchOS.ps1's first boot.
$diskPath = In-Work $Disk
$quickSnapshot = 'asoft-quick'
# GB a saved state takes on the disk's drive (measured: 3.74 GiB): the first save needs that much free
$stateGB = 4.0
# The quick save is resumed by itself once. From that start on (and from any start that does not
# resume it) it stays as the way back: <disk>.quick-used names it by its id and time (qemu-img's JSON:
# no time zone in them; Start-iOS26.ps1 writes the same), and only -LoadState asoft-quick goes back to
# it. The next save (closing the window) replaces it with a new time, which is resumed again.
function Quick-Key {
    if (-not $qemuImg -or -not (Test-Path $diskPath)) { return '' }
    # (-U: QEMU may have the disk open)
    $ErrorActionPreference = 'Continue'     # (Windows PowerShell 5.1 turns a native tool's stderr into errors)
    try {
        $j = (& $qemuImg info --output=json -U $diskPath 2>$null) -join "`n" | ConvertFrom-Json
        $s = @($j.snapshots) | Where-Object { $_ -and $_.name -ceq $quickSnapshot } | Select-Object -First 1
        if ($s) { "$($s.id) $($s.'date-sec') $($s.'date-nsec')" } else { '' }
    } catch { '' }
}
$quickUsed = "$diskPath.quick-used"
# the quick save's key when no start resumed it yet, else ''
function Get-QuickState {
    $k = Quick-Key
    $used = "$(Get-Content $quickUsed -TotalCount 1 -ErrorAction SilentlyContinue)".Trim()
    if ($k -and $k -cne $used) { $k } else { '' }
}
# keeps the quick save as the way back: no start resumes it by itself any more
function Keep-WayBack {
    $k = Quick-Key
    if ($k) { Set-Content -Path $quickUsed -Value $k -Encoding ASCII }
}
function Remove-QuickState {
    if (Quick-Key) {
        $ErrorActionPreference = 'Continue'
        $null = & $qemuImg snapshot -d $quickSnapshot $diskPath 2>&1
    }
    Remove-Item $quickUsed -ErrorAction SilentlyContinue
}
$quickBoot = -not $Snapshot -and -not $NoQuickBoot -and -not $FirstBoot -and [bool]$qemuImg
$savedState = if (-not $Snapshot) { Get-QuickState }
# (a new save of the same name takes the old one's room: only the first needs it free)
if ($quickBoot -and -not (Quick-Key)) {
    $free = ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($diskPath))).AvailableFreeSpace / 1e9
    if ($free -lt $stateGB + 1) {
        Write-Host ("{0:N1} GB free on {1}: a saved state needs about {2} GB, so quick boot is off this time" -f $free, [IO.Path]::GetPathRoot($diskPath), $stateGB) -ForegroundColor Yellow
        $quickBoot = $false
    }
}
if ($savedState -and -not $quickBoot -and -not $LoadState) {
    Write-Host 'Quick boot is off: watchOS boots, and the saved state stays as a way back (-LoadState asoft-quick)'
}
$resume = if ($LoadState) { $LoadState } elseif ($savedState -and $quickBoot) { $quickSnapshot } else { '' }

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
# ppi=326: the 41 mm Series 9's screen class (MobileGestalt's table needs 352x430 @2x at 326 ppi)
# loadvm-date (a QEMU that has it): a resumed state's clock is set by "date" on the root shell (the serial console),
# as iOS 26's and visionOS's are, and the machine's own clock stays where it was saved: no timeout that was running
# at the save runs out at the load (the watch at its face took the older way, the clock moved on, without harm)
$machine = 'vresearch,fb=352x430,ppi=326,unauth-root=on,pvg=reims,aks-stub=on,amfi-lc-off=on,aks-crypt=on,acm-stub=on,hfs-dp-stub=on'
$probeExe = Join-Path (Split-Path $Exe) 'qemu-system-aarch64.exe'
if (Test-Path $probeExe) {
    $ErrorActionPreference = 'Continue'     # (Windows PowerShell 5.1 turns a native tool's stderr into errors)
    $machineProbe = @(& $probeExe -M 'vresearch,help' 2>&1 | ForEach-Object { "$_" })
    $ErrorActionPreference = 'Stop'
    if ($machineProbe | Where-Object { $_ -cmatch '\bloadvm-date=' }) { $machine += ',loadvm-date=on' }
}
$qargs = @(
    '-name', (Q 'ASoftware watchOS 27.2'),
    '-M', $machine,
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
function Start-Watch([string[]]$more) {
    # (no extra arguments arrive as a null element, which Start-Process refuses)
    $all = @($qargs) + @($more | Where-Object { $_ })
    Set-Content "$O\cmdline.txt" ($all -join ' ')
    $p = Start-Process -FilePath $Exe -ArgumentList $all -PassThru -WorkingDirectory $Work `
        -RedirectStandardError "$O\stderr.log" -RedirectStandardOutput "$O\stdout.log"
    $null = $p.Handle       # (ExitCode, once it has ended, needs the handle taken)
    $p
}
# QEMU's own reason in a log (another CPU count, RAM size or set of devices than the save's), not its info lines
function Qemu-Why([string]$log) {
    @(Get-Content $log -ErrorAction SilentlyContinue |
      Where-Object { $_ -match 'qemu-system-aarch64w?\.exe: ' -and $_ -notmatch '\.exe: info: ' } |
      ForEach-Object { $_ -replace '^.*?qemu-system-aarch64w?\.exe: ', '' }) | Select-Object -First 2
}
# From here on the disk goes on from this start: a quick save, resumed now or not, is the way back
if (-not $Snapshot) { Keep-WayBack }
$resumed = $false
if ($resume) {
    Write-Host $(if ($LoadState) { "Resuming the saved state $LoadState" } else { 'Resuming the saved state (saved when the window was closed, or by itself after a start)' })
    $q = Start-Watch @('-loadvm', $resume)
    # until the machine runs, or QEMU ends first: then the state did not load (another QEMU build, other
    # options), at most 5 min
    $until = (Get-Date).AddMinutes(5)
    $ran = $false
    while (-not $q.HasExited -and (Get-Date) -lt $until -and -not ($ran = Qmp-Running 4473)) { Start-Sleep -Seconds 2 }
    if (-not $ran -and $q.HasExited) {
        Move-Item "$O\stderr.log" "$O\stderr-resume.log" -Force -ErrorAction SilentlyContinue
        $why = Qemu-Why "$O\stderr-resume.log"
        $said = "The saved state $resume could not be resumed (exit $($q.ExitCode)" + $(if ($why) { ': ' + ($why -join '; ') } else { '' }) + "; $O\stderr-resume.log)"
        # a state named with -LoadState is kept; the quick boot's goes, and the watch boots
        if ($LoadState) { throw "$said; it is kept" }
        Write-Host "$said; booting watchOS" -ForegroundColor Yellow
        Remove-QuickState
        $q = Start-Watch @()
    } else {
        $resumed = -not $q.HasExited
    }
} else {
    $q = Start-Watch @()
}
# a QEMU that refuses its arguments or a disk ends at once: say why (the .cmd window then stays open)
if ($q.WaitForExit(3000)) {
    $why = @(Get-Content "$O\stderr.log" -Tail 8 -ErrorAction SilentlyContinue) -join "`n"
    throw "QEMU ended at once (exit $($q.ExitCode)); $O\stderr.log:`n$why"
}
# The automatic save is for a disk with no save yet. A save already there stays as the way back, and only
# closing the window replaces it. (A save that failed to load above is gone by now: that start gets one.)
if ($quickBoot -and -not $resumed -and -not $NoAutoSave -and -not (Quick-Key)) {
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

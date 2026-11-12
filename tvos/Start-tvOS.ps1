# ASoftware tvOS launcher: tvOS 27.2 (Apple TV 4K, 3rd generation, AppleTV14,1) on -M vresearch, from the work
# folder Install-tvOS.ps1 built it in (the iOS 26 install's, with its tvos\ folder), on the install's one QEMU
# (<work>\qemu, which runs iOS 16, iOS 26, watchOS and visionOS too).
#   Start-tvOS.cmd [-Work D:\ios26] [-Cpus 4|6|8] [-Resolution 2160|1080] [-NoNet] [-NoFrame] [-Snapshot]
#                  [-Name RUN] [-NoQuickBoot] [-NoAutoSave] [-LoadState NAME] [-HostGpu auto|integrated|discrete]
#                  [-PrintOnly]
# The window is the TV's picture, 3840x2160 (scaled to the window; F11 full screen). On a QEMU with the TV window
# (usb-consumer tv-remote, branch asoft-tv) it is drawn as a TV with a Siri Remote beside it, whose parts can be
# clicked (F9 or -NoFrame: the picture alone); on an older one the window is the plain one. The keyboard is the
# remote: the arrow keys move the focus, Return selects, Esc goes back (Menu); F1 the TV button, F2 power, F3/F4
# volume, and with the TV window F5 Play/Pause, F6 Mute, F7 Siri. tvOS reaches Home in about 75-96 s on 4 vCPUs
# (measured on the hand-built disk; 73 s on visionOS's QEMU package).
# Its own ports (serial console 4501, HMP 4502, QMP 4503): one tvOS at a time; iOS 26 (4451-4453), watchOS
# (4471-4473) and visionOS (4481-4483) can run beside it.
#   -Cpus 4|6|8      vCPUs (default 4, the measured count), each with its own device tree (dtree-t, -t6, -t8);
#                    6 and 8 are made like 4 but not measured on tvOS
#   -RamMiB N        the guest's RAM (default: the tree's 4096 MiB; QEMU takes it from the device tree:
#                    ..\ios26\scripts\dt-ram.ps1 writes <tree>-<N>m beside it). Not measured on tvOS.
#   -Resolution      2160 (default, the measured mode) or 1080: see $Modes below (1080 is not wired in yet)
#   -Ppi N           the machine's ppi= (a QEMU that has it); default: the mode's (none for 2160)
#   -NoNet           no network
#   -NoFrame         the TV window starts with the picture alone, without the TV and the remote (ASOFT_FRAME=0)
#   -HostGpu         auto|integrated|discrete: the PC's GPU tvOS draws on (as Start-iOS26.ps1's)
#   -NoTlbiFilter    QEMU's x-tlbi-filter off (it is on when the QEMU has it, as iOS 26's and watchOS's starts)
#   -Snapshot        writes go to a temporary file, the disk stays as it was
#   -Disk/-Tc        another disk (relative to the work folder) and trust cache: Install-tvOS.ps1's boots
#                    (no quick boot on such a disk: it boots every time)
#   -PrintOnly       print the QEMU command line (and what the start would do) without starting QEMU or writing
#                    anything
# Quick boot, as the other launchers (on unless -NoQuickBoot, not with -Snapshot): closing the window saves the
# machine (memory and devices, about the guest's RAM) into the disk as its snapshot asoft-quick, and the next start
# resumes it in seconds instead of booting. A save is resumed once; then it stays as a way back (-LoadState
# asoft-quick goes back to it) until the next save replaces it, and a start boots tvOS from its disk as it was left.
# -LoadState NAME resumes another saved state (the side bar's Save state makes them). A state loads only with its
# own -Cpus, RAM and resolution. After a cold start on a disk with no save yet, Tv-AutoSave.ps1 (hidden) saves the
# same state once Home has been up a while and nobody is using tvOS (-NoAutoSave keeps only the save at closing).
# Writes go to the disk's own layer; the layers under it stay as the install made them. Each start keeps its logs
# in tvos\runs\<Name> (serial.log, qemu.log, stderr.log, cmdline.txt). Prints "started EXE pid N -> RUN FOLDER".
param(
    [string]$Work = '',
    [string]$Config = (Join-Path $env:LOCALAPPDATA 'ASoftware iOS 26\ios26.config.json'),
    [string]$Name = '',
    [ValidateSet(4, 6, 8)][int]$Cpus = 4,
    [ValidateSet('2160', '1080')][string]$Resolution = '2160',
    [int]$RamMiB = 0,
    [ValidateRange(0, 1000)][int]$Ppi = 0,
    [switch]$NoNet,
    [switch]$NoFrame,
    [switch]$Snapshot,
    [switch]$Keep,
    [switch]$NoQuickBoot,
    [switch]$NoAutoSave,
    [switch]$NoTlbiFilter,
    # at most so many of tvOS's frames a second (0: all)
    [ValidateRange(0, 120)][int]$MaxFps = 0,
    [string]$LoadState = '',
    [string]$Disk = '',
    [string]$Tc = '',
    [string]$Exe = '',
    [ValidateSet('auto', 'integrated', 'discrete')][string]$HostGpu = 'auto',
    [ValidateSet('error', 'warn', 'info', 'debug')][string]$GpuLog = 'warn',
    [ValidateRange(256, 8192)][int]$TbMiB = 2048,
    [switch]$PrintOnly,
    [string[]]$Extra = @()
)
$ErrorActionPreference = 'Stop'

# --- The TV window's skin ---------------------------------------------------------------------------
# The one place the window is told it shows a TV: this property of the usb-consumer device (=on), with the GTK
# display's side bar (sidebar=on, below). The window then draws the picture as a TV's screen with a Siri Remote
# beside it, and the device gets the remote's Play/Pause, Mute and Siri buttons. Only the QEMU built from branch
# asoft-tv has it: the start probes the QEMU for it (as for x-tlbi-filter) and gives the plain device without it.
$SkinProp = 'tv-remote'

# --- HOOK: the output modes (-Resolution) -----------------------------------------------------------
# Each mode's frame buffer, its device trees (one per vCPU count), the user disk, its trust cache and the machine's
# ppi (0: none). 2160 is the mode the installer builds and tvOS was measured in (3840x2160, display-scale 2).
# 1080 is a hook for the 1080p recipe (a tree with scale 1, dt-res.py; a disk whose QuartzCore takes the hardware
# scale rule, and that disk's own trust cache): its files are not made by this installer yet, so a start in it
# says what is missing and stops. Wiring it in = making these files (and the names here, if they differ).
$Modes = @{
    '2160' = @{ Fb = '3840x2160'; Ppi = 0; Disk = 'tvos\tv.qcow2'; Tc = 'tvos\roott.tc'; Measured = $true
                Trees = @{ 4 = 'tvos\dtree-t'; 6 = 'tvos\dtree-t6'; 8 = 'tvos\dtree-t8' } }
    '1080' = @{ Fb = '1920x1080'; Ppi = 0; Disk = 'tvos\tv-1080.qcow2'; Tc = 'tvos\roott-1080.tc'; Measured = $false
                Trees = @{ 4 = 'tvos\dtree-t-1080'; 6 = 'tvos\dtree-t6-1080'; 8 = 'tvos\dtree-t8-1080' } }
}
$mode = $Modes[$Resolution]
# tvOS's ports: serial console, HMP, QMP
$TvPorts = @(4501, 4502, 4503)

if (-not $Work) {
    if (Test-Path $Config) { try { $Work = [string](Get-Content $Config -Raw | ConvertFrom-Json).Work } catch { } }
}
$installIt = 'run Install-ASoftware.cmd and answer yes to tvOS (it is built on iOS 26''s base), or tvos\Install-tvOS.cmd on an iOS 26 install'
if (-not $Work -or -not (Test-Path -LiteralPath ([IO.Path]::Combine($Work, 'tvos')))) {
    throw "no tvOS install found$(if ($Work) { " in $Work" }): $installIt (or give -Work)"
}
# absolute: QEMU starts in it, and the paths it is given must not be relative to it
$Work = (Resolve-Path -LiteralPath $Work).Path.TrimEnd('\')
function In-Work([string]$rel) { if ([IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $Work $rel } }
if (-not $Exe) {
    $Exe = In-Work 'qemu\qemu-system-aarch64w.exe'
    if (-not (Test-Path $Exe)) { $Exe = In-Work 'qemu\qemu-system-aarch64.exe' }
}
$userDisk = -not $Disk
if (-not $Disk) { $Disk = $mode.Disk }
if (-not $Tc) { $Tc = $mode.Tc }
$tree = $mode.Trees[$Cpus]
$goOn = 'run tvos\Install-tvOS.cmd (or Install-ASoftware.cmd) again: it goes on where it stopped'
$need = @($Exe, (In-Work 'tvos\bootkc-t'), (In-Work $tree), (In-Work 'fw\sptm'), (In-Work 'fw\txm'),
          (In-Work 'rd-shell.hfs'), (In-Work $Disk), (In-Work $Tc))
# the install's own disk once its disks step has made it (a redo of a disk step retires it)
if ($userDisk) { $need += (In-Work $Disk) + '.ready' }
$missing = @($need | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missing -and -not $mode.Measured) {
    throw ("-Resolution $Resolution is not wired in yet: it needs files this install does not make (" +
           (($missing | ForEach-Object { $_.Replace("$Work\", '') }) -join ', ') + '). Start without -Resolution (3840x2160)')
}
foreach ($n in $missing) {
    if ($userDisk -and $n -ceq ((In-Work $Disk) + '.ready')) {
        throw "the tvOS install is not finished ($Disk has not been through its disks step): $goOn"
    }
    throw "$n is missing: $goOn"
}
# another RAM size: the tree with it, made once next to the tree (again when the tree is newer)
$ramGiB = 4.0
if ($RamMiB) {
    $dtRam = Join-Path $PSScriptRoot '..\ios26\scripts\dt-ram.ps1'
    $has = & $dtRam -In (In-Work $tree) -Read
    if ([int]$has -ne $RamMiB) {
        $src = Get-Item (In-Work $tree)
        $tree = "$tree-$($RamMiB)m"
        if (-not (Test-Path (In-Work $tree)) -or (Get-Item (In-Work $tree)).LastWriteTime -lt $src.LastWriteTime) {
            if ($PrintOnly) { Write-Host "(would write $(In-Work $tree) with dt-ram.ps1)" -ForegroundColor DarkGray }
            else { & $dtRam -In $src.FullName -Out (In-Work $tree) -MiB $RamMiB }
        }
        Write-Host "Guest RAM $RamMiB MiB ($tree)"
    }
    $ramGiB = $RamMiB / 1024
}

# What tvOS needs of the QEMU: the build the installer's qemu step put in <work>\qemu. The probes have a time limit,
# as Install-tvOS.ps1's: a console exe that hangs (a missing-DLL dialog, an antivirus hold) must not hold the start
# for ever. Its output, or '' when it did not end in time (then it is stopped by its own PID, and what the probe
# looks for counts as not there)
function Qemu-Probe([string]$path, [string[]]$argv, [int]$ms = 20000) {
    $psi = New-Object Diagnostics.ProcessStartInfo $path
    $psi.Arguments = ($argv | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    try { $p = [Diagnostics.Process]::Start($psi) } catch { return '' }
    $err = $p.StandardError.ReadToEndAsync(); $out = $p.StandardOutput.ReadToEndAsync()
    if (-not $p.WaitForExit($ms)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; $null = $p.WaitForExit(5000); return '' }
    $out.Result + "`n" + $err.Result
}
$probeExe = Join-Path (Split-Path $Exe) 'qemu-system-aarch64.exe'
if (-not (Test-Path $probeExe)) { $probeExe = $Exe }
$machineHelp = Qemu-Probe $probeExe @('-M', 'vresearch,help')
if ($machineHelp -cnotmatch '\bunauth-root=') {
    throw "$(Split-Path $Exe) is not our QEMU (its vresearch machine has no unauth-root): tvos\Install-tvOS.cmd -Only qemu replaces it"
}
# loadvm-date: a resumed state's clock is set by "date" on the root shell (the serial console), as iOS 26's,
# watchOS's and visionOS's are; a QEMU without the option resumes its old way (the clock moved on)
$loadDate = $machineHelp -cmatch '\bloadvm-date='
$ppiValue = if ($Ppi) { $Ppi } else { $mode.Ppi }
if ($ppiValue -and $machineHelp -cnotmatch '\bppi=') { throw "this QEMU has no ppi= on its vresearch machine: start without -Ppi" }
if ($MaxFps -and $machineHelp -cnotmatch '\bmax-fps=') { throw "this QEMU has no max-fps= on its vresearch machine: start without -MaxFps" }
# x-tlbi-filter, as Start-iOS26.ps1's and Start-watchOS.ps1's (qemu-sptm 4993dd8): a broadcast TLB flush in one
# address space stops only the vCPUs in it. Not measured on tvOS. A QEMU without it starts without it.
$tvCpu = 'max,pauth-impdef=on'
if (-not $NoTlbiFilter) {
    $tlbiOut = Qemu-Probe $probeExe @('-M', 'none', '-cpu', 'max,x-tlbi-filter=on,x-asoft-probe=on', '-display', 'none', '-S', '-nodefaults')
    if ($tlbiOut -cmatch 'x-asoft-probe' -and $tlbiOut -cnotmatch "x-tlbi-filter' not found") {
        $tvCpu += ',x-tlbi-filter=on'
        Write-Host 'TLBI filter on (x-tlbi-filter, experimental; -NoTlbiFilter turns it off)'
    } else { Write-Host 'TLBI filter: this QEMU has no x-tlbi-filter' }
}
# The TV window (above): the usb-consumer's property list, which names $SkinProp in a QEMU that has it
$consumer = 'usb-consumer,bus=xhci.0,port=3,id=ucons'
if ((Qemu-Probe $probeExe @('-device', 'usb-consumer,help')) -cmatch "(?m)^\s*$([regex]::Escape($SkinProp))=") {
    $consumer += ",$SkinProp=on"
    Write-Host "TV window: the picture as a TV with a Siri Remote (F9$(if ($NoFrame) { ', or -NoFrame as now' }): the picture alone)"
} else { Write-Host "TV window: this QEMU has no usb-consumer $SkinProp (the asoft-tv build has it): the plain window" }
# one tvOS at a time: the ports are fixed
$busy = @(Get-NetTCPConnection -State Listen -LocalPort $TvPorts -ErrorAction SilentlyContinue)
if ($busy) {
    $said = "ports {0}-{1} are in use (pid {2}): is tvOS running already?" -f $TvPorts[0], $TvPorts[2], (($busy | ForEach-Object OwningProcess | Sort-Object -Unique) -join ', ')
    if ($PrintOnly) { Write-Host $said -ForegroundColor Yellow } else { throw $said }
}

# Saved states: in the disk tvOS writes (not with -Snapshot), through the QEMU package's qemu-img.
$diskPath = In-Work $Disk
$qemuImg = Join-Path (Split-Path $Exe) 'qemu-img.exe'
if (-not (Test-Path $qemuImg)) { $qemuImg = '' }
# The disk and every layer under it must open: said here, in qemu-img's words, before QEMU ends on it at once (and
# before a saved state is blamed for that and dropped)
if ($qemuImg) {
    $ErrorActionPreference = 'Continue'     # (Windows PowerShell 5.1 turns a native tool's stderr into errors)
    $chain = @(& $qemuImg info -U --backing-chain $diskPath 2>&1 | ForEach-Object { "$_" })
    $chainExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($chainExit) { throw ("$diskPath cannot be opened with the layers under it: " + (($chain | Where-Object { $_ } | Select-Object -Last 2) -join ' ')) }
}
$quickSnapshot = 'asoft-quick'
# GB a saved state takes on the disk's drive: about the guest's RAM (not measured on tvOS), the first save needs it free
$stateGB = $ramGiB + 0.5
function Disk-States {
    if (-not $qemuImg -or -not (Test-Path $diskPath)) { return @() }
    # (-U: QEMU may have the disk open)
    $ErrorActionPreference = 'Continue'     # (Windows PowerShell 5.1 turns a native tool's stderr into errors)
    try { @(((& $qemuImg info --output=json -U $diskPath 2>$null) -join "`n" | ConvertFrom-Json).snapshots) | Where-Object { $_ } } catch { @() }
}
# The quick save is resumed by itself once. From that start on (and from any start that does not resume it) it
# stays as the way back: <disk>.quick-used names it by its id and time (qemu-img's JSON: no time zone in them;
# the other launchers write the same), and only -LoadState asoft-quick goes back to it. The next save (closing the
# window) replaces it with a new time, which is resumed again.
function Quick-Key {
    $s = Disk-States | Where-Object { $_.name -ceq $quickSnapshot } | Select-Object -First 1
    if ($s) { "$($s.id) $($s.'date-sec') $($s.'date-nsec')" } else { '' }
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
if ($LoadState -and $Snapshot) { throw '-LoadState resumes a state of the disk tvOS writes: not with -Snapshot' }
if ($LoadState -and -not (Disk-States | Where-Object { $_.name -ceq $LoadState })) { throw "no saved state $LoadState on $diskPath" }
# (the install's own disks only: a disk named with -Disk is one of Install-tvOS.ps1's boots, which must boot)
$quickBoot = $userDisk -and -not $Snapshot -and -not $NoQuickBoot -and [bool]$qemuImg
$savedState = if ($userDisk -and -not $Snapshot) { Get-QuickState }
# (a new save of the same name takes the old one's room: only the first needs it free)
if ($quickBoot -and -not (Quick-Key)) {
    $free = ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($diskPath))).AvailableFreeSpace / 1e9
    if ($free -lt $stateGB + 1) {
        Write-Host ("{0:N1} GB free on {1}: a saved state needs about {2:N1} GB, so quick boot is off this time" -f $free, [IO.Path]::GetPathRoot($diskPath), $stateGB) -ForegroundColor Yellow
        $quickBoot = $false
    }
}
if ($savedState -and -not $quickBoot -and -not $LoadState) {
    Write-Host 'Quick boot is off: tvOS boots, and the saved state stays as a way back (-LoadState asoft-quick)'
}
$resume = if ($LoadState) { $LoadState } elseif ($savedState -and $quickBoot) { $quickSnapshot } else { '' }

if (-not $Name) { $Name = Get-Date -Format 'yyyyMMdd-HHmmss' }
$O = In-Work "tvos\runs\$Name"
# the environment QEMU starts with (its own process takes ours)
$qemuEnv = [ordered]@{
    TMPDIR = (In-Work 'tvos\tmp'); TEMP = (In-Work 'tvos\tmp'); TMP = (In-Work 'tvos\tmp')
    ASOFT_PAGE_BITS = '14'
    REIMS_VGPU_LOG = $GpuLog
    # (a surface the GPU library cannot make is skipped, not the guest's process stopped)
    REIMS_VGPU_REFUSALS = 'skip'
    ASOFT_SUBTITLE = "tvOS 27.2 $([char]0x00B7) Apple TV 4K"
}
# the TV window draws the TV and the remote around the picture; -NoFrame starts with the picture alone (F9 switches)
$qemuEnv['ASOFT_FRAME'] = if ($NoFrame) { '0' } else { $null }
# The PC's GPU (Start-iOS26.ps1's rule: the library takes a discrete one first; -HostGpu, or auto on a PC whose GPUs
# are all AMD, two or more, limits it to a kind with REIMS_VGPU_DEVICE; set by hand in the environment, it stays)
$gpus = @(try {
    Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { "$($_.PNPDeviceID)" -clike 'PCI\*' } | ForEach-Object {
        $id = "$($_.PNPDeviceID)"
        [pscustomobject]@{ Name = "$($_.Name)"; Driver = "$($_.DriverVersion)"
            Vendor = $(if ($id -cmatch 'VEN_1002') { 'AMD' } elseif ($id -cmatch 'VEN_10DE') { 'NVIDIA' } elseif ($id -cmatch 'VEN_8086') { 'Intel' } else { 'other' }) }
    }
} catch { })
foreach ($g in $gpus) { Write-Host ("PC GPU: {0} ({1}, driver {2})" -f $g.Name, $g.Vendor, $g.Driver) -ForegroundColor DarkGray }
$gpuKind = $HostGpu
$amd = @($gpus | Where-Object { $_.Vendor -ceq 'AMD' })
if ($gpuKind -ceq 'auto' -and $amd.Count -ge 2 -and $amd.Count -eq $gpus.Count) {
    $gpuKind = 'integrated'
    Write-Host 'Only AMD GPUs: tvOS draws on the integrated one, as iOS 26 does (-HostGpu discrete tries the other)' -ForegroundColor Yellow
}
if ($gpuKind -cne 'auto') { $qemuEnv['REIMS_VGPU_DEVICE'] = $gpuKind }
elseif ($env:REIMS_VGPU_DEVICE) { $qemuEnv['REIMS_VGPU_DEVICE'] = $env:REIMS_VGPU_DEVICE }
if ($qemuEnv['REIMS_VGPU_DEVICE']) { Write-Host "GPU settings: REIMS_VGPU_DEVICE=$($qemuEnv['REIMS_VGPU_DEVICE'])" -ForegroundColor DarkGray }

# boott.ps1's boot arguments (the hand-built tvOS's), with the vCPU count
$boot = "serial=3 -v debug=0x14e cpus=$Cpus rd=disk0s1 wdt=-1 keepsyms=1 -noprogress " +
        'launchd_unsecure_cache=1 launchd_disable_all_timeouts=1 aks-endpoint=0 cpu_boot_timeout_secs=30'
$machine = "vresearch,fb=$($mode.Fb),unauth-root=on,pvg=reims,aks-stub=on,amfi-lc-off=on,aks-crypt=on,acm-stub=on,hfs-dp-stub=on" +
           $(if ($loadDate) { ',loadvm-date=on' }) + $(if ($MaxFps) { ",max-fps=$MaxFps" }) + $(if ($ppiValue) { ",ppi=$ppiValue" })
function Q([string]$a) { '"' + $a + '"' }
$qargs = @(
    '-name', (Q 'ASoftware tvOS 27.2'),
    '-M', $machine,
    '-bootkc', (Q (In-Work 'tvos\bootkc-t')), '-sptm', (Q (In-Work 'fw\sptm')), '-txm', (Q (In-Work 'fw\txm')),
    '-dtree', (Q (In-Work $tree)), '-tc', (Q (In-Work $Tc)), '-ramdisk', (Q (In-Work 'rd-shell.hfs')),
    '-args', (Q $boot),
    '-display', ('gtk,show-cursor=on,zoom-to-fit=on,gl=on,sidebar=on,show-menubar=off' + $(if ($quickBoot) { ',quick-boot=on' } else { '' })),
    '-monitor', "tcp:127.0.0.1:$($TvPorts[1]),server=on,wait=off",
    '-parallel', 'none',
    '-chardev', (Q "socket,id=con,host=127.0.0.1,port=$($TvPorts[0]),server=on,wait=off,logfile=$O\serial.log"),
    '-serial', 'chardev:con', '-d', 'guest_errors,unimp', '-D', (Q "$O\qemu.log"),
    '-cpu', $tvCpu, '-smp', "$Cpus", '-accel', "tcg,thread=multi,tb-size=$TbMiB",
    '-drive', (Q ("file=$diskPath,if=none,id=root,cache=writeback,discard=unmap")), '-device', 'virtio-blk-pci,drive=root',
    '-qmp', "tcp:127.0.0.1:$($TvPorts[2]),server=on,wait=off",
    '-device', 'qemu-xhci,id=xhci,conditional-intr-mapping=on,nonremovable=2',
    # the remote: arrows, Return and Esc on the keyboard; the consumer device's buttons are F1-F4 (TV, power,
    # volume) and, as a TV remote's ($SkinProp=on), F5-F7 (Play/Pause, Mute, Siri)
    '-device', 'usb-kbd,bus=xhci.0,port=1,id=ukbd,idle-reports=off',
    '-device', 'usb-touchscreen,bus=xhci.0,port=2,id=utouch',
    '-device', $consumer
)
if (-not $NoNet) { $qargs += @('-nic', 'user,model=virtio-net-pci') }
if ($Snapshot) { $qargs += '-snapshot' }
$qargs += $Extra

if ($PrintOnly) {
    # what a start would run: nothing is started or written (no run folder, no .quick-used)
    Write-Host "mode $Resolution ($($mode.Fb)), $Cpus vCPUs, tree $tree, disk $Disk, trust cache $Tc" -ForegroundColor DarkGray
    foreach ($k in $qemuEnv.Keys) { if ($null -ne $qemuEnv[$k]) { "set $k=$($qemuEnv[$k])" } }
    "$(Q $Exe) $($qargs -join ' ')"
    if ($resume) { "  (then -loadvm ${resume}: $(if ($LoadState) { 'the state named with -LoadState' } else { 'the quick save, resumed once' }))" }
    elseif ($quickBoot -and -not $NoAutoSave -and -not (Quick-Key)) { '  (and Tv-AutoSave.ps1, hidden: the first quick save once Home has been up a while)' }
    "(print only: QEMU not started; its run folder would be $O)"
    return
}

if (-not $Keep -and (Test-Path $O)) { Remove-Item $O -Recurse -Force }
New-Item -ItemType Directory -Force $O, (In-Work 'tvos\tmp') | Out-Null
foreach ($k in $qemuEnv.Keys) {
    if ($null -ne $qemuEnv[$k]) { Set-Item -Path "Env:$k" -Value $qemuEnv[$k] } else { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
}
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
function Start-Tv([string[]]$more) {
    # (no extra arguments arrive as a null element, which Start-Process refuses)
    $all = @($qargs) + @($more | Where-Object { $_ })
    Set-Content "$O\cmdline.txt" ($all -join ' ')
    $p = Start-Process -FilePath $Exe -ArgumentList $all -PassThru -WorkingDirectory $Work `
        -RedirectStandardError "$O\stderr.log" -RedirectStandardOutput "$O\stdout.log"
    $null = $p.Handle       # (ExitCode, once it has ended, needs the handle taken)
    $p
}
# QEMU's own reason in a log (another CPU count or set of devices than the save's), not its info lines
function Qemu-Why([string]$log) {
    @(Get-Content $log -ErrorAction SilentlyContinue |
      Where-Object { $_ -match 'qemu-system-aarch64w?\.exe: ' -and $_ -notmatch '\.exe: info: ' } |
      ForEach-Object { $_ -replace '^.*?qemu-system-aarch64w?\.exe: ', '' }) | Select-Object -First 2
}
# From here on the disk goes on from this start: a quick save, resumed now or not, is the way back
if ($userDisk -and -not $Snapshot) { Keep-WayBack }
$resumed = $false
if ($resume) {
    Write-Host $(if ($LoadState) { "Resuming the saved state $LoadState" } else { 'Resuming the state saved when the window was closed' })
    $q = Start-Tv @('-loadvm', $resume)
    # until the machine runs, or QEMU ends first: then the state did not load (another QEMU build, other
    # options), at most 5 min
    $until = (Get-Date).AddMinutes(5)
    $ran = $false
    while (-not $q.HasExited -and (Get-Date) -lt $until -and -not ($ran = Qmp-Running $TvPorts[2])) { Start-Sleep -Seconds 2 }
    if (-not $ran -and $q.HasExited) {
        Move-Item "$O\stderr.log" "$O\stderr-resume.log" -Force -ErrorAction SilentlyContinue
        $why = Qemu-Why "$O\stderr-resume.log"
        $said = "The saved state $resume could not be resumed (exit $($q.ExitCode)" + $(if ($why) { ': ' + ($why -join '; ') } else { '' }) + "; $O\stderr-resume.log)"
        # a state named with -LoadState is kept; the quick boot's goes, and tvOS boots
        if ($LoadState) { throw "$said; it is kept" }
        Write-Host "$said; booting tvOS" -ForegroundColor Yellow
        Remove-QuickState
        $q = Start-Tv @()
    } else {
        $resumed = -not $q.HasExited
    }
} else {
    $q = Start-Tv @()
}
# a QEMU that refuses its arguments or a disk ends at once: say why (the .cmd window then stays open)
if ($q.WaitForExit(3000)) {
    $why = @(Get-Content "$O\stderr.log" -Tail 8 -ErrorAction SilentlyContinue) -join "`n"
    throw "QEMU ended at once (exit $($q.ExitCode)); $O\stderr.log:`n$why"
}
if ($resumed) {
    Write-Host 'tvOS goes on where it was saved; closing the window saves it again.'
} else {
    Write-Host "tvOS boots to Home in about 1.5 minutes on 4 vCPUs (the arrow keys, Return and Esc are the remote)."
    # The automatic save is for a disk with no save yet. A save already there stays as the way back, and only
    # closing the window replaces it. (A save that failed to load above is gone by now: that start gets one.)
    if ($quickBoot -and -not $NoAutoSave -and -not (Quick-Key)) {
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', (Q (Join-Path $PSScriptRoot 'Tv-AutoSave.ps1')),
               '-QemuPid', "$($q.Id)", '-Disk', (Q $diskPath), '-Log', (Q "$O\autosave.log"), '-QmpPort', "$($TvPorts[2])", '-StateGB', "$stateGB")
        $null = Start-Process powershell.exe -ArgumentList $a -WindowStyle Hidden
        Write-Host ('Quick boot: tvOS is saved once Home has been up a while and you are not using it, and ' +
                    "again when you close the window; the next start goes on from there in seconds ($O\autosave.log).")
    } elseif ($quickBoot) {
        Write-Host 'Quick boot: closing the window saves tvOS; the next start goes on from there in seconds.'
    }
}
"started $Exe pid $($q.Id) -> $O"

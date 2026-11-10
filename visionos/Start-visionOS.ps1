# ASoftware visionOS launcher: visionOS 27.2 (Apple Vision Pro, RealityDevice14,1) on -M vresearch, from the work
# folder Install-visionOS.ps1 built it in (the iOS 26 install's, with its visionos\ folder), on the install's one
# QEMU (<work>\qemu, which runs iOS 16, iOS 26 and watchOS too).
#   Start-visionOS.cmd [-Work D:\ios26] [-Cpus 4|6|8] [-Sound] [-NoNet] [-NoFrame] [-Snapshot] [-Name RUN]
#                      [-NoQuickBoot] [-NoAutoSave] [-LoadState NAME] [-HostGpu auto|integrated|discrete]
# The window is the headset's view at 1920x1080, in a drawn Apple Vision Pro (F9 or -NoFrame: the screen alone,
# as large as the window lets it be; F11 full screen). Mouse = hover and tap (the eyes and the pinch); right
# button held: look around, and walk with W A S D, R F (up/down) and Shift (turn); the middle button turns walk
# mode on and off. Digital Crown F1 (hold: recentre), top button F2, volume F3/F4; F12 shows the keys pressed.
# Its own ports (serial console 4481, HMP 4482, QMP 4483): one visionOS at a time; iOS 26 (4451-4453) and watchOS
# (4471-4473) can run beside it.
#   -Cpus 4|6|8   vCPUs (default 8), each with its own device tree (dtree-v, -v6, -v8); RAM is the tree's 4 GiB
#   -Sound        the sound disk (visionos\vision.qcow2) with a virtio-snd speaker on Windows' default output;
#                 without it the silent disk (visionos\vision-silent.qcow2): sound costs about one vCPU
#   -NoNet        no network
#   -NoFrame      the window starts without the drawn headset
#   -HostGpu      auto|integrated|discrete: the PC's GPU visionOS draws on (as Start-iOS26.ps1's)
#   -Snapshot    writes go to a temporary file, the disk stays as it was
#   -Disk/-Tc     another disk (relative to the work folder) and trust cache: Install-visionOS.ps1's boots
#                 (no quick boot on such a disk: it boots every time)
# Quick boot, as iOS 26's and watchOS's launchers (on unless -NoQuickBoot, not with -Snapshot): closing the window
# saves the machine (memory and devices, about 4 GB) into the disk as its snapshot asoft-quick, and the next start
# resumes it in about 15 seconds instead of booting (about 5 minutes to Home). A save is resumed once; then it
# stays as a way back (-LoadState asoft-quick goes back to it) until the next save replaces it, and a start boots
# visionOS from its disk as it was left. -LoadState NAME resumes another saved state (the side bar's Save state
# makes them). A state loads only with its own -Cpus, and the sound disk and the silent disk have each their own.
# After a cold start on a disk with no save yet, Vision-AutoSave.ps1 (hidden) saves the same state once Home has
# been up for some minutes, visionOS's start-up work is done and nobody is using it: a start after a crash, a
# forced stop or a power cut then goes on from there too (-NoAutoSave keeps only the save at closing).
# Writes go to the disk's own layer; the layers under it stay as the install made them. Each start keeps its logs
# in visionos\runs\<Name> (serial.log, qemu.log, stderr.log, cmdline.txt). Prints "started EXE pid N -> RUN FOLDER".
param(
    [string]$Work = '',
    [string]$Config = (Join-Path $env:LOCALAPPDATA 'ASoftware iOS 26\ios26.config.json'),
    [string]$Name = '',
    [ValidateSet(4, 6, 8)][int]$Cpus = 8,
    [switch]$Sound,
    [switch]$NoNet,
    [switch]$NoFrame,
    [switch]$Snapshot,
    [switch]$Keep,
    [switch]$NoQuickBoot,
    [switch]$NoAutoSave,
    # at most so many of visionOS's frames a second (0: all, 60 with nothing moving; 30 takes about a tenth off
    # the PC's load at rest)
    [ValidateRange(0, 120)][int]$MaxFps = 0,
    [string]$LoadState = '',
    [string]$Disk = '',
    [string]$Tc = 'visionos\rootv.tc',
    [string]$Exe = '',
    # the PC's GPU visionOS draws on, as Start-iOS26.ps1 has it: auto is the discrete one where there is one, but
    # the integrated one on a PC whose GPUs are all AMD
    [ValidateSet('auto', 'integrated', 'discrete')][string]$HostGpu = 'auto',
    [ValidateSet('error', 'warn', 'info', 'debug')][string]$GpuLog = 'warn',
    [string[]]$Extra = @()
)
$ErrorActionPreference = 'Stop'
if (-not $Work) {
    if (Test-Path $Config) { try { $Work = [string](Get-Content $Config -Raw | ConvertFrom-Json).Work } catch { } }
}
$installIt = 'run Install-ASoftware.cmd and answer yes to visionOS (it is built on iOS 26''s base), or visionos\Install-visionOS.cmd on an iOS 26 install'
if (-not $Work -or -not (Test-Path -LiteralPath ([IO.Path]::Combine($Work, 'visionos')))) {
    throw "no visionOS install found$(if ($Work) { " in $Work" }): $installIt (or give -Work)"
}
# absolute: QEMU starts in it, and the paths it is given must not be relative to it
$Work = (Resolve-Path -LiteralPath $Work).Path.TrimEnd('\')
function In-Work([string]$rel) { if ([IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $Work $rel } }
if (-not $Exe) {
    $Exe = In-Work 'qemu\qemu-system-aarch64w.exe'
    if (-not (Test-Path $Exe)) { $Exe = In-Work 'qemu\qemu-system-aarch64.exe' }
}
$userDisk = -not $Disk
if (-not $Disk) { $Disk = if ($Sound) { 'visionos\vision.qcow2' } else { 'visionos\vision-silent.qcow2' } }
$dtree = switch ($Cpus) { 8 { 'visionos\dtree-v8' } 6 { 'visionos\dtree-v6' } default { 'visionos\dtree-v' } }
$goOn = 'run visionos\Install-visionOS.cmd (or Install-ASoftware.cmd) again: it goes on where it stopped'
if ($Sound -and $userDisk -and -not (Test-Path (In-Work 'visionos\vision.qcow2')) -and (Test-Path (In-Work 'visionos\vision-silent.qcow2.ready'))) {
    throw ('this install has no sound disk: it was made without the audio plug-in (VPhoneVirtIOSound). Start without -Sound, ' +
           'or give the plug-in to the installer (visionos\Install-visionOS.cmd -AudioPlugin <folder>) and run it again')
}
$need = @($Exe, (In-Work 'visionos\bootkc-v'), (In-Work $dtree), (In-Work 'fw\sptm'), (In-Work 'fw\txm'),
          (In-Work 'rd-shell.hfs'), (In-Work $Disk), (In-Work $Tc))
foreach ($n in $need) { if (-not (Test-Path $n)) { throw "$n is missing: $goOn" } }
# the install's own disks once its disks step has made them (a redo of a disk step retires them)
if ($userDisk -and -not (Test-Path ((In-Work $Disk) + '.ready'))) {
    throw "the visionOS install is not finished ($Disk has not been through its disks step): $goOn"
}
# what visionOS needs of the QEMU (Install-visionOS.ps1's qemu step put such a one in <work>\qemu). The probes have
# a time limit, as Install-visionOS.ps1's: a console exe that hangs (a missing-DLL dialog, an antivirus hold) must
# not hold the start for ever. Its output, or '' when it did not end in time (then it is stopped by its own PID, and
# what the probe looks for counts as not there)
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
if ((Qemu-Probe $probeExe @('-device', 'usb-touchscreen,help')) -cnotmatch '\bwalk-hold-key=') {
    throw "$(Split-Path $Exe) is not a QEMU visionOS runs on (its usb-touchscreen has no walk mode): visionos\Install-visionOS.cmd -Only qemu replaces it"
}
# loadvm-date: a resumed state's clock is set by "date" on the root shell (the serial console). The QEMU's other
# way, moving the machine's clock on by the time it was away, makes every timeout that was running at the save
# run out: visionOS's compositor aborted a few seconds into a state resumed ten minutes or more after its save,
# with every open app gone and two minutes of starting again. A QEMU without the option resumes its old way.
$loadDate = (Qemu-Probe $probeExe @('-M', 'vresearch,help')) -cmatch '\bloadvm-date='
# one visionOS at a time: the ports are fixed
$busy = @(Get-NetTCPConnection -State Listen -LocalPort 4481, 4482, 4483 -ErrorAction SilentlyContinue)
if ($busy) { throw ("ports 4481-4483 are in use (pid {0}): is visionOS running already?" -f (($busy | ForEach-Object OwningProcess | Sort-Object -Unique) -join ', ')) }

# Saved states: in the disk visionOS writes (not with -Snapshot), through the QEMU package's qemu-img.
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
# GB a saved state takes on the disk's drive (measured: 4.0 GB at the 4 GiB of RAM): the first save needs it free
$stateGB = 4.5
function Disk-States {
    if (-not $qemuImg -or -not (Test-Path $diskPath)) { return @() }
    # (-U: QEMU may have the disk open)
    $ErrorActionPreference = 'Continue'     # (Windows PowerShell 5.1 turns a native tool's stderr into errors)
    try { @(((& $qemuImg info --output=json -U $diskPath 2>$null) -join "`n" | ConvertFrom-Json).snapshots) | Where-Object { $_ } } catch { @() }
}
# The quick save is resumed by itself once. From that start on (and from any start that does not resume it) it
# stays as the way back: <disk>.quick-used names it by its id and time (qemu-img's JSON: no time zone in them;
# Start-iOS26.ps1 and Start-watchOS.ps1 write the same), and only -LoadState asoft-quick goes back to it. The next
# save (closing the window) replaces it with a new time, which is resumed again.
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
if ($LoadState -and $Snapshot) { throw '-LoadState resumes a state of the disk visionOS writes: not with -Snapshot' }
if ($LoadState -and -not (Disk-States | Where-Object { $_.name -ceq $LoadState })) { throw "no saved state $LoadState on $diskPath" }
# (the install's own disks only: a disk named with -Disk is one of Install-visionOS.ps1's boots, which must boot)
$quickBoot = $userDisk -and -not $Snapshot -and -not $NoQuickBoot -and [bool]$qemuImg
$savedState = if ($userDisk -and -not $Snapshot) { Get-QuickState }
# (a new save of the same name takes the old one's room: only the first needs it free)
if ($quickBoot -and -not (Quick-Key)) {
    $free = ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($diskPath))).AvailableFreeSpace / 1e9
    if ($free -lt $stateGB + 1) {
        Write-Host ("{0:N1} GB free on {1}: a saved state needs about {2} GB, so quick boot is off this time" -f $free, [IO.Path]::GetPathRoot($diskPath), $stateGB) -ForegroundColor Yellow
        $quickBoot = $false
    }
}
if ($savedState -and -not $quickBoot -and -not $LoadState) {
    Write-Host 'Quick boot is off: visionOS boots, and the saved state stays as a way back (-LoadState asoft-quick)'
}
$resume = if ($LoadState) { $LoadState } elseif ($savedState -and $quickBoot) { $quickSnapshot } else { '' }

if (-not $Name) { $Name = Get-Date -Format 'yyyyMMdd-HHmmss' }
$O = In-Work "visionos\runs\$Name"
if (-not $Keep -and (Test-Path $O)) { Remove-Item $O -Recurse -Force }
New-Item -ItemType Directory -Force $O, (In-Work 'visionos\tmp') | Out-Null
$env:TMPDIR = In-Work 'visionos\tmp'; $env:TEMP = $env:TMPDIR; $env:TMP = $env:TMPDIR
$env:ASOFT_PAGE_BITS = '14'
$env:REIMS_VGPU_LOG = $GpuLog
# (a surface the GPU library cannot make is skipped, not the guest's process stopped)
$env:REIMS_VGPU_REFUSALS = 'skip'
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
    Write-Host 'Only AMD GPUs: visionOS draws on the integrated one, as iOS 26 does (-HostGpu discrete tries the other)' -ForegroundColor Yellow
}
if ($gpuKind -cne 'auto') { $env:REIMS_VGPU_DEVICE = $gpuKind }
if ($env:REIMS_VGPU_DEVICE) { Write-Host "GPU settings: REIMS_VGPU_DEVICE=$env:REIMS_VGPU_DEVICE" -ForegroundColor DarkGray }
$env:ASOFT_SUBTITLE = "visionOS 27.2 $([char]0x00B7) Apple Vision Pro"
# the window draws the headset around the screen; -NoFrame starts with the screen alone (F9 in the window switches)
if ($NoFrame) { $env:ASOFT_FRAME = '0' } else { Remove-Item Env:ASOFT_FRAME -ErrorAction SilentlyContinue }
$boot = "serial=3 -v debug=0x14e cpus=$Cpus rd=disk0s1 wdt=-1 wq_timeout_sec=3600 keepsyms=1 -noprogress " +
        'launchd_unsecure_cache=1 launchd_disable_all_timeouts=1 aks-endpoint=0 cpu_boot_timeout_secs=30 ool_port_array_enforced=0'
function Q([string]$a) { '"' + $a + '"' }
$qargs = @(
    '-name', (Q 'ASoftware visionOS 27.2'),
    '-M', ('vresearch,fb=1920x1080,unauth-root=on,pvg=reims,aks-stub=on,amfi-lc-off=on,aks-crypt=on,acm-stub=on,hfs-dp-stub=on' + $(if ($loadDate) { ',loadvm-date=on' }) + $(if ($MaxFps) { ",max-fps=$MaxFps" })),
    '-bootkc', (Q (In-Work 'visionos\bootkc-v')), '-sptm', (Q (In-Work 'fw\sptm')), '-txm', (Q (In-Work 'fw\txm')),
    '-dtree', (Q (In-Work $dtree)), '-tc', (Q (In-Work $Tc)), '-ramdisk', (Q (In-Work 'rd-shell.hfs')),
    '-args', (Q $boot),
    '-display', ('gtk,show-cursor=on,zoom-to-fit=on,gl=on,sidebar=on,show-menubar=off' + $(if ($quickBoot) { ',quick-boot=on' } else { '' })),
    '-monitor', 'tcp:127.0.0.1:4482,server=on,wait=off',
    '-parallel', 'none',
    '-chardev', (Q "socket,id=con,host=127.0.0.1,port=4481,server=on,wait=off,logfile=$O\serial.log"),
    '-serial', 'chardev:con', '-d', 'guest_errors,unimp', '-D', (Q "$O\qemu.log"),
    # x-tlbi-filter: the guest's TLB flushes of other address spaces are not done on every vCPU (TCG speed)
    '-cpu', 'max,pauth-impdef=on,x-tlbi-filter=on', '-smp', "$Cpus", '-accel', 'tcg,thread=multi,tb-size=2048',
    '-drive', (Q ("file=" + (In-Work $Disk) + ",if=none,id=root,cache=writeback,discard=unmap")), '-device', 'virtio-blk-pci,drive=root',
    '-qmp', 'tcp:127.0.0.1:4483,server=on,wait=off',
    '-device', 'qemu-xhci,id=xhci,conditional-intr-mapping=on,nonremovable=2',
    '-device', 'usb-kbd,bus=xhci.0,port=1,id=ukbd,idle-reports=off',
    # hover = the eyes; taps paced to the guest's frames and held long enough for a TCG guest to see them; walk
    # mode holds F13 (183), which the guest's keyboard camera needs before W/A/S/D move the head
    '-device', 'usb-touchscreen,bus=xhci.0,port=2,id=utouch,hover=on,touch-pace-ms=66,touch-min-press-ms=250,touch-min-hover-ms=300,walk-mode=on,walk-hold-key=183',
    '-device', 'usb-consumer,bus=xhci.0,port=3,id=ucons'
)
if ($Sound) { $qargs += @('-audiodev', 'dsound,id=snd0', '-device', 'virtio-sound-pci,audiodev=snd0') }
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
function Start-Vision([string[]]$more) {
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
    $q = Start-Vision @('-loadvm', $resume)
    # until the machine runs, or QEMU ends first: then the state did not load (another QEMU build, other
    # options), at most 5 min
    $until = (Get-Date).AddMinutes(5)
    $ran = $false
    while (-not $q.HasExited -and (Get-Date) -lt $until -and -not ($ran = Qmp-Running 4483)) { Start-Sleep -Seconds 2 }
    if (-not $ran -and $q.HasExited) {
        Move-Item "$O\stderr.log" "$O\stderr-resume.log" -Force -ErrorAction SilentlyContinue
        $why = Qemu-Why "$O\stderr-resume.log"
        $said = "The saved state $resume could not be resumed (exit $($q.ExitCode)" + $(if ($why) { ': ' + ($why -join '; ') } else { '' }) + "; $O\stderr-resume.log)"
        # a state named with -LoadState is kept; the quick boot's goes, and visionOS boots
        if ($LoadState) { throw "$said; it is kept" }
        Write-Host "$said; booting visionOS" -ForegroundColor Yellow
        Remove-QuickState
        $q = Start-Vision @()
    } else {
        $resumed = -not $q.HasExited
    }
} else {
    $q = Start-Vision @()
}
# a QEMU that refuses its arguments or a disk ends at once: say why (the .cmd window then stays open)
if ($q.WaitForExit(3000)) {
    $why = @(Get-Content "$O\stderr.log" -Tail 8 -ErrorAction SilentlyContinue) -join "`n"
    throw "QEMU ended at once (exit $($q.ExitCode)); $O\stderr.log:`n$why"
}
if ($resumed) {
    Write-Host 'visionOS goes on where it was saved; closing the window saves it again.'
} else {
    Write-Host ("visionOS boots to Home in about 5 minutes on 8 vCPUs ({0}; F1 presses before Home are queued)." -f $(if ($Sound) { 'with sound' } else { 'silent' }))
    # The automatic save is for a disk with no save yet. A save already there stays as the way back, and only
    # closing the window replaces it. (A save that failed to load above is gone by now: that start gets one.)
    if ($quickBoot -and -not $NoAutoSave -and -not (Quick-Key)) {
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', (Q (Join-Path $PSScriptRoot 'Vision-AutoSave.ps1')),
               '-QemuPid', "$($q.Id)", '-Disk', (Q $diskPath), '-Log', (Q "$O\autosave.log"), '-StateGB', "$stateGB")
        $null = Start-Process powershell.exe -ArgumentList $a -WindowStyle Hidden
        Write-Host ('Quick boot: visionOS is saved once Home has been up for some minutes and you are not using it, and ' +
                    "again when you close the window; the next start goes on from there in seconds ($O\autosave.log).")
    } elseif ($quickBoot) {
        Write-Host 'Quick boot: closing the window saves visionOS; the next start goes on from there in seconds.'
    }
}
"started $Exe pid $($q.Id) -> $O"

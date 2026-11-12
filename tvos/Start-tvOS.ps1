# ASoftware tvOS launcher: tvOS 27.2 (Apple TV 4K, 3rd generation, AppleTV14,1) on -M vresearch, from the work
# folder Install-tvOS.ps1 built it in (the iOS 26 install's, with its tvos\ folder), on the install's one QEMU
# (<work>\qemu, which runs iOS 16, iOS 26, watchOS and visionOS too).
#   Start-tvOS.cmd [-Work D:\ios26] [-Resolution 1080|2160] [-Cpus 4|6|8] [-NoNet] [-NoFrame] [-Snapshot]
#                  [-Name RUN] [-NoQuickBoot] [-NoAutoSave] [-LoadState NAME] [-HostGpu auto|integrated|discrete]
#                  [-PrintOnly]
# The window is the TV's picture, 1920x1080 or 3840x2160 (-Resolution; scaled to the window, F11 full screen). On a
# QEMU with the TV window (usb-consumer tv-remote, branch asoft-tv) it is drawn as a TV with a Siri Remote beside it,
# whose parts can be clicked, and the side bar (F9 or -NoFrame: the picture alone); on an older one it is GTK's plain
# window with its menu bar. The keyboard is the remote: the arrow keys move the focus, Return selects, Esc goes back
# (Menu); F1 the TV button, F2 power, F3/F4 volume, and with the TV window F5 Play/Pause, F6 Mute, F7 Siri. tvOS
# reaches Home in about a minute on 4 vCPUs at 1080p (59-66 s), 65-96 s at 4K (measured on the hand-built disk).
# Its own ports (serial console 4501, HMP 4502, QMP 4503): one tvOS at a time; iOS 26 (4451-4453), watchOS
# (4471-4473) and visionOS (4481-4483) can run beside it.
#   -Resolution      1080 (1920x1080, tvOS's 1080p mode, scale 1) or 2160 (3840x2160, 4K, scale 2): the same disk,
#                    each with its own device trees ($Modes below). Not given: the mode of the saved state the start
#                    resumes, else the one this disk was last started in, else 1080 ($DefaultResolution)
#   -Cpus 4|6|8      vCPUs (default 4, the measured count), each with its own device tree (dtree-t, -t6, -t8);
#                    6 and 8 are made like 4 but not measured on tvOS
#   -RamMiB N        the guest's RAM (default: the tree's 4096 MiB; QEMU takes it from the device tree:
#                    ..\ios26\scripts\dt-ram.ps1 writes <tree>-<N>m beside it). Not measured on tvOS.
#   -Ppi N           the machine's ppi= (a QEMU that has it); default: the mode's (none)
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
# -LoadState NAME resumes another saved state (the TV window's side bar, Save state, makes them). A state loads only
# into the machine it was saved from: its resolution, -Cpus, RAM, network and -HostGpu (as ASoftware.exe keeps a
# save's settings). What a start does not give on its command line it takes from the state it resumes; a start that
# gives other values boots instead, and the quick save stays as the way back (a changed setting never removes a
# save; -LoadState with other values stops and says which). Each start of the disk notes its settings and time in
# <disk>.starts: a state's settings are those of the last start before it was saved (a state older than every
# noted start was saved at 2160, the only mode then). After a cold start on a disk with no save yet, Tv-AutoSave.ps1
# (hidden) saves the same state once Home has been up a while and nobody is using tvOS (-NoAutoSave keeps only the
# save at closing).
# Writes go to the disk's own layer; the layers under it stay as the install made them. Each start keeps its logs
# in tvos\runs\<Name> (serial.log, qemu.log, stderr.log, cmdline.txt). Prints "started EXE pid N -> RUN FOLDER".
param(
    [string]$Work = '',
    [string]$Config = (Join-Path $env:LOCALAPPDATA 'ASoftware iOS 26\ios26.config.json'),
    [string]$Name = '',
    [ValidateSet(4, 6, 8)][int]$Cpus = 4,
    # '' (not given): see -Resolution above
    [ValidateSet('1080', '2160')][string]$Resolution = '',
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
# asoft-tv has it: the start probes the QEMU for it (as for x-tlbi-filter) and gives the plain device and GTK's
# plain window without it (the side bar of an older QEMU is a phone's: Home, Lock, App switcher, Install .ipa).
$SkinProp = 'tv-remote'

# --- The output modes (-Resolution) -----------------------------------------------------------------
# Each mode's frame buffer, its device trees (one per vCPU count; Install-tvOS.ps1's firmware step makes both sets),
# the machine's ppi (0: none) and the size of a QMP screen dump that is Home, for Tv-AutoSave.ps1 (measured on the
# hand-built disk's boots: at 1080p the boot screens dump to 6-17 KB, Home to 115-121 KB; at 4K 24-49 KB and
# 288-299 KB). Both run on the one disk: its QuartzCore takes a mode's scale as a real Apple TV does (1 up to 1080
# lines, 2 above; Install-tvOS.ps1's patches step), and the tree's display scale and artwork keys say which.
# 1080 is the default: measured on the same PC, Home comes 59-66 s after the start (4K: 65-79 s), a slow remote
# key shows about 1.45x sooner, and QEMU takes 3.6-3.9 GB of private memory (4K: 4.9-5.5 GB); tvOS's own layout is
# 1920x1080 points either way.
$Modes = @{
    '1080' = @{ Fb = '1920x1080'; Ppi = 0; HomeBytes = 60000; Label = '1080p'
                Trees = @{ 4 = 'tvos\dtree-t-1080'; 6 = 'tvos\dtree-t6-1080'; 8 = 'tvos\dtree-t8-1080' } }
    '2160' = @{ Fb = '3840x2160'; Ppi = 0; HomeBytes = 150000; Label = '4K'
                Trees = @{ 4 = 'tvos\dtree-t'; 6 = 'tvos\dtree-t6'; 8 = 'tvos\dtree-t8' } }
}
$DefaultResolution = '1080'
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
if (-not $Disk) { $Disk = 'tvos\tv.qcow2' }
if (-not $Tc) { $Tc = 'tvos\roott.tc' }
$diskPath = In-Work $Disk
$goOn = 'run tvos\Install-tvOS.cmd (or Install-ASoftware.cmd) again: it goes on where it stopped'
function Need-Files([string[]]$files) {
    foreach ($n in @($files | Where-Object { -not (Test-Path -LiteralPath $_) })) {
        if ($userDisk -and $n -ceq "$diskPath.ready") {
            throw "the tvOS install is not finished ($Disk has not been through its disks step): $goOn"
        }
        throw "$n is missing: $goOn"
    }
}
# what every mode needs (the device tree comes once the mode is known, below)
Need-Files (@($Exe, (In-Work 'tvos\bootkc-t'), (In-Work 'fw\sptm'), (In-Work 'fw\txm'), (In-Work 'rd-shell.hfs'),
              $diskPath, (In-Work $Tc)) + $(if ($userDisk) { @("$diskPath.ready") } else { @() }))

# Saved states: in the disk tvOS writes (not with -Snapshot), through the QEMU package's qemu-img.
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

# --- The settings a state depends on ---------------------------------------------------------------
# A state loads only into the machine it was saved from (QEMU refuses another vCPU count or set of devices; another
# frame buffer and device tree would leave tvOS drawing for the screen it was saved on): the mode, the vCPUs, the
# RAM, the network card and the PC's GPU, written as ASoftware.exe writes a save's settings (Guests.Shape, with
# res=). <disk>.starts has one line per start of the install's disk, "<unix time> <settings>", the time taken just
# before QEMU starts: a state saved in a run (closing the window, Tv-AutoSave.ps1, the side bar) is newer than its
# start's line and older than the next one's.
$startsFile = "$diskPath.starts"
function Settings-Text([string]$res, [int]$smp, [int]$ram, [bool]$net, [string]$gpu) {
    "res=$res;smp=$smp;ram=$ram;net=$(if ($net) { 1 } else { 0 });gpu=$gpu"
}
function Settings-Parts([string]$text) {
    $h = @{}
    foreach ($p in ($text -split ';')) { $kv = $p -split '=', 2; if ($kv.Count -eq 2 -and $kv[1]) { $h[$kv[0]] = $kv[1] } }
    $h
}
# the noted starts, oldest first
function Read-Starts {
    if (-not $userDisk -or -not (Test-Path -LiteralPath $startsFile)) { return @() }
    @(Get-Content -LiteralPath $startsFile | ForEach-Object {
        if ("$_" -cmatch '^(\d+) (\S+)$') { [pscustomobject]@{ T = [long]$Matches[1]; Settings = $Matches[2] } }
    } | Sort-Object T)
}
# a state's settings: the last start noted at or before its time; older than every noted start: 2160, the only mode
# before the starts were noted (its other settings unknown, so not compared)
function State-Settings($state) {
    $t = [long]$state.'date-sec'
    $s = @(Read-Starts | Where-Object { $_.T -le $t }) | Select-Object -Last 1
    if ($s) { $s.Settings } else { 'res=2160' }
}
# Notes this start; keeps the lines a state on the disk was saved under, and the newest
function Note-Start([string]$settings) {
    $all = @(Read-Starts) + @([pscustomobject]@{ T = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); Settings = $settings })
    $times = @(Disk-States | ForEach-Object { [long]$_.'date-sec' })
    $kept = for ($i = 0; $i -lt $all.Count; $i++) {
        $next = if ($i + 1 -lt $all.Count) { $all[$i + 1].T } else { [long]::MaxValue }
        if ($i -eq $all.Count - 1 -or @($times | Where-Object { $_ -ge $all[$i].T -and $_ -lt $next }).Count) { "$($all[$i].T) $($all[$i].Settings)" }
    }
    Set-Content -LiteralPath $startsFile -Value $kept -Encoding ASCII
}
# for people: "1080p, 4 vCPUs, 4096 MiB RAM, network on, GPU auto" (the parts known)
function Settings-Say([string]$text) {
    $p = Settings-Parts $text
    @($(if ($p.res) { $Modes[$p.res].Label }), $(if ($p.smp) { "$($p.smp) vCPUs" }), $(if ($p.ram) { "$($p.ram) MiB RAM" }),
      $(if ($p.net) { "network $(if ($p.net -ceq '1') { 'on' } else { 'off' })" }), $(if ($p.gpu) { "GPU $($p.gpu)" }) |
      Where-Object { $_ }) -join ', '
}

if ($LoadState -and $Snapshot) { throw '-LoadState resumes a state of the disk tvOS writes: not with -Snapshot' }
$loading = if ($LoadState) { Disk-States | Where-Object { $_.name -ceq $LoadState } | Select-Object -First 1 }
if ($LoadState -and -not $loading) { throw "no saved state $LoadState on $diskPath" }
# (the install's own disks only: a disk named with -Disk is one of Install-tvOS.ps1's boots, which must boot)
$quickBoot = $userDisk -and -not $Snapshot -and -not $NoQuickBoot -and [bool]$qemuImg
$savedState = if ($userDisk -and -not $Snapshot) { Get-QuickState }
# The state this start would resume: -LoadState's, else the quick save no start has resumed yet. What the command
# line does not set comes from it, so it opens as it was saved; what the command line sets must match it.
$resumeState = if ($loading) { $loading } elseif ($savedState -and $quickBoot) { Disk-States | Where-Object { $_.name -ceq $quickSnapshot } | Select-Object -First 1 }
$stateSettings = if ($resumeState) { State-Settings $resumeState } else { '' }
if ($resumeState) {
    $sp = Settings-Parts $stateSettings
    $given = $PSBoundParameters
    if (-not $given.ContainsKey('Resolution') -and $Modes.ContainsKey("$($sp.res)")) { $Resolution = $sp.res }
    if (-not $given.ContainsKey('Cpus') -and @('4', '6', '8') -ccontains $sp.smp) { $Cpus = [int]$sp.smp }
    if (-not $given.ContainsKey('RamMiB') -and $sp.ram -cmatch '^\d+$') { $RamMiB = if ([int]$sp.ram -eq 4096) { 0 } else { [int]$sp.ram } }
    if (-not $given.ContainsKey('NoNet') -and @('0', '1') -ccontains $sp.net) { $NoNet = [switch]($sp.net -ceq '0') }
    if (-not $given.ContainsKey('HostGpu') -and @('auto', 'integrated', 'discrete') -ccontains $sp.gpu) { $HostGpu = $sp.gpu }
}
# else the mode this disk was last started in, else the default
if (-not $Resolution) {
    $last = @(Read-Starts) | Select-Object -Last 1
    $lastRes = if ($last) { (Settings-Parts $last.Settings).res }
    $Resolution = if ($Modes.ContainsKey("$lastRes")) { $lastRes } else { $DefaultResolution }
}
$mode = $Modes[$Resolution]
$tree = $mode.Trees[$Cpus]
# (an install made before 1080p was wired in has neither the 1080p trees nor QuartzCore's patch on its disk)
if ($Resolution -ceq '1080' -and -not (Test-Path -LiteralPath (In-Work $Modes['1080'].Trees[4]))) {
    throw ('this tvOS install has no 1080p device trees, and its disk not the QuartzCore patch 1080p needs (it was ' +
           'built before 1080p was wired in): start with -Resolution 2160, or run tvos\Install-tvOS.cmd -Only firmware, ' +
           'then tvos\Install-tvOS.cmd -From patches (your disk is kept as tvos\tv.qcow2.old)')
}
Need-Files @((In-Work $tree))

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
$startSettings = Settings-Text $Resolution $Cpus ([int]($ramGiB * 1024)) (-not $NoNet) $HostGpu
# the state and this start: every part the state's settings name must be the same
$differs = @()
if ($resumeState) {
    $now = Settings-Parts $startSettings
    $sp = Settings-Parts $stateSettings
    $differs = @($sp.Keys | Where-Object { $sp[$_] -cne $now[$_] } | Sort-Object)
}
if ($differs) {
    $said = "the saved state $($resumeState.name) opens with $(Settings-Say $stateSettings); this start has $(Settings-Say $startSettings)"
    if ($LoadState) { throw "$said`: start without the options that differ (they are taken from the state), or with its own. It is kept." }
    Write-Host "Quick boot: $said, so tvOS boots, and the save stays as a way back (-LoadState asoft-quick opens it with its own settings)" -ForegroundColor Yellow
    $savedState = ''
}
Write-Host ("tvOS at {0} ({1}), {2} vCPUs{3}" -f $mode.Label, $mode.Fb, $Cpus,
            $(if ($resumeState -and -not $differs) { ", as $($resumeState.name) was saved" } elseif (-not $PSBoundParameters.ContainsKey('Resolution')) { " (-Resolution 1080|2160 chooses)" }))

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
# The TV window (above): the usb-consumer's property list names $SkinProp ("  tv-remote=<bool> ...") in a QEMU that
# has it; then the device gets it and the GTK window its side bar, which draws the TV and the remote
$consumer = 'usb-consumer,bus=xhci.0,port=3,id=ucons'
$display = 'gtk,show-cursor=on,zoom-to-fit=on,gl=on'
if ((Qemu-Probe $probeExe @('-device', 'usb-consumer,help')) -cmatch "(?m)^\s*$([regex]::Escape($SkinProp))=") {
    $consumer += ",$SkinProp=on"
    $display += ',sidebar=on,show-menubar=off'
    Write-Host "TV window: the picture as a TV with a Siri Remote (F9$(if ($NoFrame) { ', or -NoFrame as now' }): the picture alone)"
} else { Write-Host "TV window: this QEMU has no usb-consumer $SkinProp (the asoft-tv build has it): the plain window" }
# one tvOS at a time: the ports are fixed
$busy = @(Get-NetTCPConnection -State Listen -LocalPort $TvPorts -ErrorAction SilentlyContinue)
if ($busy) {
    $said = "ports {0}-{1} are in use (pid {2}): is tvOS running already?" -f $TvPorts[0], $TvPorts[2], (($busy | ForEach-Object OwningProcess | Sort-Object -Unique) -join ', ')
    if ($PrintOnly) { Write-Host $said -ForegroundColor Yellow } else { throw $said }
}

# GB a saved state takes on the disk's drive: about the guest's RAM (not measured on tvOS), the first save needs it free
$stateGB = $ramGiB + 0.5
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
    ASOFT_SUBTITLE = "tvOS 27.2 $([char]0x00B7) Apple TV 4K $([char]0x00B7) $($mode.Label)"
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
    '-display', ($display + $(if ($quickBoot) { ',quick-boot=on' } else { '' })),
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
    # what a start would run: nothing is started or written (no run folder, no .quick-used, no .starts line)
    Write-Host "mode $Resolution ($($mode.Fb)), $Cpus vCPUs, tree $tree, disk $Disk, trust cache $Tc" -ForegroundColor DarkGray
    if ($userDisk -and -not $Snapshot) { Write-Host "settings $startSettings (noted in $startsFile at a start)" -ForegroundColor DarkGray }
    foreach ($k in $qemuEnv.Keys) { if ($null -ne $qemuEnv[$k]) { "set $k=$($qemuEnv[$k])" } }
    "$(Q $Exe) $($qargs -join ' ')"
    if ($resume) { "  (then -loadvm ${resume}: $(if ($LoadState) { 'the state named with -LoadState' } else { 'the quick save, resumed once' }), saved with $stateSettings)" }
    elseif ($quickBoot -and -not $NoAutoSave -and -not (Quick-Key)) { "  (and Tv-AutoSave.ps1 -HomeBytes $($mode.HomeBytes), hidden: the first quick save once Home has been up a while)" }
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
# From here on the disk goes on from this start: a quick save, resumed now or not, is the way back; the states this
# run saves are saved with this start's settings
if ($userDisk -and -not $Snapshot) { Keep-WayBack; Note-Start $startSettings }
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
        # a state named with -LoadState is kept; the quick boot's (its settings were this start's) goes, and tvOS boots
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
    Write-Host "tvOS boots to Home in about $(if ($Resolution -ceq '1080') { 'a minute' } else { '1.5 minutes' }) on 4 vCPUs (the arrow keys, Return and Esc are the remote)."
    # The automatic save is for a disk with no save yet. A save already there stays as the way back, and only
    # closing the window replaces it. (A save that failed to load above is gone by now: that start gets one.)
    if ($quickBoot -and -not $NoAutoSave -and -not (Quick-Key)) {
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', (Q (Join-Path $PSScriptRoot 'Tv-AutoSave.ps1')),
               '-QemuPid', "$($q.Id)", '-Disk', (Q $diskPath), '-Log', (Q "$O\autosave.log"), '-QmpPort', "$($TvPorts[2])", '-StateGB', "$stateGB",
               '-HomeBytes', "$($mode.HomeBytes)")
        $null = Start-Process powershell.exe -ArgumentList $a -WindowStyle Hidden
        Write-Host ('Quick boot: tvOS is saved once Home has been up a while and you are not using it, and ' +
                    "again when you close the window; the next start goes on from there in seconds ($O\autosave.log).")
    } elseif ($quickBoot) {
        Write-Host 'Quick boot: closing the window saves tvOS; the next start goes on from there in seconds.'
    }
}
"started $Exe pid $($q.Id) -> $O"

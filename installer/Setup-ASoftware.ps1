# ASoftware iOS setup: one installer for iOS 16, iOS 26 or both, and watchOS 27.2 on iOS 26
# (Install-ASoftware.cmd runs it).
# It asks which, and for iOS 26 how the build runs its Linux tools: in WSL (fast; installing WSL
# needs an administrator and a restart) or in a small Linux VM in our QEMU (no WSL). Before
# anything starts it shows what each choice costs on this PC: the download (exact, from the two
# installers' own tables), the disk space at the peak and after, and the time (measured per step on
# our PC, scaled by this PC's cores and a 10 MB probe of Apple's CDN). Then it runs the two
# installers as they are, each still usable on its own:
#   installer\Install-ASoftware.ps1 (iOS 16), ios26\Install-iOS26.ps1 (iOS 26) and
#   watchos\Install-watchOS.ps1 (watchOS, on what iOS 26 installed)
# from the install folder, in one work folder (<Dir>\work) that holds our QEMU once for both.
# Both resume where they stopped, and so does this after a stop or a restart: its choices are in
# %LOCALAPPDATA%\ASoftware\setup.json. While it runs, the window title shows the step, the time
# so far and the time left; at the end it prints what it took and where everything is.
#
#   Install-ASoftware.cmd [-Version ios16|ios26|both] [-Watch yes|no] [-Linux wsl|helper] [-Dir D:\ASoftware]
#                         [-Lang en|tr] [-Yes] [-Estimate] [-List] [-Check] [-DryRun]
#     -Version, -Watch, -Linux   the answers to the questions (else it asks; -Watch needs iOS 26)
#     -Dir               the install folder: the app, and work\ for both iOS (default: <the fixed
#                        drive with the most room>:\ASoftware; no spaces, as iOS 26's build wants)
#     -Yes               ask nothing: the defaults, and the answer to the WSL question is -IfNoWsl
#     -IfNoWsl install|nowsl   when WSL is missing: install it now, or go on without it
#     -Estimate          print the estimates and stop
#     -List / -Check / -DryRun   the two installers' own modes, for the choice; nothing changes
#     -Mbps N / -NoProbe the bandwidth to estimate with, instead of probing Apple's CDN
#     -Pretend nowsl,novirt,helper   tests: as if WSL were missing, virtualization were off in
#                        the firmware, or Install-iOS26.ps1 had the install without WSL
#   iOS 16's options go to Install-ASoftware.ps1 (-Ipsw, -KeepIpsw, -QemuDist, -Cpus), iOS 26's to
#   Install-iOS26.ps1 (-CloudOsIpsw, -IPhoneIpsw, -GpuPlugin, -Collections, -KeepBuildFiles,
#   -BakeMinutes, -Ios26Config as its -Config), watchOS's to Install-watchOS.ps1 (-WatchIpsw,
#   -WatchDir DIR[|DIR], -WatchQemu FOLDER as its -QemuFrom: our QEMU build with the watch's devices,
#   which -QemuDist is only when it has them); -NoShortcut to all.
param(
    [string]$Version = '',
    [string]$Watch = '',
    [string]$Linux = '',
    [string]$Dir = '',
    [string]$Lang = '',
    [switch]$Yes,
    [string]$IfNoWsl = '',
    [switch]$Estimate,
    [switch]$List,
    [switch]$Check,
    [switch]$DryRun,
    [double]$Mbps = 0,
    [switch]$NoProbe,
    [string]$Pretend = '',
    [string]$Ipsw = '',
    [switch]$KeepIpsw,
    [string]$QemuDist = '',
    [int]$Cpus = 0,
    [string]$CloudOsIpsw = '',
    [string]$IPhoneIpsw = '',
    [string]$GpuPlugin = '',
    [switch]$Collections,
    [switch]$KeepBuildFiles,
    [int]$BakeMinutes = 0,
    [string]$Ios26Config = '',
    [string]$WatchIpsw = '',
    [string[]]$WatchDir = @(),
    [string]$WatchQemu = '',
    [switch]$NoShortcut,
    [string]$State = (Join-Path $env:LOCALAPPDATA 'ASoftware\setup.json')
)
$ErrorActionPreference = 'Stop'
$src = (Resolve-Path "$PSScriptRoot\..").Path
$Inst16 = Join-Path $src 'installer\Install-ASoftware.ps1'
$Inst26 = Join-Path $src 'ios26\Install-iOS26.ps1'
$InstW = Join-Path $src 'watchos\Install-watchOS.ps1'
# the release package's own QEMU (Make-Release.ps1), which both take instead of downloading one
$PkgQemu = Join-Path $src 'qemu\bin'
if (-not $QemuDist -and (Test-Path (Join-Path $PkgQemu 'qemu-system-aarch64.exe'))) { $QemuDist = $PkgQemu }

if (-not $Lang) {
    $Lang = if ((Get-UICulture).TwoLetterISOLanguageName -eq 'tr' -or (Get-Culture).TwoLetterISOLanguageName -eq 'tr') { 'tr' } else { 'en' }
}
function L([string]$en, [string]$tr) { if ($Lang -eq 'tr') { $tr } else { $en } }
function Fail([string]$why, [int]$code = 1) { Write-Host ''; Write-Host $why -ForegroundColor Red; exit $code }
foreach ($p in @(@('Version', $Version, @('ios16', 'ios26', 'both')), @('Watch', $Watch, @('yes', 'no')), @('Linux', $Linux, @('wsl', 'helper')),
                 @('Lang', $Lang, @('en', 'tr')), @('IfNoWsl', $IfNoWsl, @('install', 'nowsl')))) {
    if ($p[1] -and $p[2] -cnotcontains $p[1]) { Fail "-$($p[0]) $($p[1]): one of $($p[2] -join ', ')" }
}
# -WatchDir's folders, as Install-watchOS.ps1 splits them ('|', or ',' in what is no folder as a whole:
# Apple's names have commas, D:\ipsw\Watch7,1); passed on joined by '|' (and again after a resume)
function Split-WatchDirs {
    @($WatchDir | ForEach-Object { "$_" -split '\|' } | Where-Object { $_ } | ForEach-Object {
            if ((Test-Path -LiteralPath $_ -PathType Container) -or $_ -cnotmatch ',') { $_ } else { $_ -split ',' }
        } | Where-Object { $_ })
}
$WatchDirs = Split-WatchDirs
$Pretends = @($Pretend -split '[,\s]+' | Where-Object { $_ })
foreach ($p in $Pretends) { if (@('nowsl', 'novirt', 'helper') -cnotcontains $p) { Fail "-Pretend $p`: nowsl, novirt or helper" } }
$ReadOnly = $Estimate -or $List -or $Check -or $DryRun

# --- Running tools ---------------------------------------------------------------------------
# A native tool's output lines and exit code; Windows PowerShell 5.1 turns its stderr into
# errors, here they are just lines
function Invoke-Native([string]$exe, [string[]]$argv) {
    $ErrorActionPreference = 'Continue'
    $out = @(& $exe @argv 2>&1 | ForEach-Object { ("$_" -replace "`0", '').TrimEnd() })
    @{ Code = $LASTEXITCODE; Out = $out }
}
# One of the two installers, in this console (its own progress bars and questions work), and its
# exit code. Waited for itself only: what it leaves running is not waited for (Start-Process -Wait
# would wait for that too)
function Run-Installer([string]$script, [string[]]$argv) {
    $q = @($script) + $argv | ForEach-Object { if ("$_" -eq '' -or "$_" -match '[\s"]') { '"' + ("$_" -replace '"', '\"') + '"' } else { "$_" } }
    Write-Host "  > powershell -File $($q -join ' ')" -ForegroundColor DarkGray
    $p = Start-Process powershell.exe -ArgumentList ((@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File') + $q) -join ' ') -NoNewWindow -PassThru
    $null = $p.Handle
    $p.WaitForExit()
    $p.ExitCode
}

# --- The two installers' own tables ----------------------------------------------------------
# The pinned sizes and step lists, read from their source so the numbers here are theirs: these
# variables' top-level assignments, run in order in a scope of their own
function Read-Tables([string]$file, [string[]]$names) {
    $ast = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
    $text = @($ast.EndBlock.Statements | Where-Object {
            $_ -is [Management.Automation.Language.AssignmentStatementAst] -and
            $_.Left -is [Management.Automation.Language.VariableExpressionAst] -and
            $names -contains $_.Left.VariablePath.UserPath
        } | ForEach-Object { $_.Extent.Text }) -join "`n"
    $get = ($names | ForEach-Object { "'$_' = `$$_" }) -join '; '
    & ([scriptblock]::Create("$text`n@{ $get }"))
}
function Has-Param([string]$file, [string]$name) {
    $ast = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
    [bool]($ast.ParamBlock -and @($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $name }).Count)
}
# Our QEMU build with the watch's devices (qemu-sptm asoft-watch: usb-crown) in a folder, as
# Install-watchOS.ps1 checks it; iOS's QEMU (the package's qemu\bin) does not have them
function Qemu-HasWatch([string]$dir) {
    # (Combine, not Join-Path, which throws on a drive that is not there)
    if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return $false }
    $exe = [IO.Path]::Combine($dir, 'qemu-system-aarch64.exe')
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $false }
    [bool]((Invoke-Native $exe @('-device', 'help')).Out | Where-Object { $_ -cmatch '"usb-crown"' })
}
# watchOS's QEMU: -WatchQemu, else -QemuDist (the package's qemu\bin) when it is a watch build, else what
# <work>\qemu-watch has, else the watch installer's pinned package (none is published yet). Dir: the
# folder Install-watchOS.ps1 gets as -QemuFrom; Why: why there is none
function Watch-Qemu([string]$work) {
    $r = @{ Dir = $null; There = $false; Why = '' }
    if ($work) { $r.There = Qemu-HasWatch ([IO.Path]::Combine($work, 'qemu-watch')) }
    if ($WatchQemu) {
        $d = [IO.Path]::GetFullPath($WatchQemu).TrimEnd('\')
        if (Qemu-HasWatch $d) { $r.Dir = $d }
        else { $r.Why = L "-WatchQemu $d`: no qemu-system-aarch64.exe with the watch's devices (usb-crown) there" "-WatchQemu $d`: orada saatin aygıtlarını (usb-crown) içeren qemu-system-aarch64.exe yok" }
    } elseif ($QemuDist -and (Qemu-HasWatch ([IO.Path]::GetFullPath($QemuDist)))) {
        $r.Dir = [IO.Path]::GetFullPath($QemuDist).TrimEnd('\')
    } elseif (-not $r.There -and -not $TW.QemuWatchRelease.Url) {
        $r.Why = L "watchOS's QEMU (our build with the watch's devices) is not published yet: give one with -WatchQemu <folder>" "watchOS'un QEMU'su (saatin aygıtlarını içeren derlememiz) henüz yayımlanmadı: -WatchQemu <klasör> ile verin"
    }
    $r
}
$T16 = Read-Tables $Inst16 @('ipswUrl', 'ipswSize', 'pythonUrl', 'QemuRelease', 'space', 'Steps')
$T26 = Read-Tables $Inst26 @('QemuRelease', 'Pin', 'CloudOsUrl', 'IPhoneUrl', 'CloudOsFiles', 'CloudOsGpuImage', 'OsImage',
                             'SysOsImage', 'AppOsImage', 'IPhoneFiles', 'GpuPluginRelease', 'Space', 'Steps')
# watchOS (on what iOS 26 installed), where this version has its installer
$TW = if (Test-Path $InstW) { Read-Tables $InstW @('WatchUrl', 'OsImage', 'WatchFiles', 'QemuWatchRelease', 'Space', 'Steps') } else { $null }
# the install without WSL: Install-iOS26.ps1's -Linux helper and the helper VM it boots
# (installer\helper\out: in the release package; a git checkout builds it, README.md "Without WSL")
$Has26Linux = Has-Param $Inst26 'Linux'
$HelperVm = (Test-Path (Join-Path $src 'installer\helper\out\Image.gz')) -and (Test-Path (Join-Path $src 'installer\helper\out\initrd.gz'))
$HelperReal = $Has26Linux -and $HelperVm
$Helper = $HelperReal -or ($Pretends -ccontains 'helper')
$HelperWhy = if (-not $Has26Linux) { L 'not in this version yet' 'bu sürümde henüz yok' }
             else { L 'no helper VM in installer\helper\out (the release package has it; a git checkout builds it: ios26\README.md, "Without WSL")' 'installer\helper\out''ta yardımcı VM yok (sürüm paketinde var; git checkout''ta derlenir: ios26\README.md, "Without WSL")' }

# --- Estimates ---------------------------------------------------------------------------------
# Sizes of the small downloads the tables give only as URLs (bytes, HTTP Content-Length, 2026-11-01)
$Bytes = @{ Qemu = 130774263; Python = 11133606; Sysroot = 5409409; DtFixup = 12448; GpuPlugin = 72160; IpswWin = 30720439 }
# The build distro from nothing (the wsl step without one): Ubuntu 24.04's WSL package (388 975 696
# bytes), the WSL kernel's source for the hfsplus module (230 259 456), ipsw (33 619 542) and the apt
# packages (about 250 MB). S: apt, apfs-fuse and the rest on one thread; KernelS: the module build
# (make modules), 8 min on our PC's 24 threads (its build log's times); SysGB: what the distro takes
# on the drive WSL keeps distros on (the kernel tree alone 4.6 GB)
$WslFresh = @{ Bytes = 388975696 + 230259456 + 33619542 + 250e6; Distro = 388975696; S = 300; KernelS = 480; KernelThr = 24; SysGB = 7.0 }
# Per step, measured on our PC (i7-13700HX, 24 logical processors, NVMe SSD, 2026-11-01): S the
# seconds it takes beyond its download, Thr the threads it keeps busy (a PC with fewer logical
# processors takes Thr/cores times as long), Add the GB (10^9) it adds at its height on the
# install drive and Keep what it leaves (both before the installer's own removals), Dl its download.
$Ref = 'i7-13700HX (24)'
# iOS 16: measured through this script on 2026-11-01 (43 min with -Ipsw; Thr is the QEMU's CPU
# seconds over the step's wall time: its vCPUs are not all busy)
$Ref16 = [ordered]@{
    app        = @{ S = 5; Thr = 1; Add = 0.70; Keep = 0.70 }     # app, QEMU, kernel: 0.7 GB
    python     = @{ S = 1; Thr = 1; Add = 0.05; Keep = 0.05 }
    ipsw       = @{ S = 10; Thr = 1; Add = 6.17; Keep = 6.17 }    # SHA-256 of 6.2 GB, the device tree
    disk       = @{ S = 1277; Thr = 3; Add = 20.0; Keep = 12.4 }  # the disk and its scratch disk (7.6 GB)
    firststart = @{ S = 1292; Thr = 3; Add = 0.5; Keep = 0.5 }    # then the downloaded IPSW goes
    shortcut   = @{ S = 1; Thr = 1; Add = 0; Keep = 0 }
}
# iOS 26: measured through this script on 2026-11-03 (WSL; 75 min of steps, 59 of them the wallpaper
# step, which now waits for DataMigration); Add/Keep from the drive's free space and the files left.
# H: the step without WSL (-Linux helper), measured through this script on 2026-11-04 (107 min of
# steps, 46 of them the Linux steps; the wallpaper and first boot steps took what they take with WSL),
# partly with an iOS 27 QEMU running alongside
$Ref26 = [ordered]@{
    setup       = @{ S = 2; Thr = 1; Add = 0.01; Keep = 0.01 }
    prereq      = @{ S = 2; Thr = 1; Add = 0; Keep = 0 }
    wsl         = @{ S = 60; Thr = 4; Add = 0; Keep = 0; Linux = $true; H = 15 }    # the tools there already: apt, a check
    python      = @{ S = 1; Thr = 1; Add = 0.05; Keep = 0.05 }
    qemu        = @{ S = 5; Thr = 1; Add = 0.66; Keep = 0.66 }
    sysroot     = @{ S = 3; Thr = 1; Add = 0.01; Keep = 0.01 }
    cloudos     = @{ S = 10; Thr = 1; Add = 1.02; Keep = 1.02 }
    iphone      = @{ S = 30; Thr = 1; Add = 10.2; Keep = 10.2 }
    decrypt     = @{ S = 98; Thr = 4; Add = 10.3; Keep = 0; Linux = $true; H = 19 }   # rootfs removes its images
    firmware    = @{ S = 10; Thr = 1; Add = 0.1; Keep = 0.1; Linux = $true; H = 1 }
    devicetree  = @{ S = 1; Thr = 1; Add = 0; Keep = 0 }
    ramdisk     = @{ S = 14; Thr = 2; Add = 0.3; Keep = 0.1; Linux = $true; H = 106 }
    rootfs      = @{ S = 332; Thr = 4; Add = 23.5; Keep = 18.4; Linux = $true; H = 1774 }   # root26.qcow2 18.4 GB
    trustcache  = @{ S = 1; Thr = 1; Add = 0; Keep = 0 }
    partition   = @{ S = 197; Thr = 2; Add = 18.2; Keep = 0; Linux = $true; H = 176 }      # root26g replaces root26
    tweaks      = @{ S = 8; Thr = 1; Add = 0.1; Keep = 0.1; Linux = $true; H = 86 }
    firstboot   = @{ S = 106; Thr = 6; Add = 0.2; Keep = 0.2 }
    persona     = @{ S = 7; Thr = 1; Add = 0.2; Keep = 0.2; Linux = $true; H = 46 }
    activation  = @{ S = 13; Thr = 1; Add = 0.2; Keep = 0.2; Linux = $true; H = 87 }
    apps        = @{ S = 76; Thr = 2; Add = 2.0; Keep = 2.0; Linux = $true; H = 359 }
    gpu         = @{ S = 19; Thr = 2; Add = 0.3; Keep = 0; Linux = $true; H = 58 }
    wallpaper   = @{ S = 3524; Thr = 6; Add = 1.9; Keep = 1.75 }   # 52 min of it DataMigration
    collections = @{ S = 0; Thr = 1; Add = 0; Keep = 0 }
    cleanup     = @{ S = 21; Thr = 1; Add = 0; Keep = -10.2; Linux = $true; H = 1 }
    shortcut    = @{ S = 1; Thr = 1; Add = 0; Keep = 0 }
}
# watchOS: Install-watchOS.ps1's steps on what iOS 26 left (WSL only); the times of its end-to-end run
# (measured 2026-11-08 on the test bed: decrypt 41 s, rootfs 4.5 min, patches 1 min, the first boot to
# the watch face 14 min, then 60 s and a sync; download's S is its hashing, the bytes go by bandwidth)
$RefW = [ordered]@{
    check      = @{ S = 3; Thr = 1; Add = 0.01; Keep = 0.01 }
    qemu       = @{ S = 10; Thr = 1; Add = 0.55; Keep = 0.55 }
    download   = @{ S = 30; Thr = 1; Add = 5.03; Keep = 5.03 }
    decrypt    = @{ S = 45; Thr = 4; Add = 8.4; Keep = 3.37; Linux = $true }    # the image replaces its .aea
    firmware   = @{ S = 8; Thr = 1; Add = 0.1; Keep = 0.1 }
    gpu        = @{ S = 15; Thr = 1; Add = 0.05; Keep = 0.05; Linux = $true }
    rootfs     = @{ S = 270; Thr = 4; Add = 11.9; Keep = 3.45; Linux = $true }  # rootw.qcow2 11.85 GB; the image goes
    patches    = @{ S = 70; Thr = 2; Add = 0.5; Keep = 0.45; Linux = $true }
    trustcache = @{ S = 2; Thr = 1; Add = 0; Keep = 0 }
    firstboot  = @{ S = 960; Thr = 6; Add = 1.1; Keep = 1.1 }
    activation = @{ S = 20; Thr = 1; Add = 0; Keep = 0; Linux = $true }
    cleanup    = @{ S = 5; Thr = 1; Add = 0; Keep = -0.1 }
    shortcut   = @{ S = 1; Thr = 1; Add = 0; Keep = 0 }
}
# The install without WSL: a Linux step with no H takes this many times its WSL time (the helper VM
# runs Linux under TCG; the measured ones took 0.05 to 11 times as long)
$HelperFactor = 4

# GB as the README and both installers count them (10^9; Explorer's are 2^30)
function Fmt-Size([double]$bytes) {
    if ($bytes -lt 1e6) { return '< 1 MB' }
    if ($bytes -lt 1e9) { return ('{0:N0} MB' -f ($bytes / 1e6)) }
    '{0:N1} GB' -f ($bytes / 1e9)
}
function Fmt-Time([double]$s) {
    if ($s -lt 60) { return (L '< 1 min' '< 1 dk') }
    $m = [Math]::Round($s / 60)
    if ($m -lt 60) { return ("$m " + (L 'min' 'dk')) }
    $h = [Math]::Floor($m / 60); $m = $m - 60 * $h
    if ($m -eq 0) { return ("$h " + (L 'h' 'sa')) }
    "$h " + (L 'h' 'sa') + " $m " + (L 'min' 'dk')
}

# The steps of a choice: version, id, title, download bytes, reference seconds, threads, GB
function Plan-16([bool]$qemuThere) {
    $have = { param($p) $p -and (Test-Path $p) }
    foreach ($s in $T16.Steps) {
        $r = $Ref16[$s.Id]
        $dl = 0; $add = $r.Add; $keep = $r.Keep
        switch ($s.Id) {
            'app' { if (-not $qemuThere -and -not $QemuDist) { $dl = $Bytes.Qemu } }
            'python' { $dl = $Bytes.Python }
            # an IPSW you have is read where it is
            'ipsw' { if (-not (& $have $Ipsw)) { $dl = $T16.ipswSize } else { $add = 0; $keep = 0 } }
            'firststart' { if (-not (& $have $Ipsw) -and -not $KeepIpsw) { $keep -= $T16.ipswSize / 1e9 } }
        }
        @{ Ver = 'ios16'; Id = $s.Id; Title = $s.Title; Dl = $dl; S = $r.S; Thr = $r.Thr; Add = $add; Keep = $keep; Linux = $false }
    }
}
function Plan-26([string]$how, [bool]$qemuShared, [string]$wslState) {
    $cloud = 0; foreach ($v in $T26.CloudOsFiles.Values) { $cloud += $v }
    $phone = 0; foreach ($v in $T26.IPhoneFiles.Values) { $phone += $v }
    foreach ($s in $T26.Steps) {
        # the wsl step is "linux" where Install-iOS26.ps1 has -Linux; a step not measured yet: a minute
        $r = $Ref26[$s.Id]
        if (-not $r -and $s.Id -eq 'linux') { $r = $Ref26['wsl'] }
        if (-not $r) { $r = @{ S = 60; Thr = 1; Add = 0; Keep = 0 } }
        $dl = 0; $sec = $r.S; $thr = $r.Thr; $add = $r.Add; $keep = $r.Keep
        switch -regex ($s.Id) {
            '^(wsl|linux)$' {
                if ($how -eq 'helper') { $thr = 1; $dl = $Bytes.IpswWin }   # ipsw.exe, the helper VM's self-test
                elseif ($wslState -ne 'set') {
                    $dl = $WslFresh.Bytes; $thr = 1
                    if ($wslState -eq 'bare') { $dl -= $WslFresh.Distro }
                    $sec = $WslFresh.S + $WslFresh.KernelS * [Math]::Max(1.0, $WslFresh.KernelThr / [double]$Pc.Cores)
                }
            }
            'python' { $dl = $Bytes.Python }
            'qemu' { if ($qemuShared -and -not $QemuDist) { $add = 0.13; $keep = 0.13 } elseif ($qemuShared) { $add = 0; $keep = 0 } elseif (-not $QemuDist) { $dl = $Bytes.Qemu } }
            'sysroot' { $dl = $Bytes.Sysroot }
            'cloudos' { if (-not $CloudOsIpsw) { $dl = $cloud } }
            'iphone' { if (-not $IPhoneIpsw) { $dl = $phone } }
            'devicetree' { $dl = $Bytes.DtFixup }
            'gpu' { if (-not $GpuPlugin) { $dl = $Bytes.GpuPlugin } }
            'collections' { if ($Collections) { $sec = 900; $add = 1.5; $keep = 1.5 } }
        }
        if ($how -eq 'helper' -and $r.Linux) { $sec = if ($r.H) { $r.H } else { $sec * $HelperFactor } }
        # a step an earlier run finished (Install-iOS26.ps1 skips it): what it left is there already
        $done = Test-Path (Join-Path $Work "install\$($s.Id).done")
        @{ Ver = 'ios26'; Id = $s.Id; Title = $s.Title; Dl = $dl; S = $sec; Thr = $thr; Add = $add; Keep = $keep; Linux = [bool]$r.Linux; Done = $done }
    }
}
function Plan-Watch {
    foreach ($s in $TW.Steps) {
        $r = $RefW[$s.Id]
        if (-not $r) { $r = @{ S = 60; Thr = 1; Add = 0; Keep = 0 } }
        $dl = 0; $add = $r.Add; $keep = $r.Keep
        switch ($s.Id) {
            # Apple's three members, but for what comes from this PC: the IPSW, or -WatchDir's files (the
            # device tree also unwrapped), as Install-watchOS.ps1's download step takes them
            'download' {
                if (-not $WatchIpsw) {
                    foreach ($m in $TW.WatchFiles.Keys) {
                        $n = [IO.Path]::GetFileName($m)
                        $names = @($n) + $(if ($n -ceq 'DeviceTree.n207sap.im4p') { @('DeviceTree.n207sap.raw') } else { @() })
                        # (a folder on a drive that is not there counts for nothing: Join-Path would throw)
                        $here = @(foreach ($d in $WatchDirs) {
                                if (-not (Test-Path -LiteralPath $d -PathType Container)) { continue }
                                foreach ($x in $names) { if (Test-Path -LiteralPath ([IO.Path]::Combine($d, $x)) -PathType Leaf) { $x } } })
                        if (-not $here.Count) { $dl += $TW.WatchFiles[$m] }
                    }
                }
            }
            'qemu' { if ($TW.QemuWatchRelease.Url -and -not $WatchQemuDir -and -not $WatchQemuThere) { $dl = $Bytes.Qemu } }
        }
        $done = Test-Path (Join-Path $Work "install\watch-$($s.Id).done")
        @{ Ver = 'watch'; Id = $s.Id; Title = $s.Title; Dl = $dl; S = $r.S; Thr = $r.Thr; Add = $add; Keep = $keep; Linux = [bool]$r.Linux; Done = $done }
    }
}
function Step-Seconds($st, [double]$bps) {
    $cpu = $st.S * [Math]::Max(1.0, $st.Thr / [double]$Pc.Cores)
    $(if ($bps -gt 0) { $st.Dl / $bps } else { 0 }) + $cpu
}
# download bytes, seconds, peak and after (GB, 10^9) of a list of steps, in order; Need: the room the
# steps left to run still take (the peak less what finished steps left on the drive)
function Sum-Plan($steps, [double]$bps) {
    $dl = 0; $sec = 0; $cum = 0; $peak = 0; $there = 0
    foreach ($st in $steps) {
        if ($st.Done) { $cum += $st.Keep; $there = $cum; $peak = [Math]::Max($peak, $cum); continue }
        $dl += $st.Dl
        $sec += Step-Seconds $st $bps
        $peak = [Math]::Max($peak, $cum + $st.Add)
        $cum += $st.Keep
    }
    @{ Dl = $dl; S = $sec; Peak = $peak * 1e9; After = $cum * 1e9; Need = ($peak - $there) * 1e9 }
}

# --- This PC -----------------------------------------------------------------------------------
function Get-Pc {
    $os = [Environment]::OSVersion.Version
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = @(Get-CimInstance Win32_Processor)[0]
    $gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object Name)
    # Vulkan: the loader, and a driver for it (DCH drivers register in the display adapter's key; its
    # Properties subkey refuses a user, so errors are skipped, not stopped on)
    $icd = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
        ForEach-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).VulkanDriverName } | Where-Object { $_ })
    if (Test-Path 'HKLM:\SOFTWARE\Khronos\Vulkan\Drivers') { $icd += @((Get-Item 'HKLM:\SOFTWARE\Khronos\Vulkan\Drivers').Property) }
    @{
        Os = "$os"; Build = $os.Build; X64 = [Environment]::Is64BitOperatingSystem
        Cores = [Environment]::ProcessorCount; Ram = [Math]::Round($cs.TotalPhysicalMemory / 1GB)
        Cpu = "$($cpu.Name)".Trim(); Gpus = $gpus
        VkLoader = Test-Path (Join-Path $env:SystemRoot 'System32\vulkan-1.dll'); VkDrivers = @($icd).Count
        Hypervisor = [bool]$cs.HypervisorPresent; VirtFw = $cpu.VirtualizationFirmwareEnabled
    }
}
# ok: WSL 2 runs here (a WSL 2 distro, or WSL with no distro yet); missing: not installed or not
# working; novirt: virtualization is off in the firmware, so WSL 2 cannot start
function Get-WslState {
    if ($Pretends -ccontains 'novirt') { return @{ State = 'novirt'; Distros = @{}; Why = '-Pretend novirt' } }
    if ($Pretends -ccontains 'nowsl') { return @{ State = 'missing'; Distros = @{}; Why = '-Pretend nowsl' } }
    $off = (-not $Pc.Hypervisor) -and ($Pc.VirtFw -eq $false)
    $d = @{}
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        return @{ State = $(if ($off) { 'novirt' } else { 'missing' }); Distros = $d; Why = 'no wsl.exe' }
    }
    $env:WSL_UTF8 = '1'
    $l = Invoke-Native 'wsl.exe' @('-l', '-v')
    if ($l.Code -eq 0) {
        foreach ($line in @($l.Out | Select-Object -Skip 1)) {
            $f = @(($line -replace '^\*\s*', '') -split '\s+' | Where-Object { $_ })
            if ($f.Count -ge 3) { $d[$f[0]] = $f[-1] }
        }
    }
    $installed = ($l.Code -eq 0) -or ((Invoke-Native 'wsl.exe' @('--status')).Code -eq 0)
    if ($off) { return @{ State = 'novirt'; Distros = $d; Why = 'VirtualizationFirmwareEnabled = False' } }
    if (-not $installed) { return @{ State = 'missing'; Distros = $d; Why = 'wsl -l -v and wsl --status fail' } }
    if ($d.Count -and -not @($d.Values | Where-Object { "$_" -eq '2' }).Count) {
        return @{ State = 'ok'; Distros = $d; Why = 'WSL 1 distros only; the installer makes a WSL 2 one' }
    }
    @{ State = 'ok'; Distros = $d; Why = '' }
}
function Free-Bytes([string]$path) {
    try { ([IO.DriveInfo]::new([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($path)))).AvailableFreeSpace } catch { 0 }
}
# bytes per second from 10 MB of an Apple IPSW, or $null
function Probe-Bandwidth([string]$url) {
    $r = Invoke-Native 'curl.exe' @('-s', '-o', 'NUL', '-r', '0-10485759', '--max-time', '40', '-w', '%{speed_download} %{size_download}', $url)
    if ($r.Code -eq 0 -and "$($r.Out[-1])" -match '^([\d.]+) ([\d.]+)') {
        if ([double]$Matches[2] -ge 1e6) { return [double]$Matches[1] }
    }
    $null
}

# --- Questions and the saved choices -----------------------------------------------------------
function Ask([string]$question, [object[]]$options, [int]$default) {
    Write-Host ''
    Write-Host $question -ForegroundColor White
    for ($i = 0; $i -lt $options.Count; $i++) {
        $o = $options[$i]
        $mark = if ($i -eq $default) { '*' } else { ' ' }
        Write-Host ("  {0}[{1}] {2}" -f $mark, ($i + 1), $o[0]) -ForegroundColor $(if ($o[2]) { 'DarkGray' } else { 'Gray' })
        if ($o[1]) { Write-Host ("       {0}" -f $o[1]) -ForegroundColor DarkGray }
    }
    if ($Yes -or $ReadOnly -or [Console]::IsInputRedirected) {
        Write-Host ('  -> [{0}] {1}' -f ($default + 1), $options[$default][0]) -ForegroundColor DarkGray
        return $default
    }
    while ($true) {
        $a = (Read-Host (L "Choose [$($default + 1)]" "Seçin [$($default + 1)]")).Trim()
        if (-not $a) { return $default }
        if ($a -match '^\d+$' -and [int]$a -ge 1 -and [int]$a -le $options.Count) { return [int]$a - 1 }
        Write-Host (L "1 to $($options.Count), or Enter" "1-$($options.Count) arası bir sayı ya da Enter") -ForegroundColor Yellow
    }
}
function Read-State {
    if (Test-Path $State) { try { return (Get-Content $State -Raw | ConvertFrom-Json) } catch { } }
    $null
}
function Save-State([hashtable]$keys) {
    if ($ReadOnly) { return }
    $o = [ordered]@{}
    $c = Read-State
    if ($c) { foreach ($p in $c.PSObject.Properties) { $o[$p.Name] = $p.Value } }
    foreach ($k in $keys.Keys) { $o[$k] = $keys[$k] }
    $o['Updated'] = (Get-Date).ToString('s')
    New-Item -ItemType Directory -Force (Split-Path $State) | Out-Null
    ($o | ConvertTo-Json) | Set-Content -Encoding UTF8 $State
}
function Version-Name([string]$v) {
    switch ($v) { 'ios16' { 'iOS 16' } 'ios26' { 'iOS 26' } 'both' { L 'iOS 16 and iOS 26' 'iOS 16 ve iOS 26' } }
}
function Linux-Name([string]$h) { if ($h -eq 'helper') { L 'without WSL' "WSL'siz" } else { 'WSL' } }
# watchOS's sources for setup.json, so a resumed run (with no arguments) has them again: the watch QEMU
# folder found (Watch-Qemu's Dir), -WatchIpsw and -WatchDir as full paths
function Watch-Sources([string]$qemuDir) {
    @{ WatchQemu = $(if ($WantWatch -and $qemuDir) { $qemuDir } else { '' })
       WatchIpsw = $(if ($WantWatch -and $WatchIpsw) { [IO.Path]::GetFullPath($WatchIpsw) } else { '' })
       WatchDir = $(if ($WantWatch -and $WatchDirs) { @($WatchDirs | ForEach-Object { [IO.Path]::GetFullPath($_) }) -join '|' } else { '' }) }
}
# The install folder when -Dir does not say: <the fixed drive with the most room>:\ASoftware
function Default-Dir {
    $best = [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } |
        Sort-Object AvailableFreeSpace -Descending | Select-Object -First 1
    Join-Path $best.Name 'ASoftware'
}

# --- Start -------------------------------------------------------------------------------------
$host.UI.RawUI.WindowTitle = L 'ASoftware iOS setup' 'ASoftware iOS kurulumu'
Write-Host ''
Write-Host (L 'ASoftware iOS setup' 'ASoftware iOS kurulumu') -ForegroundColor Cyan
if ($Pretends) { Write-Host "  (-Pretend $($Pretends -join ','))" -ForegroundColor Yellow }
$Pc = Get-Pc
Write-Host ("  {0}; {1} {2}, {3} GB RAM; Windows {4}" -f $Pc.Cpu, $Pc.Cores, (L 'logical processors' 'mantıksal işlemci'), $Pc.Ram, $Pc.Os) -ForegroundColor DarkGray

# a run that stopped (or waits for the restart after installing WSL) goes on with its choices
$Saved = Read-State
$resumed = $false
if ($Saved -and "$($Saved.Stage)" -ne 'done' -and -not $Version -and -not $Linux) {
    $what = "$(Version-Name $Saved.Version)$(if ($Saved.Version -ne 'ios16') { ', ' + (Linux-Name $Saved.Linux) }), $($Saved.Dir)"
    $i = Ask ((L 'An install was started here' 'Burada başlamış bir kurulum var') + " ($($Saved.Started)): $what") @(
        @((L 'Go on with it' 'Ona devam et'), (L 'it resumes where it stopped' 'kaldığı yerden sürer'), $false),
        @((L 'Choose again' 'Yeniden seç'), '', $false)) 0
    if ($i -eq 0) {
        $Version = "$($Saved.Version)"; $Linux = "$($Saved.Linux)"
        if (-not $Watch -and $Saved.Watch) { $Watch = "$($Saved.Watch)" }
        if (-not $Dir) { $Dir = "$($Saved.Dir)" }
        # watchOS's own sources, which a run with no arguments (the one-liner) cannot pass again
        if (-not $WatchQemu -and $Saved.WatchQemu) { $WatchQemu = "$($Saved.WatchQemu)" }
        if (-not $WatchIpsw -and $Saved.WatchIpsw) { $WatchIpsw = "$($Saved.WatchIpsw)" }
        if (-not $WatchDir -and $Saved.WatchDir) { $WatchDir = @("$($Saved.WatchDir)"); $WatchDirs = Split-WatchDirs }
        $resumed = $true
    }
}

# --- 1. Which iOS ------------------------------------------------------------------------------
if (-not $Version) {
    $i = Ask (L 'Which iOS?' 'Hangi iOS?') @(
        @((L 'iOS 16.7.16 (iPhone X): ready to use, Safari and .ipa apps' 'iOS 16.7.16 (iPhone X): kullanıma hazır, Safari ve .ipa uygulamaları'),
          (L 'no WSL and no administrator needed; about an hour' 'WSL ve yönetici izni gerekmez; yaklaşık bir saat'), $false),
        @((L "iOS 26.6.2 (iPhone 16): research preview, drawn by your PC's GPU" "iOS 26.6.2 (iPhone 16): araştırma önizlemesi, PC'nin GPU'suyla çizilir"),
          (L 'two to three hours, about 50 GB at its peak; a Vulkan GPU' 'iki üç saat sürer, en çok yaklaşık 50 GB; Vulkan destekli GPU'), $false),
        @((L 'Both' 'İkisi de'), (L 'one QEMU for both, downloaded once' 'ikisine tek QEMU, bir kez indirilir'), $false)) 0
    $Version = @('ios16', 'ios26', 'both')[$i]
}
$Want16 = $Version -ne 'ios26'
$Want26 = $Version -ne 'ios16'

# --- 1b. watchOS on iOS 26 ---------------------------------------------------------------------
$WantWatch = $false
if ($Want26 -and $TW) {
    # its QEMU first: a watch this version cannot build must not lead to the WSL question or a WSL install
    # (the work folder this run will use, from -Dir, the run being resumed or the default, may have one
    # in qemu-watch\)
    $wq = Watch-Qemu ([IO.Path]::Combine([IO.Path]::GetFullPath($(if ($Dir) { $Dir } else { Default-Dir })).TrimEnd('\'), 'work'))
    if (-not $Watch) {
        $wdl = 0; foreach ($v in $TW.WatchFiles.Values) { $wdl += $v }
        $i = Ask (L 'watchOS 27.2 too (Apple Watch Series 9), built on what iOS 26 installs?' 'watchOS 27.2 de kurulsun mu (Apple Watch Series 9), iOS 26''nın kurduklarının üstüne?') @(
            @((L 'No' 'Hayır'), '', $false),
            @((L 'Yes' 'Evet'), $(if ($wq.Why) { $wq.Why } else { L "about $(Fmt-Size $wdl) more download and 13 GB more disk; WSL; its own launcher, Start-watchOS.cmd" "yaklaşık $(Fmt-Size $wdl) daha indirme ve 13 GB daha disk; WSL; kendi başlatıcısı, Start-watchOS.cmd" }), [bool]$wq.Why)) 0
        $Watch = @('no', 'yes')[$i]
    }
    if ($Watch -eq 'yes' -and $wq.Why) { Fail ((L 'watchOS cannot be installed here: ' 'watchOS burada kurulamaz: ') + $wq.Why + (L ' (or -Watch no)' ' (ya da -Watch no)')) 2 }
    $WantWatch = $Watch -eq 'yes'
} elseif ($Watch -eq 'yes') {
    Fail (L '-Watch yes needs iOS 26 (-Version ios26 or both): watchOS is built on it' '-Watch yes iOS 26 ister (-Version ios26 ya da both): watchOS onun üstüne kurulur')
}

# --- 2. iOS 26: WSL or not ---------------------------------------------------------------------
$Wsl = $null
if ($Want26) {
    $Wsl = Get-WslState
    $wslNote = switch ($Wsl.State) {
        'ok' { L 'WSL 2 is ready on this PC' "WSL 2 bu PC'de hazır" }
        'missing' { L 'WSL is not installed: it needs an administrator and a restart' 'WSL kurulu değil: yönetici izni ve yeniden başlatma ister' }
        'novirt' { L 'WSL 2 cannot start: virtualization is off in the firmware' 'WSL 2 çalışamaz: sanallaştırma BIOS/UEFI''de kapalı' }
    }
    $helperNote = if ($Helper) { L 'a small Linux VM in our QEMU; no administrator, no restart' 'QEMU''da küçük bir Linux VM; yönetici ve yeniden başlatma gerekmez' }
                  else { $HelperWhy }
    if ($Wsl.State -eq 'novirt') {
        Write-Host ''
        if (-not $Helper) {
            Fail ((L "Virtualization is off in the firmware (BIOS/UEFI), so WSL 2 cannot start, and the install without WSL cannot run here either: $HelperWhy. Turn on Intel VT-x or AMD-V (SVM) in the BIOS/UEFI setup and run this again, or install iOS 16, which needs neither." `
                     "Sanallaştırma BIOS/UEFI'de kapalı, WSL 2 çalışamaz; WSL'siz kurulum da burada çalışamaz: $HelperWhy. BIOS/UEFI ayarlarından Intel VT-x ya da AMD-V'yi (SVM) açıp bunu yeniden çalıştırın ya da ikisini de istemeyen iOS 16'yı kurun.") + " ($($Wsl.Why))") 2
        }
        if ($Linux -eq 'wsl') { Write-Host (L '-Linux wsl: WSL 2 cannot start here (virtualization is off in the firmware).' '-Linux wsl: WSL 2 burada çalışamaz (sanallaştırma BIOS/UEFI''de kapalı).') -ForegroundColor Yellow }
        Write-Host (L 'Virtualization is off in the firmware (BIOS/UEFI), so WSL 2 cannot start: installing without WSL.' 'Sanallaştırma BIOS/UEFI''de kapalı, WSL 2 çalışamaz: WSL''siz kuruluma geçildi.') -ForegroundColor Yellow
        $Linux = 'helper'
    }
    if (-not $Linux) {
        # WSL when it works or -IfNoWsl install says to get it (or watchOS, which needs it), else the
        # helper when there is one
        $default = if ($IfNoWsl -ne 'install' -and $Wsl.State -ne 'ok' -and $Helper -and -not $WantWatch) { 1 } else { 0 }
        $i = Ask (L "How should the iOS 26 build run its Linux tools? (iOS 16 never needs WSL.)" "iOS 26 kurulumu Linux araçlarını nasıl çalıştırsın? (iOS 16 hiç WSL istemez.)") @(
            @((L 'Fast install with WSL' 'Hızlı kurulum (WSL)'), $wslNote, $false),
            @((L 'Install without WSL' 'WSL''siz kurulum'), $helperNote, (-not $Helper))) $default
        $Linux = @('wsl', 'helper')[$i]
    }
    if ($Linux -eq 'helper' -and -not $Helper) {
        Fail (L "The install without WSL cannot run here: $HelperWhy. Choose WSL, or iOS 16, which never needs WSL." `
                "WSL'siz kurulum burada çalışamaz: $HelperWhy. WSL'i seçin ya da hiç WSL istemeyen iOS 16'yı kurun.") 2
    }
    if ($Linux -eq 'wsl' -and $Wsl.State -eq 'missing') {
        Write-Host ''
        Write-Host (L 'WSL is not installed. Installing WSL needs an administrator and a restart of Windows.' 'WSL kurulu değil. WSL''i kurmak yönetici izni ve Windows''u yeniden başlatmayı gerektirir.') -ForegroundColor Yellow
        if ($Saved -and "$($Saved.Stage)" -eq 'wsl-install') {
            Write-Host (L 'It was installed from here before: if Windows has not been restarted since, restart it and run this again.' 'Daha önce buradan kuruldu: Windows o zamandan beri yeniden başlatılmadıysa yeniden başlatıp bunu tekrar çalıştırın.') -ForegroundColor Yellow
        }
        $default = if ($IfNoWsl -eq 'nowsl') { 1 } else { 0 }
        $i = Ask (L 'What now?' 'Ne yapılsın?') @(
            @((L 'Install WSL now' 'WSL''i şimdi kur'), (L 'Windows asks for administrator approval; then restart and run this installer again: it goes on where it stopped' 'Windows yönetici onayı ister; sonra yeniden başlatıp bu kurucuyu tekrar çalıştırın: kaldığı yerden devam eder'), $false),
            @((L 'Continue without WSL' 'WSL''siz devam et'), $helperNote, (-not $Helper))) $default
        if ($i -eq 1) {
            if (-not $Helper) {
                Fail (L "The install without WSL cannot run here: $HelperWhy. Install WSL, or choose iOS 16, which never needs WSL." `
                        "WSL'siz kurulum burada çalışamaz: $HelperWhy. WSL'i kurun ya da hiç WSL istemeyen iOS 16'yı seçin.") 2
            }
            $Linux = 'helper'
        } else {
            Write-Host '  > wsl.exe --install --no-distribution   (as administrator)' -ForegroundColor DarkGray
            if ($ReadOnly) {
                Write-Host (L '  (nothing is run in this mode)' '  (bu kipte hiçbir şey çalıştırılmaz)') -ForegroundColor DarkGray
            } else {
                Save-State (@{ Version = $Version; Watch = $(if ($WantWatch) { 'yes' } else { 'no' }); Linux = 'wsl'; Dir = $Dir; Lang = $Lang; Stage = 'wsl-install'; Started = (Get-Date).ToString('s') } + (Watch-Sources $wq.Dir))
                try {
                    $p = Start-Process -FilePath 'wsl.exe' -ArgumentList '--install', '--no-distribution' -Verb RunAs -Wait -PassThru
                    $code = $p.ExitCode
                } catch {
                    Fail ((L 'WSL was not installed: the administrator approval was not given.' 'WSL kurulmadı: yönetici onayı verilmedi.') + " ($($_.Exception.Message))") 2
                }
                if ($code -ne 0 -and $code -ne 3010) { Fail ((L "wsl --install ended with $code." "wsl --install $code ile bitti.") + ' ' + (L 'Run it in an administrator PowerShell to see why: wsl --install --no-distribution' 'Nedenini görmek için yönetici PowerShell''de çalıştırın: wsl --install --no-distribution')) }
                Write-Host ''
                Write-Host (L 'WSL is installed. Restart Windows, then run Install-ASoftware.cmd again (or the same one-liner): it goes on where it stopped.' 'WSL kuruldu. Windows''u yeniden başlatın, sonra Install-ASoftware.cmd''yi (ya da aynı tek satırı) yeniden çalıştırın: kaldığı yerden devam eder.') -ForegroundColor Green
                exit 3010
            }
        }
    }
}

# --- 3. The install folder ---------------------------------------------------------------------
if (-not $Dir) { $Dir = Default-Dir }
$Dir = [IO.Path]::GetFullPath($Dir).TrimEnd('\')
$Work = Join-Path $Dir 'work'
if ($Want26 -and $Work -cnotmatch '^[A-Za-z]:\\[^\s''"`$;&|<>()]+$') {
    Fail ((L "iOS 26's build needs an install folder on a drive letter, without spaces or shell characters: $Dir. Give another with -Dir (say D:\ASoftware)." `
             "iOS 26 kurulumu sürücü harfli, boşluk ve kabuk karakteri içermeyen bir klasör ister: $Dir. -Dir ile başka birini verin (örneğin D:\ASoftware).")) 2
}
$QemuThere = Test-Path (Join-Path $Work 'qemu\qemu-system-aarch64.exe')
# watchOS's QEMU: -WatchQemu, else -QemuDist (the package's qemu\bin) when it is a watch build, else what
# work\qemu-watch has, else the watch installer's pinned package (none is published yet)
# (again now the work folder is known: its qemu-watch\ counts too)
$WatchQemuDir = $null
$WatchQemuThere = $false
$WatchQemuWhy = ''
if ($WantWatch) {
    $wq = Watch-Qemu $Work
    $WatchQemuDir = $wq.Dir; $WatchQemuThere = $wq.There; $WatchQemuWhy = $wq.Why
}

# --- 4. What it costs --------------------------------------------------------------------------
$bps = 0
$bwNote = ''
if ($Mbps -gt 0) { $bps = $Mbps * 1e6 / 8; $bwNote = L "$Mbps Mbit/s (-Mbps)" "$Mbps Mbit/s (-Mbps)" }
elseif (-not $NoProbe -and -not $List -and -not $Check) {
    $probeUrl = if ($Want26 -and -not $IPhoneIpsw) { $T26.IPhoneUrl } else { $T16.ipswUrl }
    Write-Host (L "  measuring the bandwidth to Apple's CDN (10 MB)..." "  Apple'ın CDN'ine bant genişliği ölçülüyor (10 MB)...") -ForegroundColor DarkGray
    $b = Probe-Bandwidth $probeUrl
    if ($b) { $bps = $b; $bwNote = '{0:N0} Mbit/s ({1})' -f ($b * 8 / 1e6), (L "10 MB from Apple's CDN" "Apple CDN'inden 10 MB") }
}
if (-not $bps) { $bps = 50e6 / 8; $bwNote = L '50 Mbit/s assumed (no measurement)' '50 Mbit/s varsayıldı (ölçülmedi)' }
# the build's distro (Install-iOS26.ps1: its config's Distro, else ios-emu) there already
$Distro26 = 'ios-emu'
$Cfg26File = if ($Ios26Config) { [IO.Path]::GetFullPath($Ios26Config) } else { Join-Path $env:LOCALAPPDATA 'ASoftware iOS 26\ios26.config.json' }
if (Test-Path $Cfg26File) { try { $d = (Get-Content $Cfg26File -Raw | ConvertFrom-Json).Distro; if ($d) { $Distro26 = "$d" } } catch { } }
# none: the wsl step makes it; bare: it is there but the wsl step still sets it up (apt, the hfsplus
# module); set: it has the module (wsl-setup.sh's KO path)
$wslState = 'none'
if ($Want26 -and $Wsl -and $Wsl.State -eq 'ok' -and $Wsl.Distros.ContainsKey($Distro26)) {
    $wslState = 'bare'
    try {
        $null = & wsl.exe -d $Distro26 -u root --exec sh -c 'ls /root/work/wsl-kernel/*/fs/hfsplus/hfsplus.ko >/dev/null 2>&1'
        if ($LASTEXITCODE -eq 0) { $wslState = 'set' }
    } catch { }
}
$Plans = [ordered]@{}
if ($Want16) { $Plans['ios16'] = @(Plan-16 $QemuThere) }
if ($Want26) {
    $shared = $Want16 -or $QemuThere
    $Plans['ios26-wsl'] = @(Plan-26 'wsl' $shared $wslState)
    $Plans['ios26-helper'] = @(Plan-26 'helper' $shared 'none')
}
if ($WantWatch) { $Plans['watch'] = @(Plan-Watch) }
function Row-Name([string]$k) {
    switch ($k) { 'watch' { 'watchOS 27.2' } 'ios16' { 'iOS 16' } 'ios26-wsl' { L 'iOS 26, fast install (WSL)' 'iOS 26, hızlı kurulum (WSL)' } 'ios26-helper' { L 'iOS 26, without WSL' 'iOS 26, WSL''siz' } }
}
Write-Host ''
Write-Host ((L 'What it takes on this PC' 'Bu PC''de ne gerektirir') + " ($bwNote; " + (L "times measured on $Ref, scaled to this PC's $($Pc.Cores) logical processors" "süreler $Ref üzerinde ölçüldü, $($Pc.Cores) mantıksal işlemciye göre ölçeklendi") + '):') -ForegroundColor White
Write-Host ('  {0,-30} {1,10} {2,22} {3,16}' -f '', (L 'Download' 'İndirme'), (L 'Disk: peak / after' 'Disk: en çok / sonra'), (L 'Time' 'Süre'))
$sums = @{}
foreach ($k in $Plans.Keys) {
    $s = Sum-Plan $Plans[$k] $bps
    $sums[$k] = $s
    $note = ''
    if ($k -eq 'ios26-helper' -and -not $Helper) { Write-Host ('  {0,-30} {1}' -f (Row-Name $k), $HelperWhy) -ForegroundColor DarkGray; continue }
    $chosen = ($k -eq 'ios16') -or ($k -eq "ios26-$Linux") -or ($k -eq 'watch')
    Write-Host ('  {0,-30} {1,10} {2,22} {3,16}{4}' -f (Row-Name $k), (Fmt-Size $s.Dl), ('{0} / {1}' -f (Fmt-Size $s.Peak), (Fmt-Size $s.After)), ('~' + (Fmt-Time $s.S)), $note) -ForegroundColor $(if ($chosen) { 'Gray' } else { 'DarkGray' })
}
# the choice as a whole: iOS 16 first, then iOS 26 on what iOS 16 left
$Chosen = @()
if ($Want16) { $Chosen += $Plans['ios16'] }
if ($Want26) { $Chosen += $Plans["ios26-$Linux"] }
if ($WantWatch) { $Chosen += $Plans['watch'] }
$Total = Sum-Plan $Chosen $bps
$freeB = Free-Bytes $Dir
Write-Host ''
Write-Host ('  {0}: {1}, {2} {3}, {4} {5} / {6}, ~{7}' -f (L 'Your choice' 'Seçiminiz'), "$(Version-Name $Version)$(if ($WantWatch) { ' + watchOS' })$(if ($Want26) { ' (' + (Linux-Name $Linux) + ')' })",
    (L 'download' 'indirme'), (Fmt-Size $Total.Dl), (L 'disk' 'disk'), (Fmt-Size $Total.Peak), (Fmt-Size $Total.After), (Fmt-Time $Total.S)) -ForegroundColor White
Write-Host ('  {0}: {1}   ({2} {3} {4})' -f (L 'Folder' 'Klasör'), $Dir, (Fmt-Size $freeB), (L 'free on' 'boş:'), ([IO.Path]::GetPathRoot($Dir))) -ForegroundColor White
if ($Want26 -and $Linux -eq 'wsl' -and $wslState -eq 'bare') {
    Write-Host ('  ' + (L "The build distro ($Distro26) is set up in the wsl step (apt packages, the hfsplus module): $(Fmt-Size ($WslFresh.Bytes - $WslFresh.Distro)) of it is in the download above, and it grows by about $($WslFresh.SysGB - 1) GB" "Derleme distrosu ($Distro26) wsl adımında hazırlanır (apt paketleri, hfsplus modülü): $(Fmt-Size ($WslFresh.Bytes - $WslFresh.Distro))'ı yukarıdaki indirmede, yaklaşık $($WslFresh.SysGB - 1) GB büyür")) -ForegroundColor DarkGray
}
if ($Want26 -and $Linux -eq 'wsl' -and $wslState -eq 'none') {
    $wslDrive = [IO.Path]::GetPathRoot($env:LOCALAPPDATA)
    Write-Host ('  ' + (L "The build distro ($Distro26) is made in the wsl step: $(Fmt-Size $WslFresh.Bytes) of it is in the download above, and it takes about $($WslFresh.SysGB) GB on $wslDrive (where WSL keeps its distros)" "Derleme distrosu ($Distro26) wsl adımında kurulur: $(Fmt-Size $WslFresh.Bytes)'ı yukarıdaki indirmede, $wslDrive üzerinde yaklaşık $($WslFresh.SysGB) GB yer tutar (WSL distrolarını orada tutar)")) -ForegroundColor DarkGray
    if ((Free-Bytes $wslDrive) -lt ($WslFresh.SysGB + 1) * 1e9) { $roomWarn = L "$wslDrive has $(Fmt-Size (Free-Bytes $wslDrive)) free: the build distro wants about $($WslFresh.SysGB) GB there" "$wslDrive üzerinde $(Fmt-Size (Free-Bytes $wslDrive)) boş: derleme distrosu orada yaklaşık $($WslFresh.SysGB) GB ister" }
}
$doneN = @($Chosen | Where-Object { $_.Done }).Count
if ($doneN) {
    Write-Host ('  ' + (L "$doneN of $($Chosen.Count) steps were finished by an earlier run: the download and time are for the rest" "$($Chosen.Count) adımın $doneN tanesi önceki çalıştırmada bitti: indirme ve süre kalanlar için")) -ForegroundColor DarkGray
}
$short = $freeB -lt $Total.Need + 1e9
if ($short) {
    $room = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady -and $_.AvailableFreeSpace -ge $Total.Need + 1e9 } | ForEach-Object Name)
    Write-Host ('  ' + (L "Not enough room on $([IO.Path]::GetPathRoot($Dir)): about $(Fmt-Size ($Total.Need + 1e9)) is needed at the peak." "$([IO.Path]::GetPathRoot($Dir)) üzerinde yer yetmiyor: en çok anında yaklaşık $(Fmt-Size ($Total.Need + 1e9)) gerekir.") +
        $(if ($room) { ' ' + (L "Drives with room: $($room -join ', ') (-Dir)." "Yeri olan sürücüler: $($room -join ', ') (-Dir).") } else { ' ' + (L 'Free some space first, or use an external drive (-Dir).' 'Önce yer açın ya da harici bir sürücü kullanın (-Dir).') })) -ForegroundColor Yellow
}
if ($Estimate -or $DryRun) {
    foreach ($k in @($Plans.Keys | Where-Object { $_ -eq 'ios16' -or $_ -eq "ios26-$Linux" -or $_ -eq 'watch' })) {
        Write-Host ''
        Write-Host ('  ' + (Row-Name $k) + ':') -ForegroundColor White
        $n = 0
        foreach ($st in $Plans[$k]) {
            $n++
            Write-Host ('    {0,2} {1,-12} {2,9} {3,10}  {4}' -f $n, $st.Id, $(if ($st.Dl -and -not $st.Done) { Fmt-Size $st.Dl } else { '' }), $(if ($st.Done) { L 'done' 'bitti' } else { Fmt-Time (Step-Seconds $st $bps) }), $st.Title) -ForegroundColor DarkGray
        }
    }
}
if ($Estimate) { exit 0 }

# --- 5. Preflight ------------------------------------------------------------------------------
$warn = @()
if ($roomWarn) { $warn += $roomWarn }
$stop = @()
if (-not $Pc.X64) { $stop += L 'a 64-bit Windows' '64 bit Windows' }
if ($Want16 -and $Pc.Build -lt 18362) { $stop += L 'Windows 10 1903 (build 18362) or later for iOS 16' 'iOS 16 için Windows 10 1903 (yapı 18362) ya da sonrası' }
if ($WantWatch -and $Linux -eq 'helper') {
    if ($Wsl -and $Wsl.State -eq 'novirt') {
        $stop += L 'WSL 2 for watchOS, which cannot start here (virtualization is off in the firmware): turn on Intel VT-x or AMD-V (SVM) in the BIOS/UEFI setup, or no watchOS (-Watch no)' 'watchOS için WSL 2; burada çalışamaz (sanallaştırma BIOS/UEFI''de kapalı): BIOS/UEFI ayarlarından Intel VT-x ya da AMD-V''yi (SVM) açın ya da watchOS''u kurmayın (-Watch no)'
    } else {
        $stop += L 'WSL for watchOS (its installer has no install without WSL yet): choose WSL, or no watchOS' 'watchOS için WSL (onun kurucusunda WSL''siz kurulum henüz yok): WSL''i seçin ya da watchOS''u kurmayın'
    }
}
if ($WatchQemuWhy) { $stop += $WatchQemuWhy }
if ($WantWatch -and $WatchIpsw -and -not (Test-Path -LiteralPath $WatchIpsw -PathType Leaf)) {
    $stop += L "-WatchIpsw $WatchIpsw`: no such file" "-WatchIpsw $WatchIpsw`: böyle bir dosya yok"
}
# the watch face needs iOS 26's GPU driver (Metal): a GPU-less iOS 26 would stop watchOS's check step,
# after the whole iOS 26 build
if ($WantWatch) {
    $gm = ''
    if (Test-Path $Cfg26File) { try { $gm = "$((Get-Content $Cfg26File -Raw | ConvertFrom-Json).GpuMode)" } catch { } }
    if ($gm -ceq 'gpuless' -and -not (Test-Path (Join-Path $Work 'gpu-driver\AppleParavirtGPUMetalIOGPUFamily.bundle'))) {
        $stop += L "a GPU driver for iOS 26, which watchOS needs (iOS 26's settings say GPU-less): choose one in ios26\Start-iOS26.cmd's menu ([G]), or -Watch no" "watchOS'un ihtiyaç duyduğu iOS 26 GPU sürücüsü (iOS 26 ayarı GPU'suz diyor): ios26\Start-iOS26.cmd menüsünden ([G]) birini seçin ya da -Watch no"
    } elseif (-not $gm -and -not $Yes) {
        $warn += L "watchOS needs iOS 26's GPU driver: when iOS 26's setup asks for one, do not choose None" "watchOS, iOS 26'nın GPU sürücüsünü ister: iOS 26 kurulumu sorduğunda Yok'u seçmeyin"
    }
}
if ($Want26 -and $Linux -eq 'wsl' -and $Pc.Build -lt 19041) { $stop += L 'Windows 10 2004 (build 19041) or later for WSL 2' 'WSL 2 için Windows 10 2004 (yapı 19041) ya da sonrası' }
if ($Want26 -and -not $Pc.VkLoader) { $stop += L "a Vulkan driver for iOS 26 (vulkan-1.dll; your GPU vendor's driver)" "iOS 26 için Vulkan sürücüsü (vulkan-1.dll; GPU üreticinizin sürücüsü)" }
elseif ($Want26 -and -not $Pc.VkDrivers) { $warn += L 'no Vulkan driver found in the registry (the loader is there); iOS 26 draws on the GPU through Vulkan' 'kayıt defterinde Vulkan sürücüsü bulunamadı (yükleyici var); iOS 26 GPU''da Vulkan ile çizer' }
if ($Pc.Ram -lt 16) { $warn += L "$($Pc.Ram) GB of RAM: 16 GB is what we ask for" "$($Pc.Ram) GB RAM: istenen 16 GB" }
if ($Want26 -and $Pc.Cores -lt 8) { $warn += L "$($Pc.Cores) logical processors: iOS 26 asks for 8 or more" "$($Pc.Cores) mantıksal işlemci: iOS 26 8 ya da fazlasını ister" }
elseif ($Pc.Cores -lt 4) { $warn += L "$($Pc.Cores) logical processors: iOS 16 asks for 4 or more" "$($Pc.Cores) mantıksal işlemci: iOS 16 4 ya da fazlasını ister" }
foreach ($t in 'curl.exe', 'tar.exe', 'robocopy.exe') { if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { $stop += "$t (Windows 10 1803+)" } }
if ($Want26) {
    Write-Host ('  GPU: {0}; Vulkan: {1}' -f ($Pc.Gpus -join ', '), $(if ($Pc.VkLoader -and $Pc.VkDrivers) { L 'yes' 'var' } elseif ($Pc.VkLoader) { L 'loader only' 'yalnız yükleyici' } else { L 'no' 'yok' })) -ForegroundColor DarkGray
    Write-Host ('  WSL: {0}{1}' -f $Wsl.State, $(if ($Wsl.Why) { " ($($Wsl.Why))" })) -ForegroundColor DarkGray
}
foreach ($w in $warn) { Write-Host "  ! $w" -ForegroundColor Yellow }
if ($stop) {
    $why = (L 'This PC needs: ' 'Bu PC''de gerekenler: ') + ($stop -join '; ')
    if (-not $ReadOnly) { Fail $why }
    Write-Host "  ($(L 'a real run stops here' 'gerçek çalıştırma burada durur')) $why" -ForegroundColor Yellow
}

# --- The two installers' arguments -------------------------------------------------------------
# a real run uses the copies in the install folder (the shortcuts point there); the read-only
# modes the ones next to this script
$runFrom = if ($ReadOnly) { $src } else { $Dir }
$Args16 = @('-Dir', $Dir)
if ($Ipsw) { $Args16 += '-Ipsw', [IO.Path]::GetFullPath($Ipsw) }
if ($KeepIpsw) { $Args16 += '-KeepIpsw' }
if ($QemuDist) { $Args16 += '-QemuDist', [IO.Path]::GetFullPath($QemuDist) }
if ($Cpus) { $Args16 += '-Cpus', "$Cpus" }
if ($NoShortcut) { $Args16 += '-NoShortcut' }
$Args26 = @('-Work', $Work)
if ($Has26Linux) { $Args26 += '-Linux', $Linux }
# our QEMU: the folder iOS 16 copied it from, else the package the app step left in work\downloads
if ($QemuDist) { $Args26 += '-QemuFrom', [IO.Path]::GetFullPath($QemuDist) }
if ($CloudOsIpsw) { $Args26 += '-CloudOsIpsw', [IO.Path]::GetFullPath($CloudOsIpsw) }
if ($IPhoneIpsw) { $Args26 += '-IPhoneIpsw', [IO.Path]::GetFullPath($IPhoneIpsw) }
if ($GpuPlugin) { $Args26 += '-GpuPlugin', [IO.Path]::GetFullPath($GpuPlugin) }
if ($Collections) { $Args26 += '-Collections' }
if ($KeepBuildFiles) { $Args26 += '-KeepBuildFiles' }
if ($BakeMinutes) { $Args26 += '-BakeMinutes', "$BakeMinutes" }
if ($Ios26Config) { $Args26 += '-Config', [IO.Path]::GetFullPath($Ios26Config) }
if ($NoShortcut) { $Args26 += '-NoShortcut' }
$ArgsW = @('-Work', $Work)
if ($Ios26Config) { $ArgsW += '-Config', [IO.Path]::GetFullPath($Ios26Config) }
if ($WatchIpsw) { $ArgsW += '-WatchIpsw', [IO.Path]::GetFullPath($WatchIpsw) }
if ($WatchDirs) { $ArgsW += '-WatchDir', (@($WatchDirs | ForEach-Object { [IO.Path]::GetFullPath($_) }) -join '|') }
# (iOS's QEMU, -QemuDist, only when it is a watch build: else the watch installer keeps work\qemu-watch)
if ($WatchQemuDir) { $ArgsW += '-QemuFrom', $WatchQemuDir }
if ($KeepBuildFiles) { $ArgsW += '-KeepBuildFiles' }
if ($NoShortcut) { $ArgsW += '-NoShortcut' }
if (-not $Has26Linux -and $Want26 -and $Linux -eq 'helper') {
    Write-Host ('  ' + (L '(-Pretend helper: Install-iOS26.ps1 has no -Linux yet, so it runs as it is)' '(-Pretend helper: Install-iOS26.ps1''de henüz -Linux yok, olduğu gibi çalışır)')) -ForegroundColor Yellow
}

if ($List -or $Check) {
    $mode = if ($List) { '-List' } else { '-Check' }
    $rc = 0
    if ($Want16) { Write-Host ''; Write-Host "== iOS 16 ($mode)" -ForegroundColor Cyan; $rc = [Math]::Max($rc, (Run-Installer (Join-Path $runFrom 'installer\Install-ASoftware.ps1') ($Args16 + $mode))) }
    if ($Want26) { Write-Host ''; Write-Host "== iOS 26 ($mode)" -ForegroundColor Cyan; $rc = [Math]::Max($rc, (Run-Installer (Join-Path $runFrom 'ios26\Install-iOS26.ps1') ($Args26 + $mode))) }
    # (Install-watchOS.ps1 lists its steps for both)
    if ($WantWatch) { Write-Host ''; Write-Host '== watchOS (-List)' -ForegroundColor Cyan; $rc = [Math]::Max($rc, (Run-Installer (Join-Path $runFrom 'watchos\Install-watchOS.ps1') ($ArgsW + '-List'))) }
    exit $rc
}

# --- 6. Go -------------------------------------------------------------------------------------
if (-not $DryRun -and -not $Yes -and -not [Console]::IsInputRedirected) {
    Write-Host ''
    $a = (Read-Host (L 'Start? [Y/n]' 'Başlasın mı? [E/h]')).Trim()
    if ($a -match '^(n|no|h|hayir)$') { Write-Host (L 'Nothing was started.' 'Hiçbir şey başlatılmadı.'); exit 0 }
}
if ($short -and -not $DryRun) {
    Write-Host (L '  The installers check the room before each step and stop where there is not enough; free some space and run this again to go on.' '  Kurucular her adımdan önce yere bakar, yetmezse orada durur; yer açıp bunu yeniden çalıştırınca devam eder.') -ForegroundColor Yellow
}
$t0 = Get-Date
$started = if ($resumed -and $Saved.Started) { "$($Saved.Started)" } else { $t0.ToString('s') }
Save-State (@{ Version = $Version; Watch = $(if ($WantWatch) { 'yes' } else { 'no' }); Linux = $(if ($Want26) { $Linux } else { '' }); Dir = $Dir; Lang = $Lang; Stage = 'running'; Started = $started } + (Watch-Sources $WatchQemuDir))
# iOS 26's setup asks where its GPU driver comes from; -Yes answers it as its default does
if ($Want26 -and $Yes -and -not $DryRun) {
    $cfgFile = $Cfg26File
    $cfg = [ordered]@{}
    if (Test-Path $cfgFile) { try { foreach ($p in (Get-Content $cfgFile -Raw | ConvertFrom-Json).PSObject.Properties) { $cfg[$p.Name] = $p.Value } } catch { } }
    if (-not $cfg['GpuMode']) {
        $cfg['GpuMode'] = 'cloudos'
        New-Item -ItemType Directory -Force (Split-Path $cfgFile) | Out-Null
        ($cfg | ConvertTo-Json) | Set-Content -Encoding UTF8 $cfgFile
        Write-Host ('  ' + (L "iOS 26's GPU driver: Apple's, out of the cloudOS IPSW (-Yes; the menu's [G] changes it)" "iOS 26 GPU sürücüsü: Apple'ınki, cloudOS IPSW'sinden (-Yes; menüdeki [G] değiştirir)")) -ForegroundColor DarkGray
    }
}

# The window title while the installers run: the step, the time so far and the time left, from
# what they leave in the work folder (work\install16.log; Install-iOS26.ps1's install\*.done)
$sync = [hashtable]::Synchronized(@{ Stop = $false; Phase = ''; PhaseStart = $t0; MinFree = [double]::MaxValue; MaxDir = 0.0 })
$titlePlan = @($Chosen | ForEach-Object { @{ Ver = $_.Ver; Id = $_.Id; Est = $(if ($_.Done) { 0 } else { Step-Seconds $_ $bps }) } })
# (not $watch: PowerShell's names ignore case, and -Watch is a [string] parameter)
$titler = [powershell]::Create()
[void]$titler.AddScript({
    param($sync, $plan, $work, $drive, $t0, $tr, $always, $dir)
    function T([double]$s) {
        $m = [Math]::Max(0, [Math]::Round($s / 60)); $h = [Math]::Floor($m / 60); $m -= 60 * $h
        if ($tr) { if ($h) { "$h sa $m dk" } else { "$m dk" } } else { if ($h) { "$h h $m min" } else { "$m min" } }
    }
    # the install folder's size; a file being written lists its old length, so big ones go by a handle
    function Dir-Bytes {
        $sum = 0.0
        foreach ($f in @(Get-ChildItem $dir -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            $n = $f.Length
            if ($n -gt 64MB) { try { $s = [IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite, Delete'); $n = $s.Length; $s.Close() } catch { } }
            $sum += $n
        }
        $sum
    }
    $tick = 0
    while (-not $sync.Stop) {
        try {
            $free = ([IO.DriveInfo]::new($drive)).AvailableFreeSpace
            if ($free -lt $sync.MinFree) { $sync.MinFree = [double]$free }
            if ($tick++ % 6 -eq 0) { $b = Dir-Bytes; if ($b -gt $sync.MaxDir) { $sync.MaxDir = $b } }
            $ver = $sync.Phase
            if ($ver) {
                $idx = -1; $since = $sync.PhaseStart
                if ($ver -eq 'ios16') {
                    $last = Get-Content (Join-Path $work 'install16.log') -Tail 1 -ErrorAction SilentlyContinue
                    if ("$last" -match '^(\S+ \S+) (\d)/6 ') {
                        $at = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null)
                        if ($at -ge $sync.PhaseStart) { $n = [int]$Matches[2]; $since = $at
                            for ($i = 0; $i -lt $plan.Count; $i++) { if ($plan[$i].Ver -eq 'ios16') { $n--; if ($n -eq 0) { $idx = $i; break } } } }
                    }
                } else {
                    # the first step of iOS 26's (or watchOS's: install\watch-<id>.done) without a
                    # marker (the every-run ones have none)
                    $prev = $sync.PhaseStart
                    $pre = if ($ver -eq 'watch') { 'watch-' } else { '' }
                    for ($i = 0; $i -lt $plan.Count; $i++) {
                        if ($plan[$i].Ver -ne $ver -or $always -contains $plan[$i].Id) { continue }
                        $m = Join-Path $work "install\$pre$($plan[$i].Id).done"
                        if (Test-Path $m) { $w = (Get-Item $m).LastWriteTime; if ($w -gt $prev) { $prev = $w }; continue }
                        $idx = $i; $since = $prev; break
                    }
                    # all marked: the phase's last step (its every-run ones have no marker)
                    if ($idx -lt 0) {
                        for ($i = $plan.Count - 1; $i -ge 0; $i--) { if ($plan[$i].Ver -eq $ver) { $idx = $i; break } }
                        $since = $prev
                    }
                }
                if ($idx -ge 0) {
                    $in = ((Get-Date) - $since).TotalSeconds
                    $left = [Math]::Max($plan[$idx].Est - $in, 0.1 * $plan[$idx].Est)
                    for ($i = $idx + 1; $i -lt $plan.Count; $i++) { $left += $plan[$i].Est }
                    $name = switch ($plan[$idx].Ver) { 'ios16' { 'iOS 16' } 'watch' { 'watchOS' } default { 'iOS 26' } }
                    $el = T ((Get-Date) - $t0).TotalSeconds
                    [Console]::Title = if ($tr) { "ASoftware $name - adım $($idx + 1)/$($plan.Count) $($plan[$idx].Id) - $el geçti, ~$(T $left) kaldı" }
                                       else { "ASoftware $name - step $($idx + 1)/$($plan.Count) $($plan[$idx].Id) - $el elapsed, ~$(T $left) left" }
                }
            }
        } catch { }
        Start-Sleep -Seconds 5
    }
}).AddArgument($sync).AddArgument($titlePlan).AddArgument($Work).AddArgument([IO.Path]::GetPathRoot($Dir)).AddArgument($t0).AddArgument($Lang -eq 'tr').AddArgument(@('setup', 'prereq', 'check', 'cleanup', 'shortcut')).AddArgument($Dir)
$titlerRun = $null
if (-not $DryRun) { $titlerRun = $titler.BeginInvoke() }
$net0 = $null
try { $net0 = (Get-NetAdapterStatistics -ErrorAction Stop | Measure-Object ReceivedBytes -Sum).Sum } catch { }
$free0 = Free-Bytes $Dir

$results = [ordered]@{}
$rc = 0
try {
    # the app and our QEMU, once for both (the iOS 16 installer's step 1)
    if ($DryRun) {
        if ($Want26 -and -not $Want16) {
            Write-Host ''; Write-Host '== app (installer\Install-ASoftware.ps1 -AppOnly)' -ForegroundColor Cyan
            $rc = Run-Installer $Inst16 ($Args16 + '-AppOnly', '-KeepQemuZip', '-DryRun')
        }
    } else {
        Write-Host ''; Write-Host ('== ' + (L "The app and our QEMU -> $Dir" "Uygulama ve QEMU'muz -> $Dir")) -ForegroundColor Cyan
        $a = $Args16 + '-AppOnly'
        if ($Want26) { $a += '-KeepQemuZip' }
        $ts = Get-Date
        $rc = Run-Installer $Inst16 $a
        $results['app'] = @{ Code = $rc; Start = $ts; End = (Get-Date) }
        if ($rc) { throw (L 'copying the app failed' 'uygulama kopyalanamadı') }
    }
    foreach ($v in @('ios16', 'ios26', 'watch')) {
        if (($v -eq 'ios16' -and -not $Want16) -or ($v -eq 'ios26' -and -not $Want26) -or ($v -eq 'watch' -and -not $WantWatch)) { continue }
        $name = switch ($v) { 'ios16' { 'iOS 16' } 'ios26' { 'iOS 26' } 'watch' { 'watchOS' } }
        Write-Host ''
        Write-Host ("=== $name" + $(if ($v -eq 'ios26') { ' (' + (Linux-Name $Linux) + ')' }) + $(if ($DryRun) { ' -DryRun' })) -ForegroundColor Cyan
        $sync.PhaseStart = Get-Date; $sync.Phase = $v
        $ts = Get-Date
        if ($v -eq 'ios16') { $rc = Run-Installer (Join-Path $runFrom 'installer\Install-ASoftware.ps1') ($Args16 + $(if ($DryRun) { '-DryRun' } else { @() })) }
        elseif ($v -eq 'ios26') { $rc = Run-Installer (Join-Path $runFrom 'ios26\Install-iOS26.ps1') ($Args26 + $(if ($DryRun) { '-DryRun' } else { @() })) }
        else { $rc = Run-Installer (Join-Path $runFrom 'watchos\Install-watchOS.ps1') ($ArgsW + $(if ($DryRun) { '-DryRun' } else { @() })) }
        $results[$v] = @{ Code = $rc; Start = $ts; End = (Get-Date) }
        if ($rc) { break }
    }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    if (-not $rc) { $rc = 1 }
} finally {
    $sync.Stop = $true
    if ($titlerRun) { try { [void]$titler.EndInvoke($titlerRun) } catch { } }
    $titler.Dispose()
}
if ($DryRun) {
    Write-Host ''
    Write-Host (L 'Dry run: nothing was done.' 'Deneme: hiçbir şey yapılmadı.') -ForegroundColor Cyan
    exit $rc
}

# --- 7. What it took ---------------------------------------------------------------------------
$t1 = Get-Date
$lines = @()
$lines += (L 'ASoftware iOS setup' 'ASoftware iOS kurulumu') + " $(Version-Name $Version)$(if ($WantWatch) { ' + watchOS' })$(if ($Want26) { ' (' + (Linux-Name $Linux) + ')' }): $($t0.ToString('yyyy-MM-dd HH:mm')) - $($t1.ToString('HH:mm'))"
$lines += (L 'Time' 'Süre') + ": $(Fmt-Time ($t1 - $t0).TotalSeconds) (" + (L 'estimate' 'tahmin') + " $(Fmt-Time $Total.S))"
foreach ($v in $results.Keys) {
    $r = $results[$v]
    $name = switch ($v) { 'app' { L 'The app and our QEMU' "Uygulama ve QEMU'muz" } 'ios16' { 'iOS 16' } 'ios26' { 'iOS 26' } 'watch' { 'watchOS' } }
    $lines += "  $name`: $(Fmt-Time ($r.End - $r.Start).TotalSeconds)$(if ($r.Code) { ', ' + (L "stopped (exit $($r.Code))" "durdu (çıkış $($r.Code))") })"
    # per step: when each began (iOS 16: work\install16.log; iOS 26: the === lines of its step logs),
    # the first time in this run
    $marks = @()
    if ($v -eq 'ios16') {
        foreach ($l in @(Get-Content (Join-Path $Work 'install16.log') -ErrorAction SilentlyContinue)) {
            if ($l -match '^(\S+ \S+) (\d)/6 (.*)$') { $at = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null); if ($at -ge $r.Start) { $marks += @{ At = $at; N = [int]$Matches[2]; Id = $Plans['ios16'][[int]$Matches[2] - 1].Id } } }
        }
    } elseif ($v -eq 'ios26' -or $v -eq 'watch') {
        # watchOS's step logs are install\logs\watch-<id>.log, iOS 26's the others
        foreach ($f in @(Get-ChildItem (Join-Path $Work 'install\logs') -Filter '*.log' -ErrorAction SilentlyContinue | Where-Object { ($_.Name -like 'watch-*') -eq ($v -eq 'watch') })) {
            foreach ($m in @(Select-String -Path $f.FullName -Pattern '^=== (\S+ \S+) (\d+)/\d+ (\S+):' -ErrorAction SilentlyContinue)) {
                $at = [datetime]::ParseExact($m.Matches[0].Groups[1].Value, 'yyyy-MM-dd HH:mm:ss', $null)
                if ($at -ge $r.Start) { $marks += @{ At = $at; N = [int]$m.Matches[0].Groups[2].Value; Id = $m.Matches[0].Groups[3].Value } }
            }
        }
    }
    $seen = @{}
    $marks = @($marks | Sort-Object { $_.At }, { $_.N } | Where-Object { -not $seen.ContainsKey($_.Id) -and ($seen[$_.Id] = $true) })
    for ($i = 0; $i -lt $marks.Count; $i++) {
        $end = if ($i + 1 -lt $marks.Count) { $marks[$i + 1].At } else { $r.End }
        $lines += ('    {0,-12} {1,10}' -f $marks[$i].Id, (Fmt-Time ($end - $marks[$i].At).TotalSeconds))
    }
}
$used = 0
try { $used = (Get-ChildItem $Dir -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } catch { }
$lines += (L 'Disk' 'Disk') + ": $Dir " + (L 'holds' 'içinde') + " $(Fmt-Size $used); " + (L 'free on' 'boş:') + " $([IO.Path]::GetPathRoot($Dir)) $(Fmt-Size (Free-Bytes $Dir))"
if ($sync.MaxDir -gt 0) { $lines += '  ' + (L 'most in the folder at once' 'klasörde aynı anda en çok') + ": $(Fmt-Size $sync.MaxDir) (" + (L 'looked at every 30 s' '30 sn''de bir bakıldı') + ')' }
if ($sync.MinFree -lt [double]::MaxValue) { $lines += '  ' + (L 'most taken at once' 'aynı anda en çok') + ": $(Fmt-Size ($free0 - $sync.MinFree)) (" + (L 'free space went down to' 'boş yer şu kadara indi') + " $(Fmt-Size $sync.MinFree); " + (L 'the whole drive, other programs too' 'tüm sürücü, başka programlar da') + ')' }
if ($null -ne $net0) {
    try { $net1 = (Get-NetAdapterStatistics -ErrorAction Stop | Measure-Object ReceivedBytes -Sum).Sum; $lines += (L 'Downloaded' 'İndirilen') + ": $(Fmt-Size ($net1 - $net0)) (" + (L 'the whole PC' 'tüm PC') + '; ' + (L 'planned' 'plan') + " $(Fmt-Size $Total.Dl))" } catch { }
}
$lines += (L 'Where' 'Nerede') + ':'
$lines += "  $Dir   (" + (L 'the app' 'uygulama') + '), ' + "$Work   (" + (L 'disks, downloads, runs' 'diskler, indirilenler, çalışmalar') + ')'
if ($Want16) { $lines += '  iOS 16: ' + (Join-Path $Dir 'Start-iOS.cmd') + $(if (-not $NoShortcut) { ' (' + (L 'desktop shortcut "ASoftware iOS"' 'masaüstü kısayolu "ASoftware iOS"') + ')' }) }
if ($Want26) { $lines += '  iOS 26: ' + (Join-Path $Dir 'ios26\Start-iOS26.cmd') + $(if (-not $NoShortcut) { ' (' + (L 'Start menu "ASoftware iOS 26"' 'Başlat menüsü "ASoftware iOS 26"') + ')' }) + '; ' + (L 'logs' 'loglar') + ': ' + (Join-Path $Work 'install\logs') }
if ($WantWatch) { $lines += '  watchOS: ' + (Join-Path $Dir 'Start-watchOS.cmd') + $(if (-not $NoShortcut) { ' (' + (L 'Start menu "ASoftware watchOS"' 'Başlat menüsü "ASoftware watchOS"') + ')' }) }
Write-Host ''
foreach ($l in $lines) { Write-Host $l }
try { Set-Content (Join-Path $Dir 'install-summary.txt') $lines -Encoding UTF8 } catch { }
if ($rc) {
    Save-State @{ Stage = 'failed' }
    Write-Host ''
    Write-Host (L 'The install stopped. Fix what the installer says above and run Install-ASoftware.cmd again: it goes on where it stopped.' 'Kurulum durdu. Kurucunun yukarıda söylediğini düzeltip Install-ASoftware.cmd''yi yeniden çalıştırın: kaldığı yerden devam eder.') -ForegroundColor Yellow
    exit $rc
}
Save-State @{ Stage = 'done' }
Write-Host ''
Write-Host (L 'Done.' 'Bitti.') -ForegroundColor Green
exit 0

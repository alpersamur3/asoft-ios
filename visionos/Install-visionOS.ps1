# ASoftware visionOS installer: visionOS 27.2 (24N120) as an Apple Vision Pro (RealityDevice14,1) on -M vresearch,
# built on this PC's iOS 26 install or only its base (Install-iOS26.ps1's work folder; its -Base is enough). From
# it: cloudOS 26.4b's research kernel (which kc-vision.py patches into visionOS's), SPTM, TXM, the device trees
# (dtree-smp4/8 and fw\dtree.orig, which dt-vision.py gives the Vision Pro's identity), the shell ramdisk,
# darwin-vm's sysroot, the guest GPU driver and the WSL distro. The scripts come with this installer
# (ios26\scripts, two of watchos\scripts and visionos\scripts, copied into work\visionos\scripts).
# From Apple it reads the visionOS IPSW's OS image where it is (over HTTP, about 10 GB of it, never stored whole),
# its trust cache and device tree, and the six synthetic rooms out of the visionOS 27.2 Simulator Runtime (a 7.65 GB
# download, deleted once the 266 MB of rooms are out). It needs our QEMU with visionOS's options in <work>\qemu, the
# one QEMU every guest runs on: the qemu step puts it there when the install's is older.
# Everything goes into <Work>\visionos (about 21 GB when done, which is also the peak: the runtime's 7.6 GB .dmg is
# deleted before the root is built), and leaves a marker per step in <Work>\install\vision-*.done, so running it
# again goes on where it stopped.
#
#   visionos\Install-visionOS.cmd [-Work D:\ios26] [-List] [-DryRun] [-From STEP | -Only STEP] ...
#     -QemuDir FOLDER     a QEMU package (win-build.sh's dist) to put in <work>\qemu when the one there lacks
#                         visionOS's options; else the release package asoft-setup.json names
#     -AudioPlugin FOLDER the virtio-snd HAL plug-in (VPhoneVirtIOSound.driver, or a folder with it, as the CI's
#                         artifact has it), checked by its pinned SHA-256s; else the release below; without one
#                         visionOS is installed silent only (no sound disk). Given (or published) after a silent
#                         install was finished, it adds the sound disk; the silent disk stays as it is
#     -CdnEdge IP         an Apple CDN edge (17.253.x.x) for the 7.65 GB runtime, where this network's DNS answer
#                         is slow; TLS still checks the host name
#     -KeepBuildFiles     keep the runtime's .dmg and the build's leftovers
# The Linux steps run in the iOS 26 install's WSL distro (its -Linux helper mode is not supported here).
# Redoing a disk step (-From/-Only rootfs ... disks) after a finished install keeps the user disks as
# visionos\vision.qcow2.old and vision-silent.qcow2.old (an earlier .old stays: .old2, .old3, ...): the new ones
# start afresh.
param(
    [string]$Work = '',
    [string]$Config = (Join-Path $env:LOCALAPPDATA 'ASoftware iOS 26\ios26.config.json'),
    [string]$QemuDir = '',
    [string]$AudioPlugin = '',
    [string]$CdnEdge = '',
    [string]$From = '',
    [string]$Only = '',
    [switch]$DryRun,
    [switch]$List,
    [switch]$KeepBuildFiles,
    [switch]$NoShortcut
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = Split-Path $here

# --- What it reads from Apple, pinned --------------------------------------------------------------
# Apple's visionOS 27.2 (24N120) restore IPSW for the Vision Pro (N301AP); only these members
$VisionUrl = 'https://updates.cdn-apple.com/2026FallFCS/47477bd7-2863-41db-97fa-7a371356228f/Apple_Vision_Pro_27.2_24N120_Restore.ipsw'
$OsMember = '141-17569-165.dmg.aea'   # the OS (AEA, 12.35 GB stored; its key from Apple's key service, read in place)
$OsDataOff = 222298234                # where its data starts in the IPSW
$OsHeadSha256 = '88a9005e4b006b247622e8d70a55820bb2633183aa47b70065b29774665c148c'   # its first MiB (for the key service)
$OsIdxSha256 = 'f0e2c2d0881a69ce69a01d541c5666ec3a57b168d6d19fc8da7be5689c29b0f7'    # aearemote.py's index of its 67 clusters
$VisionFiles = [ordered]@{            # member = bytes; into <Work>\visionos\ipsw, without the folder
    "Firmware/$OsMember.trustcache"              = 75577
    'Firmware/all_flash/DeviceTree.n301ap.im4p'  = 47079
}
# The visionOS 27.2 Simulator Runtime, through Apple's asset server (Pallas, no account): only its six synthetic
# rooms are kept. Its answer must name this archive (the size and path pin it)
$Runtime = @{ Type = 'com.apple.MobileAsset.xrOSSimulatorRuntime'; Audience = '02d8e57e-dd1c-4090-aa50-b4ed2aef0062'
              Build = '24N120'; Size = 7650410496
              Path = 'com_apple_MobileAsset_xrOSSimulatorRuntime/C6762BE2-7EC5-4CCC-8FE7-365F076EC469.aar' }
# The virtio-snd HAL plug-in: vphone-cli's VPhoneGuestComponents/VirtIOSound (MIT, cb23353e) with our 48 kHz
# speaker (d59f767), built for xrOS 26.0 and ad-hoc signed on macOS CI. Not published yet: -AudioPlugin <folder>
# until then. The release asset is a zip with VPhoneVirtIOSound.driver at its top.
$AudioPluginRelease = @{ Version = ''; Url = ''; Sha256 = '' }
$AudioFiles = [ordered]@{
    'VPhoneVirtIOSound'            = 'd5980d783a86822038759988dfe7bffaa341adcc8890f0c8742568b2a772c838'
    'Info.plist'                   = '73253dd18f4dcbde9c827f183efc90738d7fe18ea842482eb9a3f16cd3089285'
    '_CodeSignature/CodeResources' = '70262abbfd5a4f2794aa829fa7b9d3069bcb8e7d58768a1515cce4729f9c9fc5'
}
$AudioCdHash = '82e8d87863e48771eb23355c8da72809e537f9d7'
$GpuBundle = 'AppleParavirtGPUMetalIOGPUFamily.bundle'
# the kernel kc-vision.py starts from: the iOS 26 install's plain one, else decompressed again out of cloudos\
$KernelIn = @('cloud\kernelcache.research.vphone600.decompressed', 'fw\bootkc')
$KernelPacked = 'cloudos\kernelcache.research.vphone600'
# the device trees dt-vision.py makes from the base's (iOS 26 0.3.0's dtree-smp4/8, fw\dtree.orig): another base
# gives other bytes, which is said, not refused
$TreeSha = @{ 'dtree-v'  = 'ad5a377032c7744f745c6088a4263aef8c07149a68912dd4fd768df80e0de421'
              'dtree-v6' = '7d8c9e050f86a61248de74338259dafa0283ef97cbc8bdde472c5fdc9c29b3fd'
              'dtree-v8' = '53f45695cd063c70ece1dcdf7142e2745d4f52ffcd2444f3ff241812e931c186' }
# GB a step adds on the work folder's drive at most
$Space = @{ qemu = 0.6; rooms = 8.0; rootfs = 18.0; patches = 1.5; firstboot = 1.0; homeboot = 0.5; disks = 0.2 }

# --- Output, running tools (as Install-watchOS.ps1) --------------------------------------------------
function Step([string]$text) { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }
# Progress for ASoftware.exe, which sets ASOFT_PROGRESS=1: ##asoft|kind|field|..., one line each
# (step|vision|N|OF|ID|start|TITLE, step|...|done/skip/fail, pct|vision|ID|0-100|TEXT, paused|vision|ID, end|vision|CODE)
function Emit([object[]]$f) { if ($env:ASOFT_PROGRESS -ceq '1') { Write-Host ('##asoft|' + (@($f | ForEach-Object { "$_" -replace '[|\r\n]', ' ' }) -join '|')) } }
function Pause-Requested { [bool]($env:ASOFT_PAUSE_FILE -and (Test-Path -LiteralPath $env:ASOFT_PAUSE_FILE)) }
function Say([string]$text, [string]$color = 'Gray') { Write-Host "  $text" -ForegroundColor $color }
function Fail([string]$why) { throw $why }
function Q([string]$a) { if ($a -eq '' -or $a -cmatch '[\s"]') { '"' + $a + '"' } else { $a } }
function Show-Cmd([string]$text) { Write-Host "  > $text" -ForegroundColor DarkGray }
$script:Log = $null
$script:Code = 0
function Run([string]$exe, [string[]]$argv, [switch]$NoFail, [switch]$Quiet) {
    Show-Cmd ((@($exe) + $argv | ForEach-Object { Q $_ }) -join ' ')
    $script:Code = 0
    if ($DryRun) { return , @() }
    $lines = New-Object System.Collections.Generic.List[string]
    $w = if ($script:Log) { New-Object System.IO.StreamWriter($script:Log, $true) } else { $null }
    try {
        $ErrorActionPreference = 'Continue'
        & $exe @argv 2>&1 | ForEach-Object {
            $t = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
            $l = ("$t" -replace "`0", '').TrimEnd()
            $lines.Add($l)
            if ($w) { $w.WriteLine($l) }
            if (-not $Quiet) { Write-Host "    $l" }
        }
        $script:Code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = 'Stop'
        if ($w) { $w.Close() }
    }
    if ($script:Code -and -not $NoFail) { Fail "$([IO.Path]::GetFileName($exe)) exited with $($script:Code)" }
    return , $lines.ToArray()
}
# (the scripts the check step copies into visionos\scripts)
function Py([string]$script, [string[]]$argv, [switch]$NoFail) {
    Run $Py (@('-I', '-B', (In-Vision "scripts\$script")) + $argv) -NoFail:$NoFail
}
function To-Wsl([string]$p) {
    $f = [IO.Path]::GetFullPath($p)
    '/mnt/' + $f.Substring(0, 1).ToLowerInvariant() + ($f.Substring(2) -replace '\\', '/')
}
function In-Work([string]$rel) { Join-Path $Work $rel }
function In-Vision([string]$rel) { Join-Path (Join-Path $Work 'visionos') $rel }
function Free-GB { ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($Work))).AvailableFreeSpace / 1e9 }
function Need-Space([double]$gb) {
    if ($gb -le 0) { return }
    if ($DryRun) { Say ("needs about {0:N1} GB free on {1}" -f $gb, [IO.Path]::GetPathRoot($Work)) DarkGray; return }
    $free = Free-GB
    if ($free -lt $gb + 1) {
        Fail ("{0:N1} GB free on {1}; this step needs about {2:N0} GB: free some space" -f $free, [IO.Path]::GetPathRoot($Work), ($gb + 1))
    }
}

# A bash script for WSL, as Install-watchOS.ps1's (its prelude: the folders, disk_tools, in_root, overlay)
function Prelude([string]$name) {
    $p = @'
#!/bin/bash
# Install-visionOS.ps1, {NAME}: written by the installer, run as root in WSL ({DISTRO})
set -euo pipefail
export ASOFT26={A} ASOFT26_LINUX={L}
A=$ASOFT26 L=$ASOFT26_LINUX S=$ASOFT26/visionos/scripts W=$ASOFT26/visionos
export A L S W
KVER=$(uname -r)
export HFSPLUS_KO=/root/work/wsl-kernel/linux-msft-wsl-${KVER%%-*}/fs/hfsplus/hfsplus.ko
mkdir -p "$L"
cd "$A"
disk_tools() {
	modprobe nbd max_part=0 2> /dev/null || true
	if ! grep -q hfsplus /proc/filesystems; then
		if [ ! -f "$HFSPLUS_KO" ]; then
			echo "no hfsplus module for $KVER (WSL was updated?): run Install-iOS26.cmd -Only linux"
			exit 1
		fi
		insmod "$HFSPLUS_KO"
	fi
	local free=() n
	for n in 12 13 14 15; do
		if [ -b /dev/nbd$n ] && [ ! -s /sys/block/nbd$n/pid ]; then free+=(/dev/nbd$n); fi
	done
	if [ ${#free[@]} -lt 2 ]; then
		echo "fewer than two free nbd devices from /dev/nbd12: wsl --terminate {DISTRO} frees them"
		exit 1
	fi
	export NBD=${free[0]} NBD2=${free[1]}
}
in_root() {
	local f
	f=$(mktemp /tmp/asoft-in-root.XXXXXX)
	cat > "$f"
	bash "$S/root26-do.sh" "$A/$1" "set -euo pipefail; . $f"
	rm -f "${f:?}"
}
overlay() {
	local new=${A:?}/${2:?}
	rm -f "${new:?}"
	qemu-img create -q -f qcow2 -b "$1" -F qcow2 "$new"
	echo "$2: an overlay on $1"
}
'@
    $p.Replace('{NAME}', $name).Replace('{DISTRO}', $Distro).Replace('{A}', (To-Wsl $Work)).Replace('{L}', $LinuxDir)
}
# A Linux step's body: steps\NAME.sh beside this script, its {PLACEHOLDERS} filled by the caller. Read from this
# release's own folder, never from a work folder.
function Step-Body([string]$name) {
    $f = Join-Path $here "steps\$name.sh"
    if (-not (Test-Path $f)) { Fail "no $f (this installer comes with its steps folder)" }
    ([IO.File]::ReadAllText($f) -replace "`r`n", "`n").TrimEnd("`n")
}
function Run-Wsl([string]$name, [string]$body) {
    $file = In-Work "install\sh\vision-$name.sh"
    if ($DryRun) {
        Show-Cmd "wsl -d $Distro -u root -- bash $(To-Wsl $file)   (the prelude, then:)"
        foreach ($l in ($body.Trim() -split "`n")) { Write-Host ('      ' + $l.TrimEnd()) -ForegroundColor DarkGray }
        return , @()
    }
    New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
    $text = ((Prelude $name) + "`n" + $body.Trim() + "`n") -replace "`r`n", "`n"
    [IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding $false))
    $env:WSL_UTF8 = '1'
    Run 'wsl.exe' @('-d', $Distro, '-u', 'root', '--', 'bash', (To-Wsl $file))
}
# One IPSW member with ipsw-get.py: resumable, CRC-checked
function Get-IpswMember([string]$member, [string]$out, [long]$size) {
    $ok = In-Work ('install\got\vision-' + [IO.Path]::GetFileName($out) + '.ok')
    if (-not $DryRun -and (Test-Path $ok) -and (Test-Path $out) -and (-not $size -or (Get-Item $out).Length -eq $size)) {
        Say "have $member"
        return
    }
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force (Split-Path $out), (Split-Path $ok) | Out-Null
        Remove-Item $ok -ErrorAction SilentlyContinue
    }
    $null = Py 'ipsw-get.py' @($VisionUrl, $member, $out)
    if (-not $DryRun) {
        if ($size -and (Get-Item $out).Length -ne $size) { Fail "$out is $((Get-Item $out).Length) bytes, not $size" }
        Set-Content $ok $member
    }
}
function Sha256([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }

# --- Markers -----------------------------------------------------------------------------------
function Mark-File([string]$id) { In-Work "install\vision-$id.done" }
function Get-Mark([string]$id) { $f = Mark-File $id; if (Test-Path $f) { (Get-Content $f -Raw).Trim() } else { $null } }
function Set-Mark([string]$id, [string]$sig) { Set-Content -Path (Mark-File $id) -Value $sig -Encoding UTF8 }
function Clear-Mark([string]$id) { Remove-Item (Mark-File $id) -ErrorAction SilentlyContinue }
# the audio step's: whether there is a plug-in to install (so a plug-in given later redoes the disk chain from it,
# unless the install is finished: then the sound disk is added, see Sound-Later)
function Step-Sig([string]$id) { if ($id -ceq 'audio') { "audio $(Audio-State)" } else { 'done' } }

# --- The guest (the install's two boots) ---------------------------------------------------------
# A QMP command (its arguments a hashtable); -Quiet: neither the command nor a failure is printed
function Send-Qmp([string]$command, [hashtable]$arguments = $null, [switch]$Quiet) {
    $json = if ($arguments) { (@{ execute = $command; arguments = $arguments } | ConvertTo-Json -Compress -Depth 4) } else { "{`"execute`":`"$command`"}" }
    if (-not $Quiet) { Show-Cmd "QMP 127.0.0.1:4483 $json" }
    if ($DryRun) { return }
    try {
        $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4483)
        # (a QEMU that holds another QMP client, or hangs, must not stop the installer for good)
        $client.ReceiveTimeout = 15000; $client.SendTimeout = 15000
        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $writer = New-Object System.IO.StreamWriter($stream)
            $writer.AutoFlush = $true
            [void]$reader.ReadLine()
            $writer.WriteLine('{"execute":"qmp_capabilities"}'); [void]$reader.ReadLine()
            # (events can come before the answer)
            $writer.WriteLine($json)
            for ($n = 0; $n -lt 20; $n++) { $l = $reader.ReadLine(); if ($null -eq $l -or $l -cmatch '"(return|error)"') { break } }
        } finally { $client.Close() }
    } catch { if (-not $Quiet) { Say "QMP: $($_.Exception.Message)" Yellow } }
}
# The size of the guest's screen dumped by QMP as a PNG: a black or blank frame is a few KB, Home over a room
# well over 60 KB (the threshold the hand-run boots used)
function Screen-Bytes($g, [string]$name) {
    $png = Join-Path $g.Dir "$name.png"
    Remove-Item $png -ErrorAction SilentlyContinue
    Send-Qmp 'screendump' @{ filename = ($png -replace '\\', '/'); format = 'png' } -Quiet
    if (Test-Path $png) { (Get-Item $png).Length } else { 0 }
}
# A visionOS guest running (its fixed ports listening) holds the files a disk or QEMU step replaces
function Need-NoVision {
    if ($DryRun) { return }
    $busy = @(Get-NetTCPConnection -State Listen -LocalPort 4481, 4482, 4483 -ErrorAction SilentlyContinue)
    if ($busy) { Fail ("visionOS is running (ports 4481-4483, pid {0}): close it first; it uses the files this step replaces" -f (($busy | ForEach-Object OwningProcess | Sort-Object -Unique) -join ', ')) }
}
function Guest([int]$wait, [string[]]$cmds, [switch]$NoFail) {
    Py 'guest-shell.py' (@('4481', "$wait") + $cmds) -NoFail:$NoFail
}
# Start-visionOS.ps1 on the install's disk, 4 vCPUs (the tree of the hand-run first boot), silent, its own window
function Start-Vision([string]$name) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $here 'Start-visionOS.ps1'), '-Work', $Work,
           '-Name', $name, '-Disk', 'visionos\rootv-b.qcow2', '-Cpus', '4')
    Show-Cmd ('powershell ' + (($a | ForEach-Object { Q $_ }) -join ' '))
    if ($DryRun) { return @{ Pid = 0; Dir = (In-Vision "runs\$name"); Proc = $null } }
    # its own process with its output in a file: QEMU, which it starts and leaves running, must not hold a pipe
    # of ours open (as Install-iOS26.ps1's Start-Guest)
    $log = In-Work "install\logs\vision-launch-$name.txt"
    $p = Start-Process powershell.exe -ArgumentList ($a | ForEach-Object { Q $_ }) -NoNewWindow -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    $null = $p.Handle
    $p.WaitForExit()
    $out = @(Get-Content $log, "$log.err" -ErrorAction SilentlyContinue)
    foreach ($l in $out) { if ($l) { Write-Host "    $l" } }
    $line = $out | Where-Object { "$_" -cmatch '^started .* pid \d+ -> ' } | Select-Object -Last 1
    if (-not $line -or -not ("$line" -cmatch 'pid (\d+) -> (.+)$')) { Fail 'the launcher did not start QEMU (its output is above)' }
    $id = [int]$Matches[1]
    @{ Pid = $id; Dir = $Matches[2].Trim(); Proc = (Get-Process -Id $id -ErrorAction SilentlyContinue) }
}
function Guest-Alive($g) { $g.Proc -and -not $g.Proc.HasExited }
# sync (unless -NoSync), QMP quit, then up to 120 s for QEMU to end before it is stopped (by its PID); true when
# the guest answered sync
function Stop-Vision($g, [switch]$NoSync) {
    $synced = $false
    if (-not $NoSync) { $null = Guest 180 @('sync') -NoFail; $synced = ($script:Code -eq 0) }
    Send-Qmp 'quit'
    if (-not $DryRun -and $g.Proc -and -not $g.Proc.WaitForExit(120000)) {
        Say "QEMU (pid $($g.Pid)) did not quit: stopped" Yellow
        Stop-Process -Id $g.Pid -Force -ErrorAction SilentlyContinue
        $null = $g.Proc.WaitForExit(10000)
    }
    $synced
}

# --- The steps ---------------------------------------------------------------------------------
# A step's stop; a dry run only says it
function Stop-Here([string]$why) { if ($DryRun) { Say "(a real run stops here) $why" Yellow } else { Fail $why } }
# An iOS 26 step's marker (install\<id>.done: the step's signature), or $null
function Ios-Mark([string]$id) { $f = In-Work "install\$id.done"; if (Test-Path $f) { (Get-Content $f -Raw).Trim() } else { $null } }
# What an earlier step left (visionos\<rel>), else stop and say which step makes it
function Need-Input([string]$rel, [string]$step) {
    if (-not $DryRun -and -not (Test-Path (In-Vision $rel))) { Fail "no visionos\${rel}: the $step step makes it (run -From $step)" }
}
function Do-Check {
    # the iOS 26 install this builds on (its kernel: kc-vision.py --check below)
    $need = @('fw\sptm', 'fw\txm', 'fw\dtree.orig', 'dtree-smp4', 'rd-shell.hfs', 'downloads\ios_sysroot.tar.gz',
              'tools\qemu-sptm\scripts\darwin\vresearch_dt_fixup.py')
    $missing = @($need | Where-Object { -not (Test-Path (In-Work $_)) })
    if ($missing) {
        Stop-Here ("this has no iOS 26 base ($Work lacks $($missing -join ', ')): make it with Install-ASoftware.cmd -Version visionos " +
                   '(or install iOS 26), or give its folder with -Work')
    }
    $mode = Ios-Mark 'linux'
    if (-not $mode) { $mode = $LinuxMode }
    if ($mode -ceq 'helper') {
        Stop-Here 'the iOS 26 install ran its Linux steps in the helper VM; the visionOS installer needs WSL 2 (ios26\Install-iOS26.cmd -Linux wsl -Only linux sets it up)'
    }
    $env:WSL_UTF8 = '1'
    $distros = @()
    if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
        $ErrorActionPreference = 'Continue'
        $distros = @(& wsl.exe -l -q 2>$null | ForEach-Object { ("$_" -replace "`0", '').Trim() } | Where-Object { $_ })
        $ErrorActionPreference = 'Stop'
    }
    if ($distros -notcontains $Distro) {
        Stop-Here "WSL has no distro $Distro, where the iOS 26 install ran its Linux steps (WSL lists: $(if ($distros) { $distros -join ', ' } else { 'none' })): ios26\Install-iOS26.cmd -Linux wsl -Only linux makes it"
    }
    # the 3D compositor draws through Metal: the GPU driver iOS 26's gpu step leaves in gpu-driver\ (or on its disk)
    if (((Ios-Mark 'gpu') -ceq 'gpuless' -or (Ios-Mark 'gpudriver') -ceq 'gpuless') -and -not (Test-Path (In-Work "gpu-driver\$GpuBundle"))) {
        Stop-Here ('iOS 26 was installed GPU-less, and visionOS draws everything through its GPU driver (Metal): choose one in ' +
                   'ios26\Start-iOS26.cmd''s menu ([G]), run ios26\Install-iOS26.cmd again (it redoes its gpu step), then this')
    }
    Say "iOS 26 install: $Work; WSL distro $Distro, Linux scratch $LinuxDir"
    # the scripts visionOS's steps run, in visionos\scripts (WSL reads them there; bash wants LF): this version's
    # iOS 26 scripts (root26-do.sh, mktc.py, root26-prefs.py, ...), the watch's shared-cache tools, then visionOS's
    $dst = In-Vision 'scripts'
    $watch = Join-Path $repo 'watchos\scripts'
    $from = @((Join-Path $repo 'ios26\scripts'), $watch, (Join-Path $here 'scripts'))
    foreach ($d in $from) { if (-not (Test-Path $d)) { Stop-Here "no $d (this installer comes with ios26\, watchos\ and visionos\ beside each other)" } }
    Show-Cmd "copy ios26\scripts, watchos\scripts\{dscforce,dscfind}.py, visionos\scripts -> $dst (.sh and .sha256 with LF)"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force $dst, (In-Vision 'ipsw'), (In-Vision 'build'), (In-Work 'install\logs') | Out-Null
        $files = @(Get-ChildItem (Join-Path $repo 'ios26\scripts') -File) +
                 @('dscforce.py', 'dscfind.py' | ForEach-Object { Get-Item (Join-Path $watch $_) }) +
                 @(Get-ChildItem (Join-Path $here 'scripts') -File)
        foreach ($f in $files) {
            $to = Join-Path $dst $f.Name
            # (sha256sum -c wants LF lines too)
            if ($f.Extension -ceq '.sh' -or $f.Extension -ceq '.sha256') {
                $t = [IO.File]::ReadAllText($f.FullName) -replace "`r`n", "`n"
                [IO.File]::WriteAllText($to, $t, (New-Object System.Text.UTF8Encoding $false))
            } else { Copy-Item $f.FullName $to -Force }
        }
    }
    # the kernel the firmware step patches, before anything is downloaded
    if (-not (Get-Mark 'firmware') -or -not (Test-Path (In-Vision 'bootkc-v'))) {
        $null = Py 'kc-vision.py' (@('--check') + @($KernelIn | ForEach-Object { In-Work $_ })) -NoFail
        if ($script:Code) {
            if (-not (Test-Path (In-Work $KernelPacked))) {
                Stop-Here "the iOS 26 install has no plain cloudOS 26.4b research kernel (see above), nor $KernelPacked to decompress it from"
            }
            Say "the firmware step decompresses it again out of $KernelPacked"
        }
    }
    # what visionOS's Linux steps need beyond the base's tools (apt, once)
    $null = Run-Wsl 'tools' (Step-Body 'tools')
}

# The QEMU every guest of this install runs on, <work>\qemu, has what visionOS needs: walk mode with the held key
# (the keyboard camera) and the TLBI filter. The probes only read (a dry run makes them too): the device's help, and
# a machine-less start whose CPU options end it at once (the last option does not exist, so a QEMU that takes
# x-tlbi-filter stops there; one that does not names that one)
function Qemu-Probe([string]$exe, [string[]]$argv) {
    $psi = New-Object Diagnostics.ProcessStartInfo $exe
    $psi.Arguments = ($argv | ForEach-Object { Q $_ }) -join ' '
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $err = $p.StandardError.ReadToEndAsync(); $out = $p.StandardOutput.ReadToEndAsync()
    if (-not $p.WaitForExit(20000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; return '' }
    $out.Result + "`n" + $err.Result
}
function Qemu-HasVision([string]$dir) {
    # (Combine, not Join-Path, which throws on a drive that is not there)
    $exe = [IO.Path]::Combine($dir, 'qemu-system-aarch64.exe')
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $false }
    $walk = Qemu-Probe $exe @('-device', 'usb-touchscreen,help')
    if ($walk -cnotmatch '\bwalk-hold-key=') { return $false }
    $cpu = Qemu-Probe $exe @('-M', 'none', '-cpu', 'max,x-tlbi-filter=on,x-asoft-probe=on', '-display', 'none', '-S', '-nodefaults')
    ($cpu -cmatch 'x-asoft-probe') -and ($cpu -cnotmatch "x-tlbi-filter' not found")
}
# QEMUs started from <work>\qemu (any guest of this install): its files cannot be replaced under them
function Need-NoQemuFrom([string]$dir) {
    if ($DryRun) { return }
    $p = @(Get-Process -Name 'qemu-system-aarch64*' -ErrorAction SilentlyContinue | Where-Object {
            $_.Path -and $_.Path.StartsWith($dir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) })
    if ($p) { Fail ("QEMU runs from $dir (pid {0}: iOS 16, iOS 26, watchOS or visionOS): close it first, its files are replaced" -f (($p | ForEach-Object Id) -join ', ')) }
}
# the release package of the QEMU with visionOS's options, as asoft-setup.json names it (os.visionos.files.qemu)
function Qemu-Release {
    $r = @{ Version = ''; Url = ''; Sha256 = '' }
    $j = Join-Path $repo 'installer\asoft-setup.json'
    try {
        $q = (Get-Content $j -Raw | ConvertFrom-Json).os.visionos.files.qemu
        if ($q) { $r.Version = "$($q.version)"; $r.Url = "$($q.url)"; $r.Sha256 = "$($q.sha256)".ToUpperInvariant() }
    } catch { }
    $r
}
function Do-Qemu {
    $dst = In-Work 'qemu'
    if (Qemu-HasVision $dst) { Say "have $dst (walk-hold-key, x-tlbi-filter)$(if ($QemuDir) { ': -QemuDir is not needed' })"; return }
    Say "$dst lacks visionOS's options (usb-touchscreen walk-hold-key, -cpu x-tlbi-filter): it is replaced by a QEMU that has them, which runs iOS 16, iOS 26 and watchOS too" Yellow
    if ($QemuDir) {
        $src = [IO.Path]::GetFullPath($QemuDir).TrimEnd('\')
        # looked at before anything is copied
        if (-not (Qemu-HasVision $src)) {
            Stop-Here "$src has no qemu-system-aarch64.exe with visionOS's options (walk-hold-key, x-tlbi-filter): not the visionOS build (qemu-sptm asoft-vision, win-build.sh's dist)"
            return
        }
        if ($src -ieq $dst.TrimEnd('\')) { return }
        # a package folder, as every launcher wants it (iOS 26's starts qemu-system-aarch64w.exe), not a bare build tree
        foreach ($n in 'qemu-system-aarch64w.exe', 'qemu-img.exe') {
            if (-not (Test-Path -LiteralPath ([IO.Path]::Combine($src, $n)) -PathType Leaf)) {
                Stop-Here "$src has no $($n), so it is no package folder (win-build.sh's dist has it): not a build tree"
                return
            }
        }
        Need-Space $Space.qemu
        Need-NoQemuFrom $dst
        Show-Cmd "robocopy $src $dst /MIR /XD backup-* v11.1.2-asoft"
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force $dst | Out-Null
            # (/R /W: a file in use fails in seconds, not after robocopy's million retries)
            $null = Run 'robocopy.exe' @($src, $dst, '/MIR', '/XD', 'backup-*', 'v11.1.2-asoft', '/R:2', '/W:2', '/NFL', '/NDL', '/NJH', '/NJS', '/NP') -NoFail -Quiet
            if ($script:Code -ge 8) { Fail "robocopy $src -> $dst failed ($($script:Code)): is a QEMU from $dst running?" }
        }
    } else {
        $rel = Qemu-Release
        if (-not $rel.Url) {
            Stop-Here ('the QEMU with visionOS''s options is not published as a package yet (asoft-setup.json, os.visionos.files.qemu): ' +
                       'give a build with -QemuDir <folder> (qemu-sptm asoft-vision, win-build.sh''s dist)')
            return
        }
        Need-Space $Space.qemu
        $zip = In-Work "downloads\asoft-qemu-vision-$($rel.Version).zip"
        if (-not $DryRun) { New-Item -ItemType Directory -Force (Split-Path $zip) | Out-Null }
        $null = Run 'curl.exe' @('-fL', '--retry', '5', '-C', '-', '-o', $zip, $rel.Url)
        if (-not $DryRun -and (Get-FileHash $zip -Algorithm SHA256).Hash -ne $rel.Sha256) { Remove-Item $zip; Fail "${zip}: wrong SHA-256 (removed)" }
        Need-NoQemuFrom $dst
        Show-Cmd "unzip $zip -> $dst"
        if (-not $DryRun) {
            Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
            Expand-Archive $zip $dst -Force
            Set-Content (Join-Path $dst 'package.sha256') $rel.Sha256 -Encoding ASCII
        }
    }
    if (-not $DryRun -and -not (Qemu-HasVision $dst)) { Fail "$dst still lacks visionOS's options after the copy" }
    $build = Join-Path $dst 'BUILD.txt'
    if (-not $DryRun -and (Test-Path $build)) { foreach ($l in Get-Content $build) { Say $l } }
}
function Do-Rooms {
    $b = In-Vision 'build\rooms'
    # (a download that stopped has that much of the .dmg there already: rooms.sh goes on with it)
    $part = Join-Path $b 'rt.dmg'
    Need-Space ($Space.rooms - $(if (Test-Path $part) { (Get-Item $part).Length / 1e9 } else { 0 }))
    $asset = Join-Path $b 'asset.json'
    if (-not $DryRun) { New-Item -ItemType Directory -Force $b | Out-Null }
    # Apple's asset server: the runtime's URL and its archive key (the answer must name the pinned archive)
    $null = Py 'pallas.py' @($asset, '--type', $Runtime.Type, '--audience', $Runtime.Audience, '--build', $Runtime.Build,
                             '--size', "$($Runtime.Size)", '--path', $Runtime.Path)
    $url = 'https://updates.cdn-apple.com/.../' + $Runtime.Path
    if (-not $DryRun) {
        $a = Get-Content $asset -Raw | ConvertFrom-Json
        $url = "$($a.url)"
        [IO.File]::WriteAllText((Join-Path $b 'rt.key'), "$($a.ArchiveDecryptionKey)", (New-Object System.Text.ASCIIEncoding))
    }
    if ($CdnEdge) { Say "the runtime through the CDN edge $CdnEdge" }
    Say ("downloading the 7.65 GB runtime onto {0} (about 19 min at 7 MB/s; only 266 MB of rooms are kept)" -f [IO.Path]::GetPathRoot($Work))
    $body = (Step-Body 'rooms').Replace('{URL}', $url).Replace('{EDGE}', $CdnEdge).Replace('{KEEP}', $(if ($KeepBuildFiles) { '1' } else { '' }))
    $null = Run-Wsl 'rooms' $body
}
function Do-Ipsw {
    foreach ($m in $VisionFiles.Keys) { Get-IpswMember $m (In-Vision ('ipsw\' + [IO.Path]::GetFileName($m))) $VisionFiles[$m] }
    # the OS member's first MiB: its AEA header, for Apple's key service
    $head = In-Vision 'ipsw\os.aea.head'
    if ($DryRun -or -not (Test-Path $head) -or (Sha256 $head) -cne $OsHeadSha256) {
        $out = Py 'aeahead.py' @($VisionUrl, $OsMember, $head)
        if (-not $DryRun) {
            $l = "$($out | Where-Object { "$_" -cmatch 'data at \d+' } | Select-Object -First 1)"
            if ($l -cnotmatch "data at $OsDataOff,") { Fail "$OsMember's data is not where it was pinned ($OsDataOff): $l" }
            if ((Sha256 $head) -cne $OsHeadSha256) { Remove-Item $head; Fail "$OsMember's first MiB is not the pinned one (another IPSW?)" }
        }
    } else { Say "have os.aea.head" }
    $body = (Step-Body 'ipsw').Replace('{URL}', $VisionUrl).Replace('{OFF}', "$OsDataOff").Replace('{MEMBER}', $OsMember)
    $null = Run-Wsl 'ipsw' $body
    $idx = In-Vision 'ipsw\os.idx'
    if (-not $DryRun -and (Sha256 $idx) -cne $OsIdxSha256) { Remove-Item $idx; Fail "the OS image's index is not the pinned one (another key or image?): removed" }
}
function Do-Firmware {
    # the kernel: cloudOS 26.4b's research kernel as the iOS 26 install has it, plain (kc-vision.py takes the first
    # of $KernelIn that is; else it is decompressed again out of $KernelPacked)
    $in = @($KernelIn | ForEach-Object { In-Work $_ })
    $null = Py 'kc-vision.py' (@('--check') + $in) -NoFail
    if ($script:Code) {
        $body = Step-Body 'kernel'
        $null = Run-Wsl 'kernel' $body.Replace('{PACKED}', ($KernelPacked -replace '\\', '/'))
        $in += In-Vision 'build\kc\kernel'
    }
    $null = Py 'kc-vision.py' (@((In-Vision 'bootkc-v')) + $in)
    # the device trees: the base's SMP trees with the Vision Pro's identity, one per vCPU count
    Need-Input 'ipsw\DeviceTree.n301ap.im4p' 'ipsw'
    $null = Run-Wsl 'devicetree' (Step-Body 'devicetree')
    $qs = In-Work 'tools\qemu-sptm'
    Show-Cmd "QEMU_SPTM=$qs"
    $env:QEMU_SPTM = $qs
    if (-not $DryRun) { New-Item -ItemType Directory -Force (In-Vision 'build') | Out-Null }
    $smp6 = In-Vision 'build\dtree-smp6'
    $null = Py 'dt-root26smp.py' @((In-Work 'fw\dtree.orig'), $smp6, '--cpus', '6')
    $smp8 = In-Work 'dtree-smp8'
    if (-not $DryRun -and -not (Test-Path $smp8)) {
        $smp8 = In-Vision 'build\dtree-smp8'
        $null = Py 'dt-root26smp.py' @((In-Work 'fw\dtree.orig'), $smp8, '--cpus', '8')
    }
    $raw = In-Vision 'ipsw\DeviceTree.n301ap.raw'
    foreach ($t in @(@('dtree-v', (In-Work 'dtree-smp4')), @('dtree-v6', $smp6), @('dtree-v8', $smp8))) {
        $out = In-Vision $t[0]
        $null = Py 'dt-vision.py' @($t[1], $raw, $out)
        if (-not $DryRun -and (Sha256 $out) -cne $TreeSha[$t[0]]) {
            Say "visionos\$($t[0]) differs from the one measured on our PC (another iOS 26 base's tree?): used as it is" Yellow
        }
    }
}
function Do-Gpu {
    # the guest GPU driver, kept in <Work>\gpu-driver for every guest (an older iOS 26 install has it only on its
    # disk: copied off it, read only)
    $shared = In-Work "gpu-driver\$GpuBundle"
    if ($DryRun -or -not (Test-Path $shared)) {
        $top = @('root.qcow2', 'root26-gpu.qcow2') | Where-Object { $DryRun -or (Test-Path (In-Work $_)) } | Select-Object -First 1
        if (-not $top) { Fail "no $shared and no iOS 26 disk with the GPU driver (root.qcow2): is iOS 26 GPU-less? visionOS cannot draw without it" }
        $body = Step-Body 'gpu-driver'
        $null = Run-Wsl 'gpu-driver' $body.Replace('{TOP}', $top).Replace('{BUNDLE}', $GpuBundle)
    } else { Say "have gpu-driver\$GpuBundle" }
    # visionOS's copy in visionos\gpu (the cleanup keeps it): both Mach-Os retargeted to visionOS (platform 11;
    # dyld refuses an iOS one) and ad-hoc signed
    $body = Step-Body 'gpu'
    $null = Run-Wsl 'gpu' $body.Replace('{BUNDLE}', $GpuBundle)
}
function Need-Gpu {
    if ($DryRun -or ((Test-Path (In-Vision "gpu\$GpuBundle")) -and (Test-Path (In-Vision 'gpu\hashes.txt')))) { return }
    Say 'no visionos\gpu (visionOS''s copy of the GPU driver): the gpu step again' Yellow
    Do-Gpu
}
# The user disks (vision.qcow2 on rootv-a, vision-silent.qcow2 on rootv-s, both on rootv-b on rootv-p on rootv) before
# a step replaces them or a layer under them: a disk the install finished (<disk>.ready) is kept as <disk>.old, with
# what visionOS wrote (on the old layers: mountable with them only), one the install did not finish goes. An .old
# an earlier redo kept is never written over: this one gets the next free name (.old2, .old3, ...)
function Retire-Vision {
    foreach ($n in 'vision.qcow2', 'vision-silent.qcow2') {
        $disk = In-Vision $n
        $ready = "$disk.ready"
        if (-not (Test-Path $disk)) { Remove-Item $ready -ErrorAction SilentlyContinue; continue }
        Need-NoVision
        if (Test-Path $ready) {
            $old = "$disk.old"
            for ($k = 2; (Test-Path $old); $k++) { $old = "$disk.old$k" }
            Say "visionos\$n, a disk visionOS ran from, rests on what this step replaces: kept as visionos\$(Split-Path $old -Leaf) (a new one starts afresh)" Yellow
            if (-not $DryRun) { Move-Item $disk $old; Remove-Item $ready -Force }
        } else {
            Show-Cmd "del visionos\$n   (an unfinished install's)"
            if (-not $DryRun) { Remove-Item $disk -Force }
        }
    }
}
function Do-Rootfs {
    # a root built before goes first, with the layers on it (the chain after this step is redone)
    Retire-Vision
    foreach ($f in 'rootv-a.qcow2', 'rootv-s.qcow2', 'rootv-b.qcow2', 'rootv-p.qcow2', 'rootv-p.hashes', 'rootv.qcow2', 'rootv.qcow2.hashes') {
        if ($DryRun -or (Test-Path (In-Vision $f))) { Show-Cmd "del visionos\$f"; if (-not $DryRun) { Remove-Item (In-Vision $f) -Force } }
    }
    Need-Input 'ipsw\os.idx' 'ipsw'
    Need-Space $Space.rootfs
    Say 'copying the root out of Apple''s OS image over the network (74 min on our PC: one apfs-fuse reader at a time)'
    $body = (Step-Body 'rootfs').Replace('{CACHE_MB}', '512')
    $null = Run-Wsl 'rootfs' $body
}
# The audio plug-in this install has (visionos\audio, checked) or can get (-AudioPlugin, the release): 'plugin' or 'none'
function Audio-State {
    if ($AudioPlugin -or $AudioPluginRelease.Url) { return 'plugin' }
    if (Test-Path (In-Vision 'audio\hash.txt')) { return 'plugin' }
    'none'
}
# A finished install (its disks step done, the silent disk ready) is not taken apart for the plug-in: its disk chain
# is not redone when the audio step's signature changes. A plug-in that came after it (given now, or published since)
# only adds the sound disk: rootv-a.qcow2 on the finished rootv-b.qcow2 with the plug-in on it, vision.qcow2 on that,
# and rootv.tc gains the plug-in's CDHash. vision-silent.qcow2, every layer under it and its saves stay as they are.
# (-From audio redoes the disk chain with the plug-in in the root instead, as an install that had it from the start:
# the finished disks are then kept as .old on layers that are rebuilt, which they cannot boot from.)
function Install-Finished { ((Get-Mark 'disks') -ceq 'done') -and (Test-Path (In-Vision 'vision-silent.qcow2.ready')) }
function Sound-Later { (Install-Finished) -and ((Audio-State) -ceq 'plugin') -and -not (Test-Path (In-Vision 'vision.qcow2.ready')) }
# VPhoneVirtIOSound.driver in a folder: the folder itself, or where the CI's artifact puts it
function Find-Driver([string]$dir) {
    foreach ($rel in '', 'VPhoneVirtIOSound.driver', 'xros\VPhoneVirtIOSound.driver', 'VPhoneVirtIOSound\xros\VPhoneVirtIOSound.driver') {
        $d = if ($rel) { [IO.Path]::Combine($dir, $rel) } else { $dir }
        if (Test-Path -LiteralPath ([IO.Path]::Combine($d, 'VPhoneVirtIOSound')) -PathType Leaf) { return $d }
    }
    $null
}
# its three files against the pinned SHA-256s; '' when they match, else why not
function Driver-Mismatch([string]$d) {
    foreach ($f in $AudioFiles.Keys) {
        $p = [IO.Path]::Combine($d, ($f -replace '/', '\'))
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return "no $f in $d" }
        if ((Sha256 $p) -cne $AudioFiles[$f]) { return "$p is not the pinned build (SHA-256 $(Sha256 $p))" }
    }
    ''
}
function Do-Audio {
    $dst = In-Vision 'audio\VPhoneVirtIOSound.driver'
    $src = $null
    if ($AudioPlugin) {
        $src = Find-Driver ([IO.Path]::GetFullPath($AudioPlugin))
        if (-not $src) { Stop-Here "-AudioPlugin $AudioPlugin`: no VPhoneVirtIOSound.driver there (its xros build, as the CI's artifact has it)"; return }
    } elseif ($AudioPluginRelease.Url) {
        $zip = In-Work "downloads\VPhoneVirtIOSound-$($AudioPluginRelease.Version).zip"
        $x = In-Vision 'build\audio'
        if (-not $DryRun) { New-Item -ItemType Directory -Force (Split-Path $zip) | Out-Null }
        $null = Run 'curl.exe' @('-fL', '--retry', '5', '-o', $zip, $AudioPluginRelease.Url)
        Show-Cmd "unzip $zip -> $x"
        if ($DryRun) { $src = Join-Path $x 'VPhoneVirtIOSound.driver' } else {
            if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $AudioPluginRelease.Sha256.ToUpperInvariant()) { Remove-Item $zip; Fail "${zip}: wrong SHA-256 (removed)" }
            Remove-Item $x -Recurse -Force -ErrorAction SilentlyContinue
            Expand-Archive $zip $x -Force
            $src = Find-Driver $x
            if (-not $src) { Fail "$zip has no VPhoneVirtIOSound.driver" }
        }
    } elseif ((Test-Path (In-Vision 'audio\hash.txt')) -and -not (Driver-Mismatch $dst)) {
        Say "have visionos\audio\VPhoneVirtIOSound.driver ($AudioCdHash)"
        return
    }
    if (-not $src) {
        Say ('No audio plug-in (VPhoneVirtIOSound): it is not published yet and -AudioPlugin <folder> was not given. ' +
             'visionOS is installed SILENT ONLY: there will be no sound disk (Start-visionOS.cmd -Sound refuses). Give the ' +
             'plug-in later with -AudioPlugin and run this installer again: it adds the sound disk, and the silent one stays as it is.') Yellow
        if (-not $DryRun) { Remove-Item (In-Vision 'audio') -Recurse -Force -ErrorAction SilentlyContinue }
        return
    }
    Show-Cmd "check $src (SHA-256s pinned, CDHash $AudioCdHash), copy -> $dst"
    if ($DryRun) { return }
    $why = Driver-Mismatch $src
    if ($why) { Fail "the audio plug-in is not the pinned build: $why" }
    $new = In-Vision 'audio.new\VPhoneVirtIOSound.driver'
    Remove-Item (In-Vision 'audio.new') -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force (Join-Path $new '_CodeSignature') | Out-Null
    foreach ($f in $AudioFiles.Keys) { Copy-Item -LiteralPath ([IO.Path]::Combine($src, ($f -replace '/', '\'))) ([IO.Path]::Combine($new, ($f -replace '/', '\'))) }
    $out = Py 'cdhash.py' @("$new\VPhoneVirtIOSound")
    if (-not (@($out) | Where-Object { "$_" -cmatch "^$AudioCdHash " })) { Fail "VPhoneVirtIOSound's CDHash is not $AudioCdHash (see above)" }
    Set-Content (In-Vision 'audio.new\hash.txt') $AudioCdHash -Encoding ASCII
    Remove-Item (In-Vision 'audio') -Recurse -Force -ErrorAction SilentlyContinue
    Rename-Item (In-Vision 'audio.new') 'audio'
    Say "VPhoneVirtIOSound.driver ($AudioCdHash): the sound disk gets it"
}
function Audio-Wsl { if (-not $DryRun -and (Test-Path (In-Vision 'audio\hash.txt'))) { To-Wsl (In-Vision 'audio\VPhoneVirtIOSound.driver') } elseif ($DryRun -and (Audio-State) -ceq 'plugin') { '$W/audio/VPhoneVirtIOSound.driver' } else { '' } }
function Do-Patches {
    # on an overlay made anew each time (rootv.qcow2 stays as mk-rootx.sh built it), so this step can be redone:
    # the shared-cache patches find their stock bytes only once
    Need-Input 'rootv.qcow2' 'rootfs'
    Need-Input 'rootv.qcow2.hashes' 'rootfs'
    Need-Input 'rooms' 'rooms'
    Need-Input 'rooms-noaudio' 'rooms'
    Need-Gpu
    Need-Space $Space.patches
    Retire-Vision
    $body = (Step-Body 'patches').Replace('{AUDIO}', (Audio-Wsl))
    $null = Run-Wsl 'patches' $body
}
function Do-TrustCache {
    # Apple's, the signed sysroot (rootfs), the patched binaries (patches), the GPU driver and the audio plug-in:
    # each list from the step that makes it
    $in = [ordered]@{ "ipsw\$OsMember.trustcache" = 'ipsw'; 'rootv.qcow2.hashes' = 'rootfs'; 'rootv-p.hashes' = 'patches'; 'gpu\hashes.txt' = 'gpu' }
    if ((Audio-Wsl)) { $in['audio\hash.txt'] = 'audio' }
    foreach ($f in $in.Keys) { Need-Input $f $in[$f] }
    $null = Py 'mktc.py' (@('-2', (In-Vision 'rootv.tc')) + @($in.Keys | ForEach-Object { In-Vision $_ }))
}
function Do-FirstBoot {
    # once, so usermanagerd writes the persona manifest and the user session (persona.kb, usersession.kb) the
    # persona step completes, and mobileactivationd makes its container (measured on the hand-built disk: both
    # there after boot 1, about 6 min). HFS+ lets it write them only when they are new.
    Need-Input 'rootv-p.qcow2' 'patches'
    Need-Input 'rootv.tc' 'trustcache'
    Need-NoVision
    Retire-Vision
    foreach ($f in 'rootv-a.qcow2', 'rootv-s.qcow2') { if (Test-Path (In-Vision $f)) { Show-Cmd "del visionos\$f"; if (-not $DryRun) { Remove-Item (In-Vision $f) -Force } } }
    $null = Run-Wsl 'overlay' 'overlay rootv-p.qcow2 visionos/rootv-b.qcow2'
    Need-Space $Space.firstboot
    $g = Start-Vision 'install-firstboot'
    try {
        $test = 'test -e /private/var/keybags/persona.kb && test -e /private/var/keybags/usersession.kb && echo __READY__ || echo __WAIT__'
        Say 'waiting for /private/var/keybags/persona.kb and usersession.kb in the guest (up to 30 min; about 6 on our PC)'
        if ($DryRun) {
            $null = Guest 90 @($test)
        } else {
            $t0 = Get-Date
            while ($true) {
                if (-not (Guest-Alive $g)) { Fail "QEMU ended during the first boot; see $($g.Dir)" }
                $min = ((Get-Date) - $t0).TotalMinutes
                Emit 'pct', 'vision', 'firstboot', ([int][Math]::Min(95, 100 * $min / 8)), 'waiting for the persona manifest'
                $out = Guest 90 @($test) -NoFail
                # a line of its own: the command (printed as "$ cmd" above it) has the word too
                if (@($out | Where-Object { "$_".Trim() -ceq '__READY__' }).Count) { break }
                if ($min -gt 30) { Fail "no persona.kb after 30 min; see $($g.Dir)\serial.log" }
                Start-Sleep -Seconds 30
            }
            Say ("there after {0:N0} min" -f ((Get-Date) - $t0).TotalMinutes)
            Start-Sleep -Seconds 30
        }
        if (-not (Stop-Vision $g)) { Fail 'the guest did not answer sync; run again to redo the first boot' }
    } catch {
        if (-not $DryRun -and (Guest-Alive $g)) { $null = Stop-Vision $g -NoSync }
        throw
    }
}
function Do-Persona {
    # (root26-prefs.py only warns when it finds no mobileactivationd container: here that is a failure)
    Need-Input 'rootv-b.qcow2' 'firstboot'
    Need-NoVision
    $null = Run-Wsl 'persona' (Step-Body 'persona')
}
function Do-HomeBoot {
    # once more, to Home: lsd registers the staged apps (their LaunchServices database went stale), the system
    # settles what a first start sets up, so the user's first start is a plain one. Home = the screen dumped by QMP
    # over 60 KB twice 20 s apart (a black or blank frame is a few KB); then 2 min more
    Need-Input 'rootv-b.qcow2' 'firstboot'
    Need-NoVision
    Need-Space $Space.homeboot
    $g = Start-Vision 'install-homeboot'
    try {
        Say 'waiting for Home (up to 30 min; 4 to 6 on our PC)'
        if (-not $DryRun) {
            $t0 = Get-Date
            $seen = 0
            $n = 0
            while ($true) {
                if (-not (Guest-Alive $g)) { Fail "QEMU ended during the boot to Home; see $($g.Dir)" }
                $min = ((Get-Date) - $t0).TotalMinutes
                Emit 'pct', 'vision', 'homeboot', ([int][Math]::Min(95, 100 * $min / 8)), 'waiting for Home'
                $n++
                $bytes = Screen-Bytes $g ("screen-{0:D2}" -f $n)
                if ($bytes -gt 60000) { $seen++ } else { $seen = 0 }
                if ($seen -ge 2) { Say ("Home after {0:N0} min ($($g.Dir)\screen-{1:D2}.png)" -f $min, $n); break }
                if ($min -gt 30) { Say 'no Home after 30 min: the first start goes on with what this boot did not finish' Yellow; break }
                Start-Sleep -Seconds 20
            }
            Start-Sleep -Seconds 120
        }
        if (-not (Stop-Vision $g)) { Fail 'the guest did not answer sync; run again to redo this boot' }
    } catch {
        if (-not $DryRun -and (Guest-Alive $g)) { $null = Stop-Vision $g -NoSync }
        throw
    }
}
function Do-Disks {
    Need-Input 'rootv-b.qcow2' 'firstboot'
    Need-NoVision
    Need-Space $Space.disks
    $audio = Audio-Wsl
    if ($SoundOnly) {
        # the plug-in came after the silent install was finished (Sound-Later): only the sound disk is made
        Say ('The audio plug-in came after this silent install was finished: the sound disk is added on its finished layers ' +
             '(rootv-a.qcow2 with the plug-in, vision.qcow2 on it); vision-silent.qcow2, the layers under it and its saves ' +
             'stay as they are. (-From audio would redo the disk chain with the plug-in in the root instead: the finished ' +
             'disks would then be kept as .old on rebuilt layers, which they cannot boot from.)') Yellow
        Need-Input 'audio\hash.txt' 'audio'
        if (Test-Path (In-Vision 'vision.qcow2')) { Show-Cmd 'del visionos\vision.qcow2   (an unfinished one)'; if (-not $DryRun) { Remove-Item (In-Vision 'vision.qcow2') -Force } }
    } else {
        Retire-Vision
    }
    if ($audio) {
        # rootv.tc has the plug-in's CDHash (the trustcache step's, when the plug-in came first; one that came later
        # gets it here): made from itself, so every entry a disk boots with stays
        $tc = In-Vision 'rootv.tc'
        $null = Py 'mktc.py' @('-2', "$tc.new", $tc, (In-Vision 'audio\hash.txt'))
        Show-Cmd 'replace visionos\rootv.tc with rootv.tc.new'
        # (no backup: [NullString], as PowerShell passes $null to a string as '')
        if (-not $DryRun) { [IO.File]::Replace("$tc.new", $tc, [NullString]::Value) }
    }
    $null = Run-Wsl 'disks' (Step-Body 'disks').Replace('{AUDIO}', $audio).Replace('{SOUND_ONLY}', $(if ($SoundOnly) { '1' } else { '' }))
    # the disks are the user's now: a later redo keeps them (Retire-Vision); the launcher starts only these
    if (-not $DryRun) {
        if (-not $SoundOnly) { Set-Content (In-Vision 'vision-silent.qcow2.ready') (Get-Date -Format s) }
        if ($audio) { Set-Content (In-Vision 'vision.qcow2.ready') (Get-Date -Format s) }
    }
}
function Do-Cleanup {
    if ($KeepBuildFiles) { Say '-KeepBuildFiles: the runtime''s .dmg and the build''s leftovers stay' DarkGray; return }
    $null = Run-Wsl 'cleanup' (Step-Body 'cleanup').Replace('{KEEP}', '')
    # (rooms, rooms-noaudio, gpu, audio, ipsw\os.idx and the hash lists stay: a later redo of the disk steps reads them)
    foreach ($rel in 'visionos\build', 'visionos\tmp', 'visionos\audio.new', 'visionos\rooms.new', 'visionos\rooms-noaudio.new') {
        if (-not (Test-Path (In-Work $rel))) { continue }
        Show-Cmd "del $rel"
        if ($DryRun) { continue }
        try { Remove-Item (In-Work $rel) -Recurse -Force }
        catch {
            # a running visionOS's temporary files (Start-visionOS.ps1's TEMP)
            if ($rel -cne 'visionos\tmp') { throw }
            Say 'visionos\tmp is in use (visionOS is running): left' DarkGray
        }
    }
}
function Do-Shortcut {
    $cmd = Join-Path $repo 'Start-visionOS.cmd'
    Say "start it with $cmd (-Sound for the sound disk$(if (-not (Test-Path (In-Vision 'vision.qcow2'))) { ', which this install does not have' }))"
    if ($NoShortcut -or $DryRun) { return }
    try {
        $dir = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\ASoftware'
        New-Item -ItemType Directory -Force $dir | Out-Null
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $dir 'ASoftware visionOS.lnk'))
        $s.TargetPath = $cmd
        $s.Arguments = "-Work `"$Work`""
        $s.WorkingDirectory = $repo
        $s.Save()
        Say "Start menu: ASoftware\ASoftware visionOS"
    } catch {
        Say "no Start menu shortcut ($($_.Exception.Message)): start it with $cmd" Yellow
    }
}

# Min: minutes on our PC (i7-13700HX, 24 threads, ~7 MB/s from Apple's CDN), measured by hand for the build (notes/
# VISIONOS-INSTALL.md section 2); GB: what it downloads
$Steps = @(
    @{ Id = 'check';      Kind = 'always'; Min = 1;  GB = 0;    Title = 'The iOS 26 base it builds on, WSL and its tools, the scripts' }
    @{ Id = 'qemu';       Kind = 'once';   Min = 1;  GB = 0.32; Title = 'The QEMU every guest runs on, with visionOS''s options (qemu\)' }
    @{ Id = 'rooms';      Kind = 'once';   Min = 22; GB = 7.65; Title = 'The six synthetic rooms, out of Apple''s visionOS Simulator Runtime' }
    @{ Id = 'ipsw';       Kind = 'once';   Min = 2;  GB = 0.003; Title = 'visionOS 27.2 IPSW: trust cache, device tree, the OS image''s key and index' }
    @{ Id = 'firmware';   Kind = 'once';   Min = 1;  GB = 0;    Title = 'The visionOS kernel and device trees (4, 6 and 8 vCPUs)' }
    @{ Id = 'gpu';        Kind = 'once';   Min = 1;  GB = 0;    Title = 'The guest GPU driver for visionOS' }
    @{ Id = 'rootfs';     Kind = 'chain';  Min = 75; GB = 10;   Title = 'The root disk, read out of Apple''s OS image (visionos\rootv.qcow2)' }
    @{ Id = 'audio';      Kind = 'chain';  Min = 1;  GB = 0;    Title = 'The virtio-snd audio plug-in (VPhoneVirtIOSound), when there is one' }
    @{ Id = 'patches';    Kind = 'chain';  Min = 3;  GB = 0;    Title = 'Patches, prefs, apps, rooms, keyboard camera and GPU driver on it' }
    @{ Id = 'trustcache'; Kind = 'chain';  Min = 1;  GB = 0;    Title = 'Its trust cache (visionos\rootv.tc)' }
    @{ Id = 'firstboot';  Kind = 'chain';  Min = 8;  GB = 0;    Title = 'First boot (visionos\rootv-b.qcow2)' }
    @{ Id = 'persona';    Kind = 'chain';  Min = 1;  GB = 0;    Title = 'Persona, MobileGestalt, activation and visionOS''s prefs' }
    @{ Id = 'homeboot';   Kind = 'chain';  Min = 10; GB = 0;    Title = 'Second boot, to Home' }
    @{ Id = 'disks';      Kind = 'chain';  Min = 1;  GB = 0;    Title = 'The silent and sound disks' }
    @{ Id = 'cleanup';    Kind = 'always'; Min = 1;  GB = 0;    Title = 'Remove what only the build needs' }
    @{ Id = 'shortcut';   Kind = 'always'; Min = 0;  GB = 0;    Title = 'Start-visionOS.cmd and the Start menu shortcut' }
)
$ids = @($Steps | ForEach-Object { $_.Id })
foreach ($s in @($From, $Only)) { if ($s -and $ids -cnotcontains $s) { throw "no step $s (the steps: $($ids -join ', '))" } }
function Invoke-Step([string]$id) {
    switch -CaseSensitive ($id) {
        'check' { Do-Check } 'qemu' { Do-Qemu } 'rooms' { Do-Rooms } 'ipsw' { Do-Ipsw } 'firmware' { Do-Firmware }
        'gpu' { Do-Gpu } 'rootfs' { Do-Rootfs } 'audio' { Do-Audio } 'patches' { Do-Patches } 'trustcache' { Do-TrustCache }
        'firstboot' { Do-FirstBoot } 'persona' { Do-Persona } 'homeboot' { Do-HomeBoot } 'disks' { Do-Disks }
        'cleanup' { Do-Cleanup } 'shortcut' { Do-Shortcut }
    }
}

# --- The iOS 26 install's settings ---------------------------------------------------------------
$cfg = $null
if (Test-Path $Config) { try { $cfg = Get-Content $Config -Raw | ConvertFrom-Json } catch { } }
if (-not $Work -and $cfg) { $Work = [string]$cfg.Work }
if (-not $Work) { throw "no iOS 26 install found ($Config has no work folder): install iOS 26 (or its base) first, or give -Work" }
$Work = [IO.Path]::GetFullPath($Work).TrimEnd('\')
$Distro = if ($cfg -and $cfg.Distro) { [string]$cfg.Distro } else { 'ios-emu' }
$LinuxDir = if ($cfg -and $cfg.Linux) { [string]$cfg.Linux } else { '/root/ios26' }
$LinuxMode = if ($cfg -and $cfg.LinuxMode) { [string]$cfg.LinuxMode } else { 'wsl' }
$Py = Join-Path $Work 'tools\python\python.exe'
if (-not (Test-Path $Py)) { $Py = (Get-Command python.exe -ErrorAction SilentlyContinue).Source }
if (-not $Py) { $Py = 'python.exe' }

if ($List) {
    $tm = 0; $tg = 0
    $later = Sound-Later
    foreach ($s in $Steps) {
        $m = if ($s.Kind -ceq 'always') { 'every run' } elseif ($later -and $s.Id -ceq 'disks') { 'add sound' } elseif ((Get-Mark $s.Id) -ceq (Step-Sig $s.Id)) { 'done' } elseif (Get-Mark $s.Id) { 'redo' } else { '-' }
        Say ("{0,-11} {1,-6} {2,-10} {3,6} {4,9}  {5}" -f $s.Id, $s.Kind, $m, $(if ($s.Min) { "$($s.Min) min" } else { '' }),
             $(if ($s.GB -ge 0.01) { '{0:N2} GB' -f $s.GB } elseif ($s.GB) { '< 0.01 GB' } else { '' }), $s.Title)
        $tm += $s.Min; $tg += $s.GB
    }
    Say ("whole run about {0} h {1} min on our PC, {2:N1} GB from Apple and our releases (audio plug-in: {3})" -f [Math]::Floor($tm / 60), ($tm % 60), $tg, (Audio-State)) DarkGray
    if ($later) { Say 'the audio plug-in came after this silent install was finished: a run adds the sound disk, and vision-silent.qcow2 and the layers under it stay as they are' Yellow }
    exit 0
}

# --- Run -----------------------------------------------------------------------------------------
Write-Host "ASoftware visionOS installer$(if ($DryRun) { ' (dry run: nothing is run)' })" -ForegroundColor Cyan
Write-Host "  Work $Work (WSL: $(To-Wsl $Work)), WSL distro $Distro, Linux scratch $LinuxDir"
$fromIdx = if ($From) { [array]::IndexOf($ids, $From) } else { -1 }
$chainRedone = $false
# A finished install keeps its disks when the audio step runs again (its chain is not redone), and a plug-in that came
# after it only adds the sound disk (Sound-Later); -From and -Only redo what they name, as before
$keepDisks = -not $From -and -not $Only -and (Install-Finished)
$SoundOnly = $keepDisks -and (Sound-Later)
for ($i = 0; $i -lt $Steps.Count; $i++) {
    $s = $Steps[$i]
    $forced = ($From -and $i -ge $fromIdx) -or ($Only -ceq $s.Id) -or ($SoundOnly -and $s.Id -ceq 'disks')
    $label = "{0}/{1} {2}: {3}" -f ($i + 1), $Steps.Count, $s.Id, $s.Title
    if ($s.Kind -cne 'always' -and -not $forced) {
        if ($Only -or ($From -and $i -lt $fromIdx)) { continue }
        if ((Get-Mark $s.Id) -ceq (Step-Sig $s.Id) -and -not ($s.Kind -ceq 'chain' -and $chainRedone)) {
            Write-Host "== $label  [done]" -ForegroundColor DarkGray
            Emit 'step', 'vision', ($i + 1), $Steps.Count, $s.Id, 'skip', $s.Title
            continue
        }
    }
    if ($Only -and $s.Kind -ceq 'always' -and $Only -cne $s.Id -and $s.Id -cne 'check') { continue }
    if (-not $DryRun -and (Pause-Requested)) {
        Emit 'paused', 'vision', $s.Id
        Write-Host ''
        Write-Host "Paused before step $($s.Id) (ASoftware.exe). Run this again to go on from it." -ForegroundColor Yellow
        exit 5
    }
    Step $label
    Emit 'step', 'vision', ($i + 1), $Steps.Count, $s.Id, 'start', $s.Title
    $script:Log = $null
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force (In-Work 'install\logs') | Out-Null
        $script:Log = In-Work "install\logs\vision-$($s.Id).log"
        Add-Content $script:Log ("`n=== {0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $label)
    }
    try {
        if ($s.Kind -ceq 'chain' -and -not ($keepDisks -and $s.Id -ceq 'audio')) {
            $chainRedone = $true
            for ($j = $i + 1; $j -lt $Steps.Count; $j++) {
                if ($Steps[$j].Kind -ceq 'chain' -and -not $DryRun) { Clear-Mark $Steps[$j].Id }
            }
        }
        # its own marker too: a redone step that fails (what it replaces may be gone) is redone next time. Not the
        # disks step's when it only adds the sound disk: that marker stands for the silent disk, which stays
        if ($s.Kind -cne 'always' -and -not $DryRun -and -not ($SoundOnly -and $s.Id -ceq 'disks')) { Clear-Mark $s.Id }
        Invoke-Step $s.Id
    } catch {
        Write-Host ''
        Write-Host "Step $($s.Id) failed: $($_.Exception.Message)" -ForegroundColor Red
        if ($script:Log) { Write-Host "  log: $script:Log" }
        Write-Host ("  Fix the cause and run Install-ASoftware.cmd (or visionos\Install-visionOS.cmd) again: it goes on " +
                    "from this step (Install-visionOS.cmd -Only $($s.Id) redoes just this one).") -ForegroundColor Yellow
        Emit 'step', 'vision', ($i + 1), $Steps.Count, $s.Id, 'fail', $_.Exception.Message
        Emit 'end', 'vision', 1
        exit 1
    }
    if ($s.Kind -cne 'always' -and -not $DryRun) { Set-Mark $s.Id (Step-Sig $s.Id) }
    Emit 'step', 'vision', ($i + 1), $Steps.Count, $s.Id, 'done', $s.Title
}
Emit 'end', 'vision', 0
Write-Host ''
if ($DryRun) { Write-Host 'Dry run: nothing was run.' -ForegroundColor Cyan }
elseif ($Only) { Write-Host "Done: $Only." -ForegroundColor Cyan }
else { Write-Host 'Done. Start visionOS with Start-visionOS.cmd (-Sound for sound) or the Start menu shortcut.' -ForegroundColor Cyan }

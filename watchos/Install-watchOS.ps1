# ASoftware watchOS installer: watchOS 27.2 (24S118) as an Apple Watch Series 9 (Watch7,1, 41 mm) on
# -M vresearch, built on this PC's iOS 26 install or only its base (Install-iOS26.ps1's work folder; its
# -Base is enough: iOS 26 itself is not needed). From it: cloudOS
# 26.4b's research kernel (cloud\kernelcache.research.vphone600.decompressed, which kc-watch.py patches
# into the watch's), SPTM, TXM, the device trees (dtree-smp4/8, which dt-watch.py gives the watch's
# identity), the shell ramdisk, darwin-vm's sysroot, the guest GPU driver and the WSL distro. The
# scripts come with this installer (ios26\scripts and watchos\scripts, copied into work\watchos\scripts).
# From Apple it downloads only the watch IPSW's OS image (5.03 GB), its trust cache and its device tree;
# and our QEMU with the watch's machine options (ppi, usb-crown, the GTK watch case) into qemu-watch\,
# unless that is there already.
# Everything goes into <Work>\watchos (about 13 GB when done; the build peaks near 21 GB), and leaves a
# marker per step in <Work>\install\watch-*.done, so running it again goes on where it stopped.
#
#   watchos\Install-watchOS.cmd [-Work D:\ios26] [-List] [-DryRun] [-From STEP | -Only STEP] ...
#     -WatchIpsw FILE  take Apple's files from a watch IPSW on this PC
#     -WatchDir DIR[|DIR]  folders with some of them as files: 141-08453-168.dmg.aea (checked by its
#                      SHA-1), 141-08453-168.dmg.aea.trustcache, DeviceTree.n207sap.im4p or its unwrapped
#                      DeviceTree.n207sap.raw; what none has is downloaded
#     -QemuFrom auto|release|<folder>   the watch QEMU: auto = qemu-watch\ as it is, else the release
#                      package below, else stop; <folder> copies a build you have (win-build.sh's dist),
#                      checked for the watch's devices first
#     -KeepBuildFiles  keep the decrypted image and the build's leftovers
# The Linux steps run in the iOS 26 install's WSL distro (its -Linux helper mode is not supported here).
# Redoing a disk step (-From/-Only rootfs, patches, trustcache, firstboot) after a finished install keeps
# the watch's disk as watchos\watch.qcow2.old: the new one starts afresh.
param(
    [string]$Work = '',
    [string]$Config = (Join-Path $env:LOCALAPPDATA 'ASoftware iOS 26\ios26.config.json'),
    [string]$WatchIpsw = '',
    [string[]]$WatchDir = @(),
    [string]$QemuFrom = 'auto',
    [string]$From = '',
    [string]$Only = '',
    [switch]$DryRun,
    [switch]$List,
    [switch]$KeepBuildFiles,
    [switch]$NoShortcut
)
$ErrorActionPreference = 'Stop'
# (powershell -File passes -WatchDir a,b as one string: '|' parts, and ',' parts of what is no folder
# as a whole, as Apple's names have commas: D:\ipsw\Watch7,1)
$WatchDir = @($WatchDir | ForEach-Object { "$_" -split '\|' } | Where-Object { $_ } | ForEach-Object {
        if ((Test-Path -LiteralPath $_ -PathType Container) -or $_ -cnotmatch ',') { $_ } else { $_ -split ',' }
    } | Where-Object { $_ })
$here = $PSScriptRoot
$repo = Split-Path $here

# --- What it downloads, pinned -----------------------------------------------------------------
# Apple's watchOS 27.2 (24S118) restore IPSW for Watch7,1 (Series 9 41 mm GPS); only these members
$WatchUrl = 'https://updates.cdn-apple.com/2026FallFCS/fullrestores/142-48899/8300757E-0764-4393-ACB8-F3B486BF7D19/Watch7,1_27.2_24S118_Restore.ipsw'
$OsImage = '141-08453-168.dmg'       # the OS (AEA; its key from Apple's key service, as for iOS 26)
$OsAeaSha1 = 'F6ED700829EA9C0943C4593603544450F91ACB8C'
$WatchFiles = [ordered]@{        # member = bytes; into <Work>\watchos\ipsw, without the folder
    "$OsImage.aea"                                = 5033164800
    "Firmware/$OsImage.aea.trustcache"            = 99169
    'Firmware/all_flash/DeviceTree.n207sap.im4p'  = 39613
}
# Our QEMU for Windows with the watch's options: qemu-sptm asoft-watch (asoft 7364c4e + ppi, usb-consumer
# power-usage, usb-crown, the GTK watch case) with reims-vgpu / metal2vulkan that write imageblock slices
# into extended-range textures (watchOS's backdrops). Not published yet: -QemuFrom <folder> until then.
$QemuWatchRelease = @{ Version = ''; Url = ''; Sha256 = '' }
$GpuBundle = 'AppleParavirtGPUMetalIOGPUFamily.bundle'
# the kernel kc-watch.py starts from: the iOS 26 install's plain one (its fw\bootkc is that file only when
# its gpu step did not add OpenGL ES's keys to it), kc-watch.py taking the first that is the stock kernel;
# else the firmware step decompresses it again out of what iOS 26 downloaded (its cleanup keeps it)
$KernelIn = @('cloud\kernelcache.research.vphone600.decompressed', 'fw\bootkc')
$KernelPacked = 'cloudos\kernelcache.research.vphone600'
# GB a step adds on the work folder's drive at most
$Space = @{ download = 5.1; decrypt = 9.0; rootfs = 13.0; patches = 1.5; firstboot = 1.5; qemu = 0.6 }

# --- Output, running tools (as Install-iOS26.ps1) ------------------------------------------------
function Step([string]$text) { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }
# Progress for ASoftware.exe, which sets ASOFT_PROGRESS=1: ##asoft|kind|field|..., one line each
# (step|watch|N|OF|ID|start|TITLE, step|...|done/skip/fail, pct|watch|ID|0-100|TEXT, paused|watch|ID, end|watch|CODE)
function Emit([object[]]$f) { if ($env:ASOFT_PROGRESS -ceq '1') { Write-Host ('##asoft|' + (@($f | ForEach-Object { "$_" -replace '[|\r\n]', ' ' }) -join '|')) } }
# ASoftware.exe's "pause after this step": the file ASOFT_PAUSE_FILE names is there before a step starts
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
# (the scripts the check step copies into watchos\scripts: this version's iOS 26 scripts and the watch's)
function Py([string]$script, [string[]]$argv, [switch]$NoFail) {
    Run $Py (@('-I', '-B', (In-Watch "scripts\$script")) + $argv) -NoFail:$NoFail
}
function To-Wsl([string]$p) {
    $f = [IO.Path]::GetFullPath($p)
    '/mnt/' + $f.Substring(0, 1).ToLowerInvariant() + ($f.Substring(2) -replace '\\', '/')
}
function In-Work([string]$rel) { Join-Path $Work $rel }
function In-Watch([string]$rel) { Join-Path (Join-Path $Work 'watchos') $rel }
function Free-GB { ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($Work))).AvailableFreeSpace / 1e9 }
function Need-Space([double]$gb) {
    if ($gb -le 0) { return }
    if ($DryRun) { Say ("needs about {0:N1} GB free on {1}" -f $gb, [IO.Path]::GetPathRoot($Work)) DarkGray; return }
    $free = Free-GB
    if ($free -lt $gb + 1) {
        Fail ("{0:N1} GB free on {1}; this step needs about {2:N0} GB: free some space" -f $free, [IO.Path]::GetPathRoot($Work), ($gb + 1))
    }
}

# A bash script for WSL, as Install-iOS26.ps1's (its prelude: the folders, disk_tools, in_root, overlay)
function Prelude([string]$name) {
    $p = @'
#!/bin/bash
# Install-watchOS.ps1, {NAME}: written by the installer, run as root in WSL ({DISTRO})
set -euo pipefail
export ASOFT26={A} ASOFT26_LINUX={L}
A=$ASOFT26 L=$ASOFT26_LINUX S=$ASOFT26/watchos/scripts W=$ASOFT26/watchos
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
# A Linux step's body: steps\NAME.sh beside this script (the Android app's setup reads the same files),
# its {PLACEHOLDERS} filled by the caller. Read from this release's own folder, never from a work folder.
function Step-Body([string]$name) {
    $f = Join-Path $here "steps\$name.sh"
    if (-not (Test-Path $f)) { Fail "no $f (this installer comes with its steps folder)" }
    ([IO.File]::ReadAllText($f) -replace "`r`n", "`n").TrimEnd("`n")
}
function Run-Wsl([string]$name, [string]$body) {
    $file = In-Work "install\sh\watch-$name.sh"
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

# One IPSW member (the URL, or the IPSW on this PC) with ipsw-get.py: resumable, CRC-checked
function Get-IpswMember([string]$member, [string]$out, [long]$size) {
    $ok = In-Work ('install\got\watch-' + [IO.Path]::GetFileName($out) + '.ok')
    if (-not $DryRun -and (Test-Path $ok) -and (Test-Path $out) -and (-not $size -or (Get-Item $out).Length -eq $size)) {
        Say "have $member"
        return
    }
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force (Split-Path $out), (Split-Path $ok) | Out-Null
        Remove-Item $ok -ErrorAction SilentlyContinue
    }
    $from = if ($WatchIpsw) { [IO.Path]::GetFullPath($WatchIpsw) } else { $WatchUrl }
    $null = Py 'ipsw-get.py' @($from, $member, $out)
    if (-not $DryRun) { Set-Content $ok $member }
}

# --- Markers -----------------------------------------------------------------------------------
function Mark-File([string]$id) { In-Work "install\watch-$id.done" }
function Get-Mark([string]$id) { $f = Mark-File $id; if (Test-Path $f) { (Get-Content $f -Raw).Trim() } else { $null } }
function Set-Mark([string]$id, [string]$sig) { Set-Content -Path (Mark-File $id) -Value $sig -Encoding UTF8 }
function Clear-Mark([string]$id) { Remove-Item (Mark-File $id) -ErrorAction SilentlyContinue }
function Step-Sig([string]$id) { 'done' }

# --- The guest (first boot) --------------------------------------------------------------------
# A QMP command (its arguments a hashtable); -Quiet: neither the command nor a failure is printed
function Send-Qmp([string]$command, [hashtable]$arguments = $null, [switch]$Quiet) {
    $json = if ($arguments) { (@{ execute = $command; arguments = $arguments } | ConvertTo-Json -Compress -Depth 4) } else { "{`"execute`":`"$command`"}" }
    if (-not $Quiet) { Show-Cmd "QMP 127.0.0.1:4473 $json" }
    if ($DryRun) { return }
    try {
        $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4473)
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
# The watch's screen is up: its screen dumped by QMP as a PNG, the Apple logo about 3.4 KB, the face 23-30 KB
function Face-Up($g) {
    $png = Join-Path $g.Dir 'screen.png'
    Remove-Item $png -ErrorAction SilentlyContinue
    Send-Qmp 'screendump' @{ filename = ($png -replace '\\', '/'); format = 'png' } -Quiet
    (Test-Path $png) -and (Get-Item $png).Length -gt 12000
}
# A watch running (its fixed ports listening) holds the files a disk or QEMU step replaces
function Need-NoWatch {
    if ($DryRun) { return }
    $busy = @(Get-NetTCPConnection -State Listen -LocalPort 4471, 4472, 4473 -ErrorAction SilentlyContinue)
    if ($busy) { Fail ("a watch is running (ports 4471-4473, pid {0}): close it first; it uses the files this step replaces" -f (($busy | ForEach-Object OwningProcess | Sort-Object -Unique) -join ', ')) }
}
function Guest([int]$wait, [string[]]$cmds, [switch]$NoFail) {
    Py 'guest-shell.py' (@('4471', "$wait") + $cmds) -NoFail:$NoFail
}
function Start-Watch([string]$name) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $here 'Start-watchOS.ps1'), '-Work', $Work, '-Name', $name, '-FirstBoot')
    Show-Cmd ('powershell ' + (($a | ForEach-Object { Q $_ }) -join ' '))
    if ($DryRun) { return @{ Pid = 0; Dir = (In-Watch "runs\$name"); Proc = $null } }
    # its own process with its output in a file: QEMU, which it starts and leaves running, must not
    # hold a pipe of ours open (as Install-iOS26.ps1's Start-Guest)
    $log = In-Work "install\logs\watch-launch-$name.txt"
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
# sync (unless -NoSync), QMP quit, then up to 120 s for QEMU to end before it is stopped (by its PID);
# true when the guest answered sync
function Stop-Watch($g, [switch]$NoSync) {
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
function Do-Check {
    # the iOS 26 install this builds on (its kernel: kc-watch.py --check below)
    $need = @('fw\sptm', 'fw\txm', 'dtree-smp4', 'rd-shell.hfs', 'downloads\ios_sysroot.tar.gz',
              'tools\qemu-sptm\scripts\darwin\vresearch_dt_fixup.py')
    $missing = @($need | Where-Object { -not (Test-Path (In-Work $_)) })
    if ($missing) {
        Stop-Here ("this has no iOS 26 base ($Work lacks $($missing -join ', ')): make it with Install-ASoftware.cmd -Version watchos " +
                   '(or install iOS 26), or give its folder with -Work')
    }
    # where its Linux steps ran: its linux step's marker has the mode it resolved (its config may say auto)
    $mode = Ios-Mark 'linux'
    if (-not $mode) { $mode = $LinuxMode }
    if ($mode -ceq 'helper') {
        Stop-Here 'the iOS 26 install ran its Linux steps in the helper VM; the watchOS installer needs WSL 2 (ios26\Install-iOS26.cmd -Linux wsl -Only linux sets it up)'
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
    # the watch face needs Metal: the GPU driver iOS 26's gpu step leaves in gpu-driver\ (or on its disk)
    if (((Ios-Mark 'gpu') -ceq 'gpuless' -or (Ios-Mark 'gpudriver') -ceq 'gpuless') -and -not (Test-Path (In-Work "gpu-driver\$GpuBundle"))) {
        Stop-Here ('iOS 26 was installed GPU-less, and the watch face needs its GPU driver (Metal): choose one in ' +
                   'ios26\Start-iOS26.cmd''s menu ([G]), run ios26\Install-iOS26.cmd again (it redoes its gpu step), then this')
    }
    Say "iOS 26 install: $Work; WSL distro $Distro, Linux scratch $LinuxDir"
    # the scripts the watch's steps run, in watchos\scripts (WSL reads them there; bash wants LF): this
    # version's iOS 26 scripts (root26-do.sh, mktc.py, root26-prefs.py, ...), not the iOS 26 install's,
    # which may be an older release's, then the watch's own
    $dst = In-Watch 'scripts'
    $from = @((Join-Path $repo 'ios26\scripts'), (Join-Path $here 'scripts'))
    foreach ($d in $from) { if (-not (Test-Path $d)) { Stop-Here "no $d (this installer comes with ios26\ and watchos\ beside each other)" } }
    Show-Cmd "copy ios26\scripts, watchos\scripts -> $dst (.sh with LF)"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force $dst, (In-Watch 'ipsw'), (In-Work 'install\logs') | Out-Null
        foreach ($f in @($from | ForEach-Object { Get-ChildItem $_ -File })) {
            $to = Join-Path $dst $f.Name
            if ($f.Extension -ceq '.sh') {
                $t = [IO.File]::ReadAllText($f.FullName) -replace "`r`n", "`n"
                [IO.File]::WriteAllText($to, $t, (New-Object System.Text.UTF8Encoding $false))
            } else { Copy-Item $f.FullName $to -Force }
        }
    }
    # the kernel the firmware step patches, before anything is downloaded
    if (-not (Get-Mark 'firmware') -or -not (Test-Path (In-Watch 'bootkc-w'))) {
        $null = Py 'kc-watch.py' (@('--check') + @($KernelIn | ForEach-Object { In-Work $_ })) -NoFail
        if ($script:Code) {
            if (-not (Test-Path (In-Work $KernelPacked))) {
                Stop-Here "the iOS 26 install has no plain cloudOS 26.4b research kernel (see above), nor $KernelPacked to decompress it from"
            }
            Say "the firmware step decompresses it again out of $KernelPacked"
        }
    }
}
function Qemu-HasWatch([string]$exe) {
    if (-not (Test-Path $exe)) { return $false }
    $ErrorActionPreference = 'Continue'
    $out = & $exe -device help 2>&1 | ForEach-Object { "$_" }
    $ErrorActionPreference = 'Stop'
    [bool]($out | Where-Object { $_ -cmatch '"usb-crown"' })
}
function Do-Qemu {
    $dst = In-Work 'qemu-watch'
    $exe = Join-Path $dst 'qemu-system-aarch64.exe'
    # (the probes only read: a dry run makes them too)
    $have = Qemu-HasWatch $exe
    if ($QemuFrom -ceq 'auto' -and $have) { Say "have $dst (it has usb-crown)"; return }
    if ($QemuFrom -cnotin 'auto', 'release') {
        $src = [IO.Path]::GetFullPath($QemuFrom).TrimEnd('\')
        # (Combine, not Join-Path, which throws on a drive that is not there)
        $srcExe = [IO.Path]::Combine($src, 'qemu-system-aarch64.exe')
        if (-not (Test-Path -LiteralPath $srcExe)) { Stop-Here "$src has no qemu-system-aarch64.exe"; return }
        # looked at before anything is copied: a QEMU without the watch's devices (iOS's) leaves qemu-watch\ be
        if (-not (Qemu-HasWatch $srcExe)) {
            if ($have) { Say "$src has no usb-crown device (it is not the watch build): $dst, which has one, stays" Yellow; return }
            Stop-Here "$src has no usb-crown device: it is not the watch build (qemu-sptm asoft-watch, win-build.sh's dist)"
            return
        }
        if ($src -ieq $dst.TrimEnd('\')) { Say "have $dst (it has usb-crown)"; return }
        Need-Space $Space.qemu
        Need-NoWatch
        Show-Cmd "copy $src -> $dst"
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force $dst | Out-Null
            # (/R /W: a file in use fails in seconds, not after robocopy's million retries)
            $null = Run 'robocopy.exe' @($src, $dst, '/E', '/R:2', '/W:2', '/NFL', '/NDL', '/NJH', '/NJS', '/NP') -NoFail -Quiet
            if ($script:Code -ge 8) { Fail "robocopy $src -> $dst failed ($($script:Code)): is a QEMU from $dst running?" }
        }
    } else {
        if (-not $QemuWatchRelease.Url) {
            Stop-Here ('the watch QEMU is not published as a package yet: give a build with -QemuFrom <folder> ' +
                       '(qemu-sptm asoft-watch, win-build.sh''s dist)')
            return
        }
        Need-Space $Space.qemu
        $zip = In-Work "downloads\asoft-qemu-watch-$($QemuWatchRelease.Version).zip"
        if (-not $DryRun) { New-Item -ItemType Directory -Force (Split-Path $zip) | Out-Null }
        $null = Run 'curl.exe' @('-fL', '--retry', '5', '-C', '-', '-o', $zip, $QemuWatchRelease.Url)
        if (-not $DryRun -and (Get-FileHash $zip -Algorithm SHA256).Hash -ne $QemuWatchRelease.Sha256) { Remove-Item $zip; Fail "${zip}: wrong SHA-256 (removed)" }
        Show-Cmd "unzip $zip -> $dst"
        if (-not $DryRun) { Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue; Expand-Archive $zip $dst -Force }
    }
    if (-not $DryRun -and -not (Qemu-HasWatch $exe)) { Fail "$exe has no usb-crown device: not the watch build (qemu-sptm asoft-watch)" }
}
# A file of -WatchDir's folders by its name, or $null
function Local-File([string]$name) {
    foreach ($d in $WatchDir) {
        # (a folder on a drive that is not there is skipped: Join-Path would throw)
        if (-not $d -or -not (Test-Path -LiteralPath $d -PathType Container)) { continue }
        $p = [IO.Path]::Combine($d, $name)
        if (Test-Path -LiteralPath $p -PathType Leaf) { return [IO.Path]::GetFullPath($p) }
    }
    $null
}
# The decrypted OS image is whole: the decrypt that made it finished (it leaves os\<image>.ok; an image
# without it is one a decrypt did not finish)
function Image-Ready { (Test-Path (In-Watch "os\$OsImage")) -and (Test-Path (In-Watch "os\$OsImage.ok")) }
function Do-Download {
    foreach ($m in $WatchFiles.Keys) {
        $name = [IO.Path]::GetFileName($m)
        $out = In-Watch "ipsw\$name"
        $ok = In-Work "install\got\watch-$name.ok"
        if ($m -ceq "$OsImage.aea" -and (Image-Ready)) { Say "have os\$OsImage (decrypted)"; continue }
        # the device tree may come unwrapped
        if ($name -ceq 'DeviceTree.n207sap.im4p' -and -not (Local-File $name) -and (Local-File 'DeviceTree.n207sap.raw')) {
            $name = 'DeviceTree.n207sap.raw'; $out = In-Watch "ipsw\$name"
        }
        $src = Local-File $name
        if ($src) {
            if (-not $DryRun -and (Test-Path $ok) -and (Test-Path $out) -and (Get-Item $out).Length -eq (Get-Item $src).Length) { Say "have $name"; continue }
            if ($m -ceq "$OsImage.aea") { Need-Space $Space.download }
            Show-Cmd "copy $src $out"
            if ($DryRun) { continue }
            New-Item -ItemType Directory -Force (Split-Path $out), (Split-Path $ok) | Out-Null
            # (its marker first: a copy cut short must not pass for a whole one)
            Remove-Item $ok -ErrorAction SilentlyContinue
            Copy-Item $src $out -Force
            if ($m -ceq "$OsImage.aea") {
                Say 'checking its SHA-1'
                $h = (Get-FileHash $out -Algorithm SHA1).Hash
                if ($h -ne $OsAeaSha1) { Remove-Item $out; Fail "$src has SHA-1 $h, not $OsAeaSha1 (the 27.2 24S118 Watch7,1 OS image)" }
            }
            Set-Content $ok $m
            continue
        }
        if ($m -ceq "$OsImage.aea") { Need-Space $Space.download }
        Get-IpswMember $m $out $WatchFiles[$m]
    }
}
function Do-Decrypt {
    if (-not $DryRun -and (Image-Ready)) { Say "have os\$OsImage" ; return }
    # the .aea whole first: the download step's checks pass a whole one, fetch it again when a decrypt
    # took it away, and go on with one a fetch did not finish (a cut-short fetch leaves a full-size file)
    if (-not $DryRun) { Do-Download }
    Need-Space $Space.decrypt
    $body = Step-Body 'decrypt'
    $null = Run-Wsl 'decrypt' $body.Replace('{OS}', $OsImage)
    # read decrypted from now on (the .aea goes with its download marker and chunk list)
    if (-not $KeepBuildFiles -and -not $DryRun) {
        Show-Cmd "del watchos\ipsw\$OsImage.aea"
        Remove-Item (In-Work "install\got\watch-$OsImage.aea.ok"), (In-Watch "ipsw\$OsImage.aea.done"), (In-Watch "ipsw\$OsImage.aea") -ErrorAction SilentlyContinue
    }
}
function Do-Firmware {
    # the kernel: cloudOS 26.4b's research kernel as the iOS 26 install has it, plain (kc-watch.py takes
    # the first of $KernelIn that is; else it is decompressed again out of $KernelPacked)
    $in = @($KernelIn | ForEach-Object { In-Work $_ })
    $null = Py 'kc-watch.py' (@('--check') + $in) -NoFail
    if ($script:Code) {
        $body = Step-Body 'kernel'
        $null = Run-Wsl 'kernel' $body.Replace('{PACKED}', ($KernelPacked -replace '\\', '/'))
        $in += In-Watch 'build\kc\kernel'
    }
    $null = Py 'kc-watch.py' (@((In-Watch 'bootkc-w')) + $in)
    # the device trees: the iOS 26 install's dtree-smp4 (and dtree-smp8) with the Series 9's identity
    if ($DryRun -or (Test-Path (In-Watch 'ipsw\DeviceTree.n207sap.im4p'))) {
        $body = Step-Body 'devicetree'
        $null = Run-Wsl 'devicetree' $body
    }
    $qs = In-Work 'tools\qemu-sptm'
    Show-Cmd "QEMU_SPTM=$qs"
    $env:QEMU_SPTM = $qs
    $null = Py 'dt-watch.py' @((In-Work 'dtree-smp4'), (In-Watch 'ipsw\DeviceTree.n207sap.raw'), (In-Watch 'dtree-w'))
    # (Start-watchOS.cmd -Smp 8)
    if ($DryRun -or (Test-Path (In-Work 'dtree-smp8'))) {
        $null = Py 'dt-watch.py' @((In-Work 'dtree-smp8'), (In-Watch 'ipsw\DeviceTree.n207sap.raw'), (In-Watch 'dtree-w8'))
    }
}
function Do-Gpu {
    # the guest GPU driver, kept in <Work>\gpu-driver for every guest (Install-iOS26.ps1 keeps it there
    # since its gpu step does; an older iOS 26 install has it only on its disk: copied off it, read only)
    $shared = In-Work "gpu-driver\$GpuBundle"
    if ($DryRun -or -not (Test-Path $shared)) {
        $top = @('root.qcow2', 'root26-gpu.qcow2') | Where-Object { $DryRun -or (Test-Path (In-Work $_)) } | Select-Object -First 1
        if (-not $top) { Fail "no $shared and no iOS 26 disk with the GPU driver (root.qcow2): is iOS 26 GPU-less? Then the watch cannot draw (ClockFace needs Metal)" }
        # (copied under another name and renamed: an interrupted copy never looks like the driver)
        $body = Step-Body 'gpu-driver'
        $null = Run-Wsl 'gpu-driver' $body.Replace('{TOP}', $top).Replace('{BUNDLE}', $GpuBundle)
    } else { Say "have gpu-driver\$GpuBundle" }
    # the watch's copy in watchos\gpu (the cleanup keeps it: the patches step copies it onto the disk, the
    # trust cache takes its hashes.txt): both Mach-Os retargeted to watchOS (dyld refuses an iOS one) and
    # ad-hoc signed
    $body = Step-Body 'gpu'
    $null = Run-Wsl 'gpu' $body.Replace('{BUNDLE}', $GpuBundle)
}
# What the gpu step leaves (made again when it is missing: a step after it needs it)
function Need-Gpu {
    if ($DryRun -or ((Test-Path (In-Watch "gpu\$GpuBundle")) -and (Test-Path (In-Watch 'gpu\hashes.txt')))) { return }
    Say 'no watchos\gpu (the watch''s copy of the GPU driver): the gpu step again' Yellow
    Do-Gpu
}
# The watch's disk (watch.qcow2, an overlay on rootw-p.qcow2 on rootw.qcow2) before a step replaces it or
# a layer under it: a disk the install finished (watch.qcow2.ready) is kept as watch.qcow2.old, with what
# the watch wrote (on the old layers: mountable with them only), one the install did not finish goes
function Retire-Watch {
    $disk = In-Watch 'watch.qcow2'
    $ready = In-Watch 'watch.qcow2.ready'
    if (-not (Test-Path $disk)) { Remove-Item $ready -ErrorAction SilentlyContinue; return }
    Need-NoWatch
    if (Test-Path $ready) {
        Say 'watchos\watch.qcow2, the watch''s disk, rests on what this step replaces: kept as watchos\watch.qcow2.old (a new one starts afresh)' Yellow
        if (-not $DryRun) { Move-Item $disk "$disk.old" -Force; Remove-Item $ready -Force }
    } else {
        Show-Cmd 'del watchos\watch.qcow2   (an unfinished install''s)'
        if (-not $DryRun) { Remove-Item $disk -Force }
    }
}
function Do-Rootfs {
    # a root built before goes first, with the patch layer on it (the chain after this step is redone),
    # which also makes the room the image needs (so a redo peaks where the first build did)
    Retire-Watch
    foreach ($f in 'rootw-p.qcow2', 'rootw-p.hashes', 'rootw.qcow2', 'rootw.qcow2.hashes') {
        if ($DryRun -or (Test-Path (In-Watch $f))) { Show-Cmd "del watchos\$f"; if (-not $DryRun) { Remove-Item (In-Watch $f) -Force } }
    }
    # the decrypted image is removed once a root is built from it: redone later, this step fetches
    # (from -WatchDir, the IPSW or Apple) and decrypts it again (as a decrypt that did not finish)
    if (-not $DryRun -and -not (Image-Ready)) {
        Say "no whole watchos\os\$OsImage (a root was built from it before, or its decrypt stopped): getting it again" Yellow
        Do-Decrypt
    }
    Need-Space $Space.rootfs
    $body = Step-Body 'rootfs'
    $null = Run-Wsl 'rootfs' $body.Replace('{OS}', $OsImage)
    # the image is on the disk now
    if (-not $KeepBuildFiles -and -not $DryRun) {
        Show-Cmd "del watchos\os\$OsImage"
        Remove-Item (In-Watch "os\$OsImage.ok"), (In-Watch "os\$OsImage") -ErrorAction SilentlyContinue
    }
}
# What an earlier step left (watchos\<rel>), else stop and say which step makes it
function Need-Input([string]$rel, [string]$step) {
    if (-not $DryRun -and -not (Test-Path (In-Watch $rel))) { Fail "no watchos\${rel}: the $step step makes it (run -From $step)" }
}
function Do-Patches {
    # on an overlay made anew each time (rootw.qcow2 stays as mk-rootw.sh built it), so this step can be
    # redone: the shared-cache patches find their stock bytes only once
    Need-Input 'rootw.qcow2' 'rootfs'
    Need-Input 'rootw.qcow2.hashes' 'rootfs'
    Need-Gpu
    Need-Space $Space.patches
    Retire-Watch
    $body = Step-Body 'patches'
    $null = Run-Wsl 'patches' $body.Replace('{BUNDLE}', $GpuBundle)
}
function Do-TrustCache {
    # Apple's, the signed sysroot (rootfs), the patched subcaches (patches) and the GPU driver as the
    # patches step put it on the disk (its hashes.txt): each list from the step that makes it
    $in = [ordered]@{ "ipsw\$OsImage.aea.trustcache" = 'download'; 'rootw.qcow2.hashes' = 'rootfs'
                      'rootw-p.hashes' = 'patches'; 'gpu\hashes.txt' = 'patches' }
    foreach ($f in $in.Keys) { Need-Input $f $in[$f] }
    $null = Py 'mktc.py' (@('-2', (In-Watch 'rootw.tc')) + @($in.Keys | ForEach-Object { In-Watch $_ }))
}
function Do-FirstBoot {
    # once, until the watch face is up. On the way mobileactivationd makes its system container (the
    # activation step seeds it); DataMigration and the face's first start (ClockFace, NanoTimeKit's
    # complication migration) keep the Apple logo up until they are done: 14 min here, after which a start
    # takes 6. A first boot stopped before the face leaves that to the user's first start.
    Need-Input 'rootw-p.qcow2' 'patches'
    Need-Input 'rootw.tc' 'trustcache'
    Retire-Watch
    $null = Run-Wsl 'overlay' 'overlay rootw-p.qcow2 watchos/watch.qcow2'
    Need-Space $Space.firstboot
    $g = Start-Watch 'install-firstboot'
    try {
        # mobileactivationd's data ark in its system container: the containers' metadata is closed to the
        # guest's shell (Operation not permitted), the ark is not. Coreutils and bash only (the guest has no
        # grep); no double quotes (Windows PowerShell 5.1 passes them to python unescaped)
        $test = 'ls /private/var/containers/Data/System/*/Library/internal/data_ark.plist > /dev/null 2>&1 && echo __READY__ || echo __WAIT__'
        Say 'waiting for mobileactivationd''s data ark, then the watch face (up to 45 min; on our PC 1 and 14 min)'
        if (-not $DryRun) {
            $t0 = Get-Date
            $ark = $false
            while ($true) {
                if (-not (Guest-Alive $g)) { Fail "QEMU ended during the first boot; see $($g.Dir)" }
                $min = ((Get-Date) - $t0).TotalMinutes
                Emit 'pct', 'watch', 'firstboot', ([int][Math]::Min(95, 100 * $min / 15)), $(if ($ark) { 'waiting for the watch face' } else { 'waiting for the data ark' })
                if (-not $ark) {
                    $out = Guest 90 @($test) -NoFail
                    if (@($out | Where-Object { "$_".Trim() -ceq '__READY__' }).Count) {
                        $ark = $true
                        Say ("the data ark after {0:N0} min; now the face" -f $min)
                    }
                }
                if ($ark -and (Face-Up $g)) { Say ("the watch face after {0:N0} min ($($g.Dir)\screen.png)" -f $min); break }
                if ($min -gt 45) {
                    if (-not $ark) { Fail "no mobileactivationd data ark after 45 min; see $($g.Dir)\serial.log" }
                    Say 'no watch face after 45 min: the first start goes on with what this boot did not finish' Yellow
                    break
                }
                Start-Sleep -Seconds 20
            }
            # (what the face's first start writes)
            Start-Sleep -Seconds 60
        }
        if (-not (Stop-Watch $g)) { Fail 'the guest did not answer sync; run again to redo the first boot' }
    } catch {
        if (-not $DryRun -and (Guest-Alive $g)) { $null = Stop-Watch $g -NoSync }
        throw
    }
}
function Do-Activation {
    # (root26-prefs.py only warns when it finds no mobileactivationd container, with "data ark skipped":
    # here that is a failure; its success line is "data ark <the container's Library/internal>")
    Need-Input 'watch.qcow2' 'firstboot'
    # (it mounts watch.qcow2 read-write: never under a running watch)
    Need-NoWatch
    $body = Step-Body 'activation'
    $null = Run-Wsl 'activation' $body
    # the disk is the watch's now: a later redo keeps it (Retire-Watch); the launcher starts only it
    if (-not $DryRun) { Set-Content (In-Watch 'watch.qcow2.ready') (Get-Date -Format s) }
}
function Do-Cleanup {
    if ($KeepBuildFiles) { Say '-KeepBuildFiles: the decrypted image and the build''s leftovers stay' DarkGray; return }
    # (watchos\gpu and the hash lists stay: a later redo of the disk steps reads them)
    $gone = @('watchos\os', 'watchos\build', "watchos\ipsw\$OsImage.aea", 'watchos\tmp')
    foreach ($rel in $gone) {
        if (-not (Test-Path (In-Work $rel))) { continue }
        Show-Cmd "del $rel"
        if ($DryRun) { continue }
        try { Remove-Item (In-Work $rel) -Recurse -Force }
        catch {
            # a running watch's temporary files (Start-watchOS.ps1's TEMP; -Snapshot's disk)
            if ($rel -cne 'watchos\tmp') { throw }
            Say 'watchos\tmp is in use (a watch is running): left' DarkGray
        }
    }
}
function Do-Shortcut {
    $cmd = Join-Path $repo 'Start-watchOS.cmd'
    Say "start it with $cmd"
    if ($NoShortcut -or $DryRun) { return }
    try {
        $dir = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\ASoftware'
        New-Item -ItemType Directory -Force $dir | Out-Null
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $dir 'ASoftware watchOS.lnk'))
        $s.TargetPath = $cmd
        $s.Arguments = "-Work `"$Work`""
        $s.WorkingDirectory = $repo
        $s.Save()
        Say "Start menu: ASoftware\ASoftware watchOS"
    } catch {
        Say "no Start menu shortcut ($($_.Exception.Message)): start it with $cmd" Yellow
    }
}

$Steps = @(
    @{ Id = 'check';      Kind = 'always'; Title = 'The iOS 26 install it builds on, WSL, the scripts' }
    @{ Id = 'qemu';       Kind = 'once';   Title = 'The watch QEMU (qemu-watch\)' }
    @{ Id = 'download';   Kind = 'once';   Title = 'watchOS 27.2 files (Apple, about 5 GB)' }
    @{ Id = 'decrypt';    Kind = 'once';   Title = 'Decrypt the OS image' }
    @{ Id = 'firmware';   Kind = 'once';   Title = 'The watch kernel and device tree' }
    @{ Id = 'gpu';        Kind = 'once';   Title = 'The guest GPU driver for watchOS' }
    @{ Id = 'rootfs';     Kind = 'chain';  Title = 'The root disk (watchos\rootw.qcow2)' }
    @{ Id = 'patches';    Kind = 'chain';  Title = 'Shared-cache patches, prefs, apps and the GPU driver on it' }
    @{ Id = 'trustcache'; Kind = 'chain';  Title = 'Its trust cache (watchos\rootw.tc)' }
    @{ Id = 'firstboot';  Kind = 'chain';  Title = 'First boot (watchos\watch.qcow2)' }
    @{ Id = 'activation'; Kind = 'chain';  Title = 'Activation' }
    @{ Id = 'cleanup';    Kind = 'always'; Title = 'Remove what only the build needs' }
    @{ Id = 'shortcut';   Kind = 'always'; Title = 'Start-watchOS.cmd and the Start menu shortcut' }
)
$ids = @($Steps | ForEach-Object { $_.Id })
foreach ($s in @($From, $Only)) { if ($s -and $ids -cnotcontains $s) { throw "no step $s (the steps: $($ids -join ', '))" } }
function Invoke-Step([string]$id) {
    switch -CaseSensitive ($id) {
        'check' { Do-Check } 'qemu' { Do-Qemu } 'download' { Do-Download } 'decrypt' { Do-Decrypt }
        'firmware' { Do-Firmware } 'gpu' { Do-Gpu } 'rootfs' { Do-Rootfs } 'patches' { Do-Patches }
        'trustcache' { Do-TrustCache } 'firstboot' { Do-FirstBoot } 'activation' { Do-Activation }
        'cleanup' { Do-Cleanup } 'shortcut' { Do-Shortcut }
    }
}

# --- The iOS 26 install's settings ---------------------------------------------------------------
$cfg = $null
if (Test-Path $Config) { try { $cfg = Get-Content $Config -Raw | ConvertFrom-Json } catch { } }
if (-not $Work -and $cfg) { $Work = [string]$cfg.Work }
if (-not $Work) { throw "no iOS 26 install found ($Config has no work folder): install iOS 26 first, or give -Work" }
$Work = [IO.Path]::GetFullPath($Work).TrimEnd('\')
$Distro = if ($cfg -and $cfg.Distro) { [string]$cfg.Distro } else { 'ios-emu' }
$LinuxDir = if ($cfg -and $cfg.Linux) { [string]$cfg.Linux } else { '/root/ios26' }
$LinuxMode = if ($cfg -and $cfg.LinuxMode) { [string]$cfg.LinuxMode } else { 'wsl' }
$Py = Join-Path $Work 'tools\python\python.exe'
if (-not (Test-Path $Py)) { $Py = (Get-Command python.exe -ErrorAction SilentlyContinue).Source }
if (-not $Py) { $Py = 'python.exe' }

if ($List) {
    foreach ($s in $Steps) {
        $m = if ($s.Kind -ceq 'always') { 'every run' } elseif (Get-Mark $s.Id) { 'done' } else { '-' }
        Say ("{0,-11} {1,-10} {2}" -f $s.Id, $m, $s.Title)
    }
    exit 0
}

# --- Run -----------------------------------------------------------------------------------------
Write-Host "ASoftware watchOS installer$(if ($DryRun) { ' (dry run: nothing is run)' })" -ForegroundColor Cyan
Write-Host "  Work $Work (WSL: $(To-Wsl $Work)), WSL distro $Distro, Linux scratch $LinuxDir"
$fromIdx = if ($From) { [array]::IndexOf($ids, $From) } else { -1 }
$chainRedone = $false
for ($i = 0; $i -lt $Steps.Count; $i++) {
    $s = $Steps[$i]
    $forced = ($From -and $i -ge $fromIdx) -or ($Only -ceq $s.Id)
    $label = "{0}/{1} {2}: {3}" -f ($i + 1), $Steps.Count, $s.Id, $s.Title
    if ($s.Kind -cne 'always' -and -not $forced) {
        if ($Only -or ($From -and $i -lt $fromIdx)) { continue }
        if ((Get-Mark $s.Id) -ceq (Step-Sig $s.Id) -and -not ($s.Kind -ceq 'chain' -and $chainRedone)) {
            Write-Host "== $label  [done]" -ForegroundColor DarkGray
            Emit 'step', 'watch', ($i + 1), $Steps.Count, $s.Id, 'skip', $s.Title
            continue
        }
    }
    if ($Only -and $s.Kind -ceq 'always' -and $Only -cne $s.Id -and $s.Id -cne 'check') { continue }
    if (-not $DryRun -and (Pause-Requested)) {
        Emit 'paused', 'watch', $s.Id
        Write-Host ''
        Write-Host "Paused before step $($s.Id) (ASoftware.exe). Run this again to go on from it." -ForegroundColor Yellow
        exit 5
    }
    Step $label
    Emit 'step', 'watch', ($i + 1), $Steps.Count, $s.Id, 'start', $s.Title
    $script:Log = $null
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force (In-Work 'install\logs') | Out-Null
        $script:Log = In-Work "install\logs\watch-$($s.Id).log"
        Add-Content $script:Log ("`n=== {0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $label)
    }
    try {
        if ($s.Kind -ceq 'chain') {
            $chainRedone = $true
            for ($j = $i + 1; $j -lt $Steps.Count; $j++) {
                if ($Steps[$j].Kind -ceq 'chain' -and -not $DryRun) { Clear-Mark $Steps[$j].Id }
            }
        }
        # its own marker too: a redone step that fails (what it replaces may be gone) is redone next time
        if ($s.Kind -cne 'always' -and -not $DryRun) { Clear-Mark $s.Id }
        Invoke-Step $s.Id
    } catch {
        Write-Host ''
        Write-Host "Step $($s.Id) failed: $($_.Exception.Message)" -ForegroundColor Red
        if ($script:Log) { Write-Host "  log: $script:Log" }
        Write-Host ("  Fix the cause and run Install-ASoftware.cmd (or watchos\Install-watchOS.cmd) again: it goes on " +
                    "from this step (Install-watchOS.cmd -Only $($s.Id) redoes just this one).") -ForegroundColor Yellow
        Emit 'step', 'watch', ($i + 1), $Steps.Count, $s.Id, 'fail', $_.Exception.Message
        Emit 'end', 'watch', 1
        exit 1
    }
    if ($s.Kind -cne 'always' -and -not $DryRun) { Set-Mark $s.Id (Step-Sig $s.Id) }
    Emit 'step', 'watch', ($i + 1), $Steps.Count, $s.Id, 'done', $s.Title
}
Emit 'end', 'watch', 0
Write-Host ''
if ($DryRun) { Write-Host 'Dry run: nothing was run.' -ForegroundColor Cyan }
elseif ($Only) { Write-Host "Done: $Only." -ForegroundColor Cyan }
else { Write-Host 'Done. Start watchOS with Start-watchOS.cmd or the Start menu shortcut.' -ForegroundColor Cyan }

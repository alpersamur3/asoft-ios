# ASoftware tvOS installer: tvOS 27.2 (24K122) as an Apple TV 4K (3rd generation, AppleTV14,1, J255) on
# -M vresearch, built on this PC's iOS 26 install or only its base (Install-iOS26.ps1's work folder; its -Base is
# enough). From it: cloudOS 26.4b's research kernel (which visionOS's kc-vision.py patches; the same bytes as
# visionos\bootkc-v, which is taken when visionOS is installed), SPTM, TXM, the device trees (dtree-smp4/8 and
# fw\dtree.orig, which dt-tv.py gives J255's identity), the shell ramdisk, darwin-vm's sysroot, the guest GPU driver
# and the WSL distro. The scripts come with this installer (ios26\scripts, two of watchos\scripts, visionos's
# kc-vision.py and tvos\scripts, copied into work\tvos\scripts).
# Apple publishes no tvOS 27 IPSW for any Apple TV 4K: it reads Apple's full OTA (4.97 GB, AEA, pinned by URL, size,
# SHA-256 and key) and builds the root out of it. OS 27's payload is pbzm (LZRAVEN), which ipsw cannot decode off
# macOS 27: liblzraven (0BSD, a clean-room decoder, pinned to one commit) is built from source in WSL, and
# tvx.py unpacks the payload into an ext4 image on the work drive, whose code signatures vsig.py checks.
# It needs our QEMU with visionOS's options in <work>\qemu (the build tvOS was measured on), the one QEMU every guest
# runs on: the qemu step puts it there when the install's is older.
# One disk runs at 4K (3840x2160) and at 1080p: its QuartzCore takes a display mode's scale as a real Apple TV does
# (dsc-qcscale.py, the patches step), and each mode has its own device trees (dtree-t*, dtree-t*-1080), which
# Start-tvOS.ps1 -Resolution picks.
# Everything goes into <Work>\tvos (about 12.7 GB when done; the build peaks near 23 GB, when the root disk is
# built from the unpacked root), and leaves a marker per step in <Work>\install\tv-*.done, so running it again goes
# on where it stopped.
#
#   tvos\Install-tvOS.cmd [-Work D:\ios26] [-List] [-Estimate] [-DryRun] [-From STEP | -Only STEP] ...
#     -QemuDir FOLDER     a QEMU package (win-build.sh's dist) to put in <work>\qemu when the one there lacks the
#                         options; else the release package asoft-setup.json names (os.tvos, else os.visionos)
#     -OtaFile FILE       the OTA (.aea) on this PC (checked by its size and SHA-256), read where it is: nothing is
#                         downloaded, and it is never removed
#     -CdnEdge IP[,IP]    Apple CDN edges (17.253.x.x) for the OTA, where this network's DNS answer is slow; TLS
#                         still checks the host name
#     -KeepBuildFiles     keep the OTA, its decrypted archive and the unpacked root's image
#     -Estimate           the time, download and disk space of what is left to do, then stop
# The Linux steps run in the iOS 26 install's WSL distro (its -Linux helper mode is not supported here).
# Redoing a disk step (-From/-Only rootfs ... disks) after a finished install keeps the user disk as
# tvos\tv.qcow2.old (an earlier .old stays: .old2, .old3, ...): the new one starts afresh.
param(
    [string]$Work = '',
    [string]$Config = (Join-Path $env:LOCALAPPDATA 'ASoftware iOS 26\ios26.config.json'),
    [string]$QemuDir = '',
    [string]$OtaFile = '',
    [string]$CdnEdge = '',
    [string]$From = '',
    [string]$Only = '',
    [switch]$DryRun,
    [switch]$List,
    [switch]$Estimate,
    [switch]$KeepBuildFiles,
    [switch]$NoShortcut
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = Split-Path $here

# --- What it reads from Apple, pinned --------------------------------------------------------------
# Apple's full OTA of tvOS 27.2 (24K122) for AppleTV14,1 (J255AP), from Pallas (release audience, PublicAssetSets
# 2026-10-26, expiring there 2027-02-06; the CDN file stays as long as Apple keeps it). AEA: its key is the one
# Pallas and AppleDB give for it. Decrypted it is an Apple Archive (AA01) of DecSize bytes.
$OtaUrl = 'https://updates.cdn-apple.com/2026FallFCS/372ccebe-e288-46c1-b427-e36c5103d7f9/com_apple_MobileAsset_SoftwareUpdate/ec0f05584a1d84bb0275ce419a24ee68c55f5c3d39b40239e6c24ec882a8caaf.aea'
$OtaName = 'AppleTV14,1_27.2_24K122_full-OTA.aea'
$OtaSize = 4966055936
$OtaSha256 = 'b436615ce265a597cdaf2d78ff9b09acb54dced24b9e13bb14fb304845f85c9c'
$OtaKey = 'gUokX0RHox/zA24cgD4XNGmQuBZ92IRwnuROdnmk91c='
$DecSize = 4986563871
# its boot files the build reads (ipsw ota extract): the OS root's trust cache (1623 entries), J255's device tree
# (unwrapped: SHA-256 pinned), the build manifest (24K122, AppleTV14,1)
$OsTrustCache = '141-10510-176.dmg.trustcache'
$TcEntries = 1623
$BootPattern = '^AssetData/boot/(BuildManifest\.plist|Firmware/141-10510-176\.dmg\.trustcache|Firmware/all_flash/DeviceTree\.j255ap\.im4p)$'
$J255Sha = '34c1283d1d7ba9e1e00c998282edc39588b9a630089e90b6a01b19a2037432d2'
# signed files of the unpacked root not in the OS trust cache (vsig.py on the hand-built tree: 8 kexts, whose code
# is in the kernel cache); more is another root
$NotInTc = 8
# liblzraven, the LZRAVEN decoder (0BSD), at the commit the hand build used (2026-07-30), fetched by its id
$LzRaven = @{ Repo = 'https://github.com/anat0m1a/liblzraven'; Commit = '700b88c4b2e1b1d96e499d172dfa0b8e5d9134ab' }
$GpuBundle = 'AppleParavirtGPUMetalIOGPUFamily.bundle'
# the kernel: visionOS's (kc-vision.py's result, the hand-built bootkc-ty byte for byte: cloudOS 26.4b's research
# kernel with iOS 27's patches, the IOGPU timeouts and the sandbox syscall filters off). Taken from visionos\ when
# visionOS is installed, else made from the base's plain kernel, else decompressed again out of cloudos\
$KernelIn = @('visionos\bootkc-v', 'cloud\kernelcache.research.vphone600.decompressed', 'fw\bootkc')
$KernelPacked = 'cloudos\kernelcache.research.vphone600'
# the device trees dt-tv.py makes from the base's (iOS 26 0.3.0's dtree-smp4/8, fw\dtree.orig; the same properties
# as the hand-built dtree-t, in a fixed order), and their 1080p siblings dt-res.py makes (the same properties as the
# hand-built dtree-t-1080): another base gives other bytes, which is said, not refused
$TreeSha = @{ 'dtree-t'       = 'ba5e4bfe54bbe080bf2c58c4a606b23968dce311f0e151dd3453b28a95c58f1d'
              'dtree-t6'      = '04e6b2ef6c1843e391eb51f368265ab28e486bc086a75e89fa014b48b7c6fee5'
              'dtree-t8'      = 'f47825e781d6add815275a3f8220ec03a2585429709f52b1c7e3c530207d7cd5'
              'dtree-t-1080'  = '932ec7ea624720139dfafda9286d5aa9316105a8c3cf0dcc865f2bf1a4d0333b'
              'dtree-t6-1080' = '971ce5ded69fee5a139d066a283d0e2944a6bfa5c8117bbc62428614aac4c522'
              'dtree-t8-1080' = '9ed63b5684f703166b8556b1026c36ee0089ef141fd79d04efafdc4ba3efd44e' }
# the unpacked root's ext4 image: sparse, this big at most (about 13 GB of it is used)
$RootImageGiB = 20
# tvOS's ports (serial console, HMP, QMP): iOS 26 4451-4453, iOS 27 4461-4463, watchOS 4471-4473, visionOS 4481-4483
$TvPorts = @(4501, 4502, 4503)
# GB a step adds on the work folder's drive at most
$Space = @{ qemu = 0.6; download = 5.0; decrypt = 5.1; unpack = 14.0; rootfs = 11.0; patches = 1.0; firstboot = 1.5; homeboot = 0.5; disks = 0.1 }

# --- Output, running tools (as Install-visionOS.ps1) -------------------------------------------------
function Step([string]$text) { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }
# Progress for ASoftware.exe, which sets ASOFT_PROGRESS=1: ##asoft|kind|field|..., one line each
# (step|tv|N|OF|ID|start|TITLE, step|...|done/skip/fail, pct|tv|ID|0-100|TEXT, paused|tv|ID, end|tv|CODE)
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
        # (Windows PowerShell 5.1 turns a native tool's stderr into errors: here they are just lines)
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
# (the scripts the check step copies into tvos\scripts)
function Py([string]$script, [string[]]$argv, [switch]$NoFail) {
    Run $Py (@('-I', '-B', (In-Tv "scripts\$script")) + $argv) -NoFail:$NoFail
}
function To-Wsl([string]$p) {
    $f = [IO.Path]::GetFullPath($p)
    '/mnt/' + $f.Substring(0, 1).ToLowerInvariant() + ($f.Substring(2) -replace '\\', '/')
}
function In-Work([string]$rel) { Join-Path $Work $rel }
function In-Tv([string]$rel) { Join-Path (Join-Path $Work 'tvos') $rel }
function Free-GB { ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($Work))).AvailableFreeSpace / 1e9 }
function Need-Space([double]$gb) {
    if ($gb -le 0) { return }
    if ($DryRun) { Say ("needs about {0:N1} GB free on {1}" -f $gb, [IO.Path]::GetPathRoot($Work)) DarkGray; return }
    $free = Free-GB
    if ($free -lt $gb + 1) {
        Fail ("{0:N1} GB free on {1}; this step needs about {2:N0} GB: free some space" -f $free, [IO.Path]::GetPathRoot($Work), ($gb + 1))
    }
}
function Sha256([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }

# A bash script for WSL, as Install-visionOS.ps1's (its prelude: the folders, disk_tools, in_root, overlay)
function Prelude([string]$name) {
    $p = @'
#!/bin/bash
# Install-tvOS.ps1, {NAME}: written by the installer, run as root in WSL ({DISTRO})
set -euo pipefail
export ASOFT26={A} ASOFT26_LINUX={L}
A=$ASOFT26 L=$ASOFT26_LINUX S=$ASOFT26/tvos/scripts W=$ASOFT26/tvos
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
    $file = In-Work "install\sh\tv-$name.sh"
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
# A file on the work drive with no room taken by what was never written (NTFS sparse): the unpacked root's ext4
# image, which WSL fills through a loop mount. The flag goes on before anything is written (set later, the zeros
# mkfs and the loop device write would take their room).
function New-SparseFile([string]$path, [long]$bytes) {
    Show-Cmd ("new sparse file {0} ({1:N0} GiB at most)" -f $path, ($bytes / 1GB))
    if ($DryRun) { return }
    if (-not ('ASoft.TvSparse' -as [type])) {
        Add-Type -Namespace ASoft -Name TvSparse -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool DeviceIoControl(Microsoft.Win32.SafeHandles.SafeFileHandle h, uint code, IntPtr inBuf, uint inSize, IntPtr outBuf, uint outSize, out uint returned, IntPtr overlapped);
'@
    }
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    $fs = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $n = [uint32]0
        # FSCTL_SET_SPARSE
        if (-not [ASoft.TvSparse]::DeviceIoControl($fs.SafeFileHandle, [uint32]0x000900C4, [IntPtr]::Zero, 0, [IntPtr]::Zero, 0, [ref]$n, [IntPtr]::Zero)) {
            Fail "$path cannot be made sparse (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())): the work drive must be NTFS"
        }
        $fs.SetLength($bytes)
    } finally { $fs.Close() }
}

# --- Markers -----------------------------------------------------------------------------------
function Mark-File([string]$id) { In-Work "install\tv-$id.done" }
function Get-Mark([string]$id) { $f = Mark-File $id; if (Test-Path $f) { (Get-Content $f -Raw).Trim() } else { $null } }
function Set-Mark([string]$id, [string]$sig) { Set-Content -Path (Mark-File $id) -Value $sig -Encoding UTF8 }
function Clear-Mark([string]$id) { Remove-Item (Mark-File $id) -ErrorAction SilentlyContinue }
function Step-Sig([string]$id) { 'done' }

# --- The guest (the install's two boots) ---------------------------------------------------------
# A QMP command (its arguments a hashtable); -Quiet: neither the command nor a failure is printed
function Send-Qmp([string]$command, [hashtable]$arguments = $null, [switch]$Quiet) {
    $json = if ($arguments) { (@{ execute = $command; arguments = $arguments } | ConvertTo-Json -Compress -Depth 4) } else { "{`"execute`":`"$command`"}" }
    if (-not $Quiet) { Show-Cmd "QMP 127.0.0.1:$($TvPorts[2]) $json" }
    if ($DryRun) { return }
    try {
        $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $TvPorts[2])
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
            for ($k = 0; $k -lt 20; $k++) { $l = $reader.ReadLine(); if ($null -eq $l -or $l -cmatch '"(return|error)"') { break } }
        } finally { $client.Close() }
    } catch { if (-not $Quiet) { Say "QMP: $($_.Exception.Message)" Yellow } }
}
# The size of the guest's screen dumped by QMP as a PNG. At 3840x2160 (the install's boots) the boot screens (black,
# then the Apple logo) dump to 24-49 KB, Home with its rows of app artwork to 288-299 KB (measured on two boots of
# the hand-built disk, 2026-11-12): Home is a dump over 150 KB
function Screen-Bytes($g, [string]$shot) {
    $png = Join-Path $g.Dir "$shot.png"
    Remove-Item $png -ErrorAction SilentlyContinue
    Send-Qmp 'screendump' @{ filename = ($png -replace '\\', '/'); format = 'png' } -Quiet
    if (Test-Path $png) { (Get-Item $png).Length } else { 0 }
}
$HomeBytes = 150000
# A tvOS guest running (its fixed ports listening) holds the files a disk or QEMU step replaces
function Need-NoTv {
    if ($DryRun) { return }
    $busy = @(Get-NetTCPConnection -State Listen -LocalPort $TvPorts -ErrorAction SilentlyContinue)
    if ($busy) { Fail ("tvOS is running (ports {0}-{1}, pid {2}): close it first; it uses the files this step replaces" -f $TvPorts[0], $TvPorts[2], (($busy | ForEach-Object OwningProcess | Sort-Object -Unique) -join ', ')) }
}
function Guest([int]$wait, [string[]]$cmds, [switch]$NoFail) {
    Py 'guest-shell.py' (@("$($TvPorts[0])", "$wait") + $cmds) -NoFail:$NoFail
}
# Start-tvOS.ps1 on the install's disk, 4 vCPUs, its own window, at 2160p: the mode the hand-built disk's first boots
# ran in (its 1080p starts were on such a disk) and $HomeBytes is measured for
function Start-Tv([string]$runName) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $here 'Start-tvOS.ps1'), '-Work', $Work,
           '-Name', $runName, '-Disk', 'tvos\roott-b.qcow2', '-Cpus', '4', '-Resolution', '2160')
    Show-Cmd ('powershell ' + (($a | ForEach-Object { Q $_ }) -join ' '))
    if ($DryRun) { return @{ Pid = 0; Dir = (In-Tv "runs\$runName"); Proc = $null } }
    # its own process with its output in a file: QEMU, which it starts and leaves running, must not hold a pipe
    # of ours open (as Install-iOS26.ps1's Start-Guest)
    $out = In-Work "install\logs\tv-launch-$runName.txt"
    $p = Start-Process powershell.exe -ArgumentList ($a | ForEach-Object { Q $_ }) -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    $null = $p.Handle
    $p.WaitForExit()
    $said = @(Get-Content $out, "$out.err" -ErrorAction SilentlyContinue)
    foreach ($l in $said) { if ($l) { Write-Host "    $l" } }
    $line = $said | Where-Object { "$_" -cmatch '^started .* pid \d+ -> ' } | Select-Object -Last 1
    if (-not $line -or -not ("$line" -cmatch 'pid (\d+) -> (.+)$')) { Fail 'the launcher did not start QEMU (its output is above)' }
    $id = [int]$Matches[1]
    @{ Pid = $id; Dir = $Matches[2].Trim(); Proc = (Get-Process -Id $id -ErrorAction SilentlyContinue) }
}
function Guest-Alive($g) { $g.Proc -and -not $g.Proc.HasExited }
# sync (unless -NoSync), QMP quit, then up to 120 s for QEMU to end before it is stopped (by its PID); true when
# the guest answered sync
function Stop-Tv($g, [switch]$NoSync) {
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
# What an earlier step left (tvos\<rel>), else stop and say which step makes it
function Need-Input([string]$rel, [string]$step) {
    if (-not $DryRun -and -not (Test-Path (In-Tv $rel))) { Fail "no tvos\${rel}: the $step step makes it (run -From $step)" }
}
function Do-Check {
    # the iOS 26 install this builds on (its kernel: kc-vision.py --check below)
    $need = @('fw\sptm', 'fw\txm', 'fw\dtree.orig', 'dtree-smp4', 'rd-shell.hfs', 'downloads\ios_sysroot.tar.gz',
              'tools\qemu-sptm\scripts\darwin\vresearch_dt_fixup.py')
    $missing = @($need | Where-Object { -not (Test-Path (In-Work $_)) })
    if ($missing) {
        Stop-Here ("this has no iOS 26 base ($Work lacks $($missing -join ', ')): make it with Install-ASoftware.cmd -Version tvos " +
                   '(or install iOS 26), or give its folder with -Work')
    }
    $mode = Ios-Mark 'linux'
    if (-not $mode) { $mode = $LinuxMode }
    if ($mode -ceq 'helper') {
        Stop-Here 'the iOS 26 install ran its Linux steps in the helper VM; the tvOS installer needs WSL 2 (ios26\Install-iOS26.cmd -Linux wsl -Only linux sets it up)'
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
    # tvOS's home screen draws through Metal: the GPU driver iOS 26's gpu step leaves in gpu-driver\ (or on its disk)
    if (((Ios-Mark 'gpu') -ceq 'gpuless' -or (Ios-Mark 'gpudriver') -ceq 'gpuless') -and -not (Test-Path (In-Work "gpu-driver\$GpuBundle"))) {
        Stop-Here ('iOS 26 was installed GPU-less, and tvOS draws through its GPU driver (Metal): choose one in ' +
                   'ios26\Start-iOS26.cmd''s menu ([G]), run ios26\Install-iOS26.cmd again (it redoes its gpu step), then this')
    }
    Say "iOS 26 install: $Work; WSL distro $Distro, Linux scratch $LinuxDir"
    if ($OtaFile) {
        # (read in WSL through its /mnt path, inside single quotes)
        $f = [IO.Path]::GetFullPath($OtaFile)
        if ($f -cmatch "'" -or $f -cnotmatch '^[A-Za-z]:\\') { Stop-Here "-OtaFile $f`: WSL reads it through its drive letter, and a network path or a ' in the path cannot be passed to it; copy the file to a local drive" }
        elseif (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Stop-Here "-OtaFile $f`: no such file" }
        elseif ((Get-Item -LiteralPath $f).Length -ne $OtaSize) { Stop-Here "-OtaFile $f is $((Get-Item -LiteralPath $f).Length) bytes, not $OtaSize (the 27.2 24K122 AppleTV14,1 full OTA)" }
        else { Say "the OTA from $f (its SHA-256 is checked by the download step)" }
    }
    # the scripts tvOS's steps run, in tvos\scripts (WSL reads them there; bash wants LF): this version's iOS 26
    # scripts (root26-do.sh, mktc.py, root26-prefs.py, ...), the watch's shared-cache tools, visionOS's kernel
    # patcher, the LZFSE decoder of tools\ (the OTA's device tree is stored compressed), then tvOS's
    $dst = In-Tv 'scripts'
    $watchDir = Join-Path $repo 'watchos\scripts'
    $visionDir = Join-Path $repo 'visionos\scripts'
    $dirs = @((Join-Path $repo 'ios26\scripts'), $watchDir, $visionDir, (Join-Path $here 'scripts'))
    foreach ($d in $dirs) { if (-not (Test-Path $d)) { Stop-Here "no $d (this installer comes with ios26\, watchos\, visionos\ and tvos\ beside each other)" } }
    $lzfse = Join-Path $repo 'tools\lzfse.py'
    if (-not (Test-Path -LiteralPath $lzfse -PathType Leaf)) { Stop-Here "no $lzfse (this installer comes with tools\ beside tvos\)" }
    Show-Cmd "copy ios26\scripts, watchos\scripts\{dscforce,dscfind}.py, visionos\scripts\kc-vision.py, tools\lzfse.py, tvos\scripts -> $dst (.sh with LF)"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force $dst, (In-Tv 'ota'), (In-Tv 'build'), (In-Work 'install\logs') | Out-Null
        $files = @(Get-ChildItem (Join-Path $repo 'ios26\scripts') -File) +
                 @('dscforce.py', 'dscfind.py' | ForEach-Object { Get-Item (Join-Path $watchDir $_) }) +
                 @(Get-Item (Join-Path $visionDir 'kc-vision.py')) +
                 @(Get-Item -LiteralPath $lzfse) +
                 @(Get-ChildItem (Join-Path $here 'scripts') -File)
        foreach ($f in $files) {
            $to = Join-Path $dst $f.Name
            if ($f.Extension -ceq '.sh') {
                $t = [IO.File]::ReadAllText($f.FullName) -replace "`r`n", "`n"
                [IO.File]::WriteAllText($to, $t, (New-Object System.Text.UTF8Encoding $false))
            } else { Copy-Item $f.FullName $to -Force }
        }
    }
    # the kernel the firmware step makes, before anything is downloaded
    if (-not (Get-Mark 'firmware') -or -not (Test-Path (In-Tv 'bootkc-t'))) {
        $null = Py 'kc-vision.py' (@('--check') + @($KernelIn | ForEach-Object { In-Work $_ })) -NoFail
        if ($script:Code) {
            if (-not (Test-Path (In-Work $KernelPacked))) {
                Stop-Here "the iOS 26 install has no plain cloudOS 26.4b research kernel (see above), nor $KernelPacked to decompress it from"
            }
            Say "the firmware step decompresses it again out of $KernelPacked"
        }
    }
    # what tvOS's Linux steps need beyond the base's tools (apt, once)
    $null = Run-Wsl 'tools' (Step-Body 'tools')
}

# The QEMU every guest of this install runs on, <work>\qemu, is the build tvOS was measured on: visionOS's (walk
# mode with the held key, the TLBI filter; its reims/metal2vulkan draw tvOS's glass, which the older watch build
# refused). The probes only read (a dry run makes them too), as Install-visionOS.ps1's. The TV window (usb-consumer
# tv-remote, branch asoft-tv) is asked for by Qemu-HasRemote below, never required.
function Qemu-Probe([string]$exe, [string[]]$argv) {
    $psi = New-Object Diagnostics.ProcessStartInfo $exe
    $psi.Arguments = ($argv | ForEach-Object { Q $_ }) -join ' '
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $err = $p.StandardError.ReadToEndAsync(); $out = $p.StandardOutput.ReadToEndAsync()
    if (-not $p.WaitForExit(20000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; return '' }
    $out.Result + "`n" + $err.Result
}
function Qemu-HasTv([string]$dir) {
    # (Combine, not Join-Path, which throws on a drive that is not there)
    $exe = [IO.Path]::Combine($dir, 'qemu-system-aarch64.exe')
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $false }
    $walk = Qemu-Probe $exe @('-device', 'usb-touchscreen,help')
    if ($walk -cnotmatch '\bwalk-hold-key=') { return $false }
    $cpu = Qemu-Probe $exe @('-M', 'none', '-cpu', 'max,x-tlbi-filter=on,x-asoft-probe=on', '-display', 'none', '-S', '-nodefaults')
    ($cpu -cmatch 'x-asoft-probe') -and ($cpu -cnotmatch "x-tlbi-filter' not found")
}
# The TV window (usb-consumer tv-remote, the asoft-tv build): not needed (Start-tvOS.ps1 falls back to the plain
# window), but a -QemuDir that has it replaces a <work>\qemu that does not
function Qemu-HasRemote([string]$dir) {
    $exe = [IO.Path]::Combine($dir, 'qemu-system-aarch64.exe')
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $false }
    (Qemu-Probe $exe @('-device', 'usb-consumer,help')) -cmatch '(?m)^\s*tv-remote='
}
# QEMUs started from <work>\qemu (any guest of this install): its files cannot be replaced under them
function Need-NoQemuFrom([string]$dir) {
    if ($DryRun) { return }
    $p = @(Get-Process -Name 'qemu-system-aarch64*' -ErrorAction SilentlyContinue | Where-Object {
            $_.Path -and $_.Path.StartsWith($dir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) })
    if ($p) { Fail ("QEMU runs from $dir (pid {0}: iOS 16, iOS 26, watchOS, visionOS or tvOS): close it first, its files are replaced" -f (($p | ForEach-Object Id) -join ', ')) }
}
# the release package of that QEMU, as asoft-setup.json names it: os.tvos.files.qemu, else visionOS's (the same build)
function Qemu-Release {
    $r = @{ Version = ''; Url = ''; Sha256 = '' }
    $j = Join-Path $repo 'installer\asoft-setup.json'
    try {
        $os = (Get-Content $j -Raw | ConvertFrom-Json).os
        foreach ($q in @($os.tvos.files.qemu, $os.visionos.files.qemu)) {
            if ($q -and $q.url) { $r.Version = "$($q.version)"; $r.Url = "$($q.url)"; $r.Sha256 = "$($q.sha256)".ToUpperInvariant(); break }
        }
    } catch { }
    $r
}
function Do-Qemu {
    $dst = In-Work 'qemu'
    $newRemote = $QemuDir -and (Qemu-HasRemote ([IO.Path]::GetFullPath($QemuDir).TrimEnd('\'))) -and -not (Qemu-HasRemote $dst)
    if ((Qemu-HasTv $dst) -and -not $newRemote) {
        Say "have $dst (visionOS's build: walk-hold-key, x-tlbi-filter$(if (Qemu-HasRemote $dst) { '; the TV window' }))$(if ($QemuDir) { ': -QemuDir is not needed' })"
        return
    }
    if ($newRemote -and (Qemu-HasTv $dst)) { Say "-QemuDir has the TV window (usb-consumer tv-remote), $dst does not: it is replaced, for every guest" Yellow }
    else { Say "$dst is older than the build tvOS was measured on (visionOS's: usb-touchscreen walk-hold-key, -cpu x-tlbi-filter): it is replaced by one that has them, which runs iOS 16, iOS 26, watchOS and visionOS too" Yellow }
    if ($QemuDir) {
        $src = [IO.Path]::GetFullPath($QemuDir).TrimEnd('\')
        # looked at before anything is copied
        if (-not (Qemu-HasTv $src)) {
            Stop-Here "$src has no qemu-system-aarch64.exe with visionOS's options (walk-hold-key, x-tlbi-filter): not the build tvOS runs on (qemu-sptm asoft-vision, win-build.sh's dist)"
            return
        }
        if ($src -ieq $dst.TrimEnd('\')) { return }
        # a package folder, as every launcher wants it (they start qemu-system-aarch64w.exe), not a bare build tree
        foreach ($exeName in 'qemu-system-aarch64w.exe', 'qemu-img.exe') {
            if (-not (Test-Path -LiteralPath ([IO.Path]::Combine($src, $exeName)) -PathType Leaf)) {
                Stop-Here "$src has no $($exeName), so it is no package folder (win-build.sh's dist has it): not a build tree"
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
            Stop-Here ('the QEMU tvOS runs on (visionOS''s build) is not published as a package yet (asoft-setup.json, os.tvos / os.visionos files.qemu): ' +
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
    if (-not $DryRun -and -not (Qemu-HasTv $dst)) { Fail "$dst still lacks visionOS's options after the copy" }
    $build = Join-Path $dst 'BUILD.txt'
    if (-not $DryRun -and (Test-Path $build)) { foreach ($l in Get-Content $build) { Say $l } }
}
function Do-LzRaven {
    $body = (Step-Body 'lzraven').Replace('{COMMIT}', $LzRaven.Commit).Replace('{REPO}', $LzRaven.Repo)
    $null = Run-Wsl 'lzraven' $body
}

# The OTA's chain of build files, each made again from the one before when it is gone (a later step's redo after
# the cleanup removed them): the .aea (downloaded, or -OtaFile) -> the decrypted archive + its index + the boot
# files (decrypt) -> the unpacked root's ext4 image (unpack) -> the root disk (rootfs)
function Ota-Path { if ($OtaFile) { [IO.Path]::GetFullPath($OtaFile) } else { In-Tv "ota\$OtaName" } }
$OtaOk = 'install\got\tv-ota.ok'
# the .aea is whole and checked: its marker names it with its size and time (a file changed since is checked again)
function Ota-Key([string]$p) { $i = Get-Item -LiteralPath $p; "$($i.FullName)|$($i.Length)|$($i.LastWriteTimeUtc.Ticks)" }
function Ota-Ready {
    $p = Ota-Path
    $ok = In-Work $OtaOk
    (Test-Path -LiteralPath $p -PathType Leaf) -and (Test-Path $ok) -and ("$(Get-Content $ok -TotalCount 1)".Trim() -ceq (Ota-Key $p))
}
function Decrypt-Ready {
    (Test-Path (In-Tv 'build\dec.ok')) -and (Test-Path (In-Tv 'build\dec\ota.aa')) -and (Test-Path (In-Tv 'build\outer.json')) -and
        -not @($OsTrustCache, 'DeviceTree.j255ap.im4p', 'BuildManifest.plist' | Where-Object { -not (Test-Path (In-Tv "ota\$_")) }).Count
}
function Root-Ready { (Test-Path (In-Tv 'build\root.ext4')) -and (Test-Path (In-Tv 'build\root.ext4.ok')) }
function Do-Download {
    if (-not $DryRun -and ((Decrypt-Ready) -or (Root-Ready))) { Say 'have the OTA''s decrypted archive or the unpacked root: nothing to fetch'; return }
    if (-not $DryRun -and (Ota-Ready)) { Say "have $(Ota-Path) (checked)"; return }
    $p = Ota-Path
    $ok = In-Work $OtaOk
    if ($OtaFile) {
        Show-Cmd "SHA-256 of $p (pinned $OtaSha256)"
        if ($DryRun) { return }
        if (-not (Test-Path -LiteralPath $p -PathType Leaf) -or (Get-Item -LiteralPath $p).Length -ne $OtaSize) { Fail "-OtaFile $p is not the $OtaSize-byte OTA" }
        Say 'checking its SHA-256 (about a minute from an SSD)'
        $h = Sha256 $p
        if ($h -cne $OtaSha256) { Fail "-OtaFile $p has SHA-256 $h, not $OtaSha256 (the 27.2 24K122 AppleTV14,1 full OTA)" }
        New-Item -ItemType Directory -Force (Split-Path $ok) | Out-Null
        Set-Content $ok (Ota-Key $p)
        return
    }
    # (pdl.py makes OUT.part at its full size first: a download that stopped has its room already, and goes on
    # with the pieces OUT.part.done notes)
    $part = "$p.part"
    $partThere = (Test-Path -LiteralPath $part -PathType Leaf) -and (Get-Item -LiteralPath $part).Length -eq $OtaSize
    if (-not $partThere) { Need-Space $Space.download }
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force (Split-Path $p), (Split-Path $ok) | Out-Null
        Remove-Item $ok -ErrorAction SilentlyContinue
    }
    if ($CdnEdge) { Say "the OTA through the CDN edge(s) $CdnEdge" }
    Say ("downloading the 4.97 GB OTA onto {0} (about 12 min at 7 MB/s; a stop goes on where it stopped)" -f [IO.Path]::GetPathRoot($Work))
    $edge = if ($CdnEdge) { $CdnEdge } else { '-' }
    $null = Py 'pdl.py' @($OtaUrl, $p, "$OtaSize", $OtaSha256, $edge, '8') -NoFail
    if ($script:Code -eq 3) {
        if (-not $DryRun) { Remove-Item -LiteralPath $part, "$part.done" -ErrorAction SilentlyContinue }
        Fail "the OTA's SHA-256 is not $OtaSha256 (Apple changed the file?): its pieces were removed"
    }
    if ($script:Code) { Fail "the download stopped (pdl.py exited with $($script:Code)): run again to go on where it stopped" }
    if (-not $DryRun) { Set-Content $ok (Ota-Key $p) }
}
function Do-Decrypt {
    if (-not $DryRun -and -not (Test-Path (In-Tv 'build\dec.ok'))) {
        # the .aea first (a later redo, after the cleanup removed it, fetches it again)
        if (-not (Ota-Ready)) { Do-Download }
        Need-Space $Space.decrypt
    }
    $body = (Step-Body 'decrypt').Replace('{KEY}', $OtaKey).Replace('{AEA}', (To-Wsl (Ota-Path))).Replace('{DECSIZE}', "$DecSize").
        Replace('{PATTERN}', $BootPattern).Replace('{TC}', $OsTrustCache).Replace('{TCENTRIES}', "$TcEntries")
    $null = Run-Wsl 'decrypt' $body
    # read decrypted from now on: a downloaded .aea goes (-OtaFile's stays where it is)
    if (-not $OtaFile -and -not $KeepBuildFiles) {
        Show-Cmd "del tvos\ota\$OtaName"
        if (-not $DryRun) { Remove-Item -LiteralPath (Ota-Path), (In-Work $OtaOk) -ErrorAction SilentlyContinue }
    }
}
function Do-Unpack {
    if (-not $DryRun -and -not (Decrypt-Ready)) {
        Say 'no decrypted OTA (removed once a root was unpacked from it, or its decrypt stopped): decrypting it again' Yellow
        Do-Decrypt
    }
    # made anew each time: a new sparse file (an image a stopped unpack wrote keeps its room until it is removed)
    $img = In-Tv 'build\root.ext4'
    if (-not $DryRun) { Remove-Item -LiteralPath "$img.ok", $img -Force -ErrorAction SilentlyContinue }
    Need-Space $Space.unpack
    New-SparseFile $img ([long]$RootImageGiB * 1GB)
    Say 'unpacking the root (12.6 GB) out of the OTA, then checking its code signatures (about 40 min measured on a USB 2 drive)'
    $body = (Step-Body 'unpack').Replace('{TC}', $OsTrustCache).Replace('{NOTINTC}', "$NotInTc")
    $null = Run-Wsl 'unpack' $body
    # the report and the signature check stay with the install's logs
    if (-not $DryRun) {
        foreach ($n in 'report.json', 'vsig.json') {
            $f = In-Tv "build\root-meta\$n"
            if (Test-Path $f) { Copy-Item $f (In-Work "install\logs\tv-root-$n") -Force }
        }
    }
    # the decrypted archive is read no more (the root is unpacked): it goes
    if (-not $KeepBuildFiles) {
        Show-Cmd 'del tvos\build\dec'
        if (-not $DryRun) { Remove-Item (In-Tv 'build\dec.ok'), (In-Tv 'build\dec') -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
function Do-Firmware {
    # the kernel: visionOS's (visionos\bootkc-v when visionOS is installed), else the base's plain research kernel
    # patched by kc-vision.py, else that kernel decompressed again out of $KernelPacked
    $in = @($KernelIn | ForEach-Object { In-Work $_ })
    $null = Py 'kc-vision.py' (@('--check') + $in) -NoFail
    if ($script:Code) {
        $body = Step-Body 'kernel'
        # (kernel.sh writes into $W/build/kc: here tvos\build\kc)
        $null = Run-Wsl 'kernel' $body.Replace('{PACKED}', ($KernelPacked -replace '\\', '/'))
        $in += In-Tv 'build\kc\kernel'
    }
    $null = Py 'kc-vision.py' (@((In-Tv 'bootkc-t')) + $in)
    # the device trees: the base's SMP trees with J255's identity, one per vCPU count
    Need-Input "ota\DeviceTree.j255ap.im4p" 'decrypt'
    $raw = In-Tv 'ota\DeviceTree.j255ap.raw'
    $null = Py 'dtraw.py' @((In-Tv 'ota\DeviceTree.j255ap.im4p'), $raw)
    if (-not $DryRun -and (Sha256 $raw) -cne $J255Sha) { Fail "J255's device tree in the OTA is not the pinned one (SHA-256 $(Sha256 $raw)): another OTA?" }
    $qs = In-Work 'tools\qemu-sptm'
    Show-Cmd "QEMU_SPTM=$qs"
    $env:QEMU_SPTM = $qs
    if (-not $DryRun) { New-Item -ItemType Directory -Force (In-Tv 'build') | Out-Null }
    $smp6 = In-Tv 'build\dtree-smp6'
    $null = Py 'dt-root26smp.py' @((In-Work 'fw\dtree.orig'), $smp6, '--cpus', '6')
    $smp8 = In-Work 'dtree-smp8'
    if (-not $DryRun -and -not (Test-Path $smp8)) {
        $smp8 = In-Tv 'build\dtree-smp8'
        $null = Py 'dt-root26smp.py' @((In-Work 'fw\dtree.orig'), $smp8, '--cpus', '8')
    }
    # each with its 1080p sibling (<tree>-1080: display scale 1, artwork 1080 @1x), which Start-tvOS.ps1
    # -Resolution 1080 boots with fb=1920x1080 on the same disk
    foreach ($t in @(@('dtree-t', (In-Work 'dtree-smp4')), @('dtree-t6', $smp6), @('dtree-t8', $smp8))) {
        $outTree = In-Tv $t[0]
        $null = Py 'dt-tv.py' @($t[1], $raw, $outTree)
        $null = Py 'dt-res.py' @($outTree, '1', "$outTree-1080")
        foreach ($n in $t[0], "$($t[0])-1080") {
            if (-not $DryRun -and (Sha256 (In-Tv $n)) -cne $TreeSha[$n]) {
                Say "tvos\$n differs from the one made on our PC (another iOS 26 base's tree?): used as it is" Yellow
            }
        }
    }
}
function Do-Gpu {
    # the guest GPU driver, kept in <Work>\gpu-driver for every guest (an older iOS 26 install has it only on its
    # disk: copied off it, read only)
    $shared = In-Work "gpu-driver\$GpuBundle"
    if ($DryRun -or -not (Test-Path $shared)) {
        $top = @('root.qcow2', 'root26-gpu.qcow2') | Where-Object { $DryRun -or (Test-Path (In-Work $_)) } | Select-Object -First 1
        if (-not $top) { Fail "no $shared and no iOS 26 disk with the GPU driver (root.qcow2): is iOS 26 GPU-less? tvOS cannot draw without it" }
        $body = Step-Body 'gpu-driver'
        $null = Run-Wsl 'gpu-driver' $body.Replace('{TOP}', $top).Replace('{BUNDLE}', $GpuBundle)
    } else { Say "have gpu-driver\$GpuBundle" }
    # tvOS's copy in tvos\gpu (the cleanup keeps it): both Mach-Os retargeted to tvOS and ad-hoc signed
    $body = Step-Body 'gpu'
    $null = Run-Wsl 'gpu' $body.Replace('{BUNDLE}', $GpuBundle)
}
function Need-Gpu {
    if ($DryRun -or ((Test-Path (In-Tv "gpu\$GpuBundle")) -and (Test-Path (In-Tv 'gpu\hashes.txt')))) { return }
    Say 'no tvos\gpu (tvOS''s copy of the GPU driver): the gpu step again' Yellow
    Do-Gpu
}
# The user disk (tv.qcow2 on roott-b on roott-p on roott) before a step replaces it or a layer under it: a disk the
# install finished (tv.qcow2.ready) is kept as tv.qcow2.old, with what tvOS wrote (on the old layers: mountable with
# them only), one the install did not finish goes. An .old an earlier redo kept is never written over: this one gets
# the next free name (.old2, .old3, ...)
function Retire-Tv {
    $userDisk = In-Tv 'tv.qcow2'
    $ready = "$userDisk.ready"
    if (-not (Test-Path $userDisk)) { if (-not $DryRun) { Remove-Item $ready -ErrorAction SilentlyContinue }; return }
    Need-NoTv
    if (Test-Path $ready) {
        $old = "$userDisk.old"
        for ($k = 2; (Test-Path $old); $k++) { $old = "$userDisk.old$k" }
        Say "tvos\tv.qcow2, the disk tvOS ran from, rests on what this step replaces: kept as tvos\$(Split-Path $old -Leaf) (a new one starts afresh)" Yellow
        if (-not $DryRun) { Move-Item $userDisk $old; Remove-Item $ready -Force }
    } else {
        Show-Cmd 'del tvos\tv.qcow2   (an unfinished install''s)'
        if (-not $DryRun) { Remove-Item $userDisk -Force }
    }
}
function Do-Rootfs {
    # a root built before goes first, with the layers on it (the chain after this step is redone)
    Retire-Tv
    foreach ($f in 'roott-b.qcow2', 'roott-p.qcow2', 'roott-p.hashes', 'roott.qcow2', 'roott.qcow2.hashes') {
        if ($DryRun -or (Test-Path (In-Tv $f))) { Show-Cmd "del tvos\$f"; if (-not $DryRun) { Remove-Item (In-Tv $f) -Force } }
    }
    # the unpacked root is removed once a root disk is built from it: redone later, this step unpacks it again
    if (-not $DryRun -and -not (Root-Ready)) {
        Say 'no whole unpacked root (a root disk was built from it before, or its unpack stopped): unpacking it again' Yellow
        Do-Unpack
    }
    Need-Space $Space.rootfs
    Say 'copying the root onto the HFS+ disk (19 min measured from a USB 2 drive)'
    $null = Run-Wsl 'rootfs' (Step-Body 'rootfs')
    # the root is on the disk now
    if (-not $KeepBuildFiles) {
        Show-Cmd 'del tvos\build\root.ext4'
        if (-not $DryRun) { Remove-Item (In-Tv 'build\root.ext4.ok'), (In-Tv 'build\root.ext4') -Force -ErrorAction SilentlyContinue }
    }
}
function Do-Patches {
    # on an overlay made anew each time (roott.qcow2 stays as mk-roott.sh built it), so this step can be redone
    Need-Input 'roott.qcow2' 'rootfs'
    Need-Input 'roott.qcow2.hashes' 'rootfs'
    Need-Gpu
    Need-Space $Space.patches
    Retire-Tv
    $null = Run-Wsl 'patches' (Step-Body 'patches')
}
function Do-TrustCache {
    # Apple's, the signed sysroot (rootfs), the patched subcaches (patches: IOMobileFramebuffer's, libxpc's and
    # QuartzCore's, whose CDHashes dsc-patch.py computes) and the GPU driver (gpu): each list from the step that makes
    # it (the hand-built roott.tc: 1738 entries, 1739 with QuartzCore's in roott4.tc)
    $in = [ordered]@{ "ota\$OsTrustCache" = 'decrypt'; 'roott.qcow2.hashes' = 'rootfs'; 'roott-p.hashes' = 'patches'; 'gpu\hashes.txt' = 'gpu' }
    foreach ($f in $in.Keys) { Need-Input $f $in[$f] }
    $null = Py 'mktc.py' (@('-2', (In-Tv 'roott.tc')) + @($in.Keys | ForEach-Object { In-Tv $_ }))
}
function Do-FirstBoot {
    # once, so usermanagerd writes the persona manifest and the user session (persona.kb, usersession.kb: both there
    # a minute into the hand-built disk's first boot) and mobileactivationd makes its container, which the persona
    # step completes. HFS+ lets it write them only when they are new.
    Need-Input 'roott-p.qcow2' 'patches'
    Need-Input 'roott.tc' 'trustcache'
    Need-NoTv
    Retire-Tv
    $null = Run-Wsl 'overlay' 'overlay roott-p.qcow2 tvos/roott-b.qcow2'
    Need-Space $Space.firstboot
    $g = Start-Tv 'install-firstboot'
    try {
        $test = ('test -e /private/var/keybags/persona.kb && test -e /private/var/keybags/usersession.kb && ' +
                 'ls /private/var/containers/Data/System/*/Library/internal/data_ark.plist > /dev/null 2>&1 && echo __READY__ || echo __WAIT__')
        Say 'waiting for the persona manifest, the user session and mobileactivationd''s data ark in the guest (up to 30 min)'
        if ($DryRun) {
            $null = Guest 90 @($test)
        } else {
            $t0 = Get-Date
            while ($true) {
                if (-not (Guest-Alive $g)) { Fail "QEMU ended during the first boot; see $($g.Dir)" }
                $min = ((Get-Date) - $t0).TotalMinutes
                Emit 'pct', 'tv', 'firstboot', ([int][Math]::Min(95, 100 * $min / 5)), 'waiting for the persona manifest'
                $said = Guest 90 @($test) -NoFail
                # a line of its own: the command (printed as "$ cmd" above it) has the word too
                if (@($said | Where-Object { "$_".Trim() -ceq '__READY__' }).Count) { break }
                if ($min -gt 30) { Fail "no persona.kb, usersession.kb or data ark after 30 min; see $($g.Dir)\serial.log" }
                Start-Sleep -Seconds 30
            }
            Say ("there after {0:N0} min" -f ((Get-Date) - $t0).TotalMinutes)
            Start-Sleep -Seconds 30
        }
        if (-not (Stop-Tv $g)) { Fail 'the guest did not answer sync; run again to redo the first boot' }
    } catch {
        if (-not $DryRun -and (Guest-Alive $g)) { $null = Stop-Tv $g -NoSync }
        throw
    }
}
function Do-Persona {
    Need-Input 'roott-b.qcow2' 'firstboot'
    Need-NoTv
    $null = Run-Wsl 'persona' (Step-Body 'persona')
}
function Do-HomeBoot {
    # once more, to Home (about 75-96 s on the hand-built disk), so the user's first start is a plain one. Home = the
    # screen dumped by QMP over $HomeBytes twice 20 s apart; then 2 min more
    Need-Input 'roott-b.qcow2' 'firstboot'
    Need-NoTv
    Need-Space $Space.homeboot
    $g = Start-Tv 'install-homeboot'
    try {
        Say 'waiting for Home (up to 20 min; about 1.5 on our PC)'
        if (-not $DryRun) {
            $t0 = Get-Date
            $seen = 0
            $k = 0
            while ($true) {
                if (-not (Guest-Alive $g)) { Fail "QEMU ended during the boot to Home; see $($g.Dir)" }
                $min = ((Get-Date) - $t0).TotalMinutes
                Emit 'pct', 'tv', 'homeboot', ([int][Math]::Min(95, 100 * $min / 4)), 'waiting for Home'
                $k++
                $bytes = Screen-Bytes $g ("screen-{0:D2}" -f $k)
                if ($bytes -gt $HomeBytes) { $seen++ } else { $seen = 0 }
                if ($seen -ge 2) { Say ("Home after {0:N0} min ($($g.Dir)\screen-{1:D2}.png)" -f $min, $k); break }
                if ($min -gt 20) { Say 'no Home after 20 min: the first start goes on with what this boot did not finish' Yellow; break }
                Start-Sleep -Seconds 20
            }
            Start-Sleep -Seconds 120
        }
        if (-not (Stop-Tv $g)) { Fail 'the guest did not answer sync; run again to redo this boot' }
    } catch {
        if (-not $DryRun -and (Guest-Alive $g)) { $null = Stop-Tv $g -NoSync }
        throw
    }
}
function Do-Disks {
    Need-Input 'roott-b.qcow2' 'firstboot'
    Need-NoTv
    Need-Space $Space.disks
    Retire-Tv
    $null = Run-Wsl 'disks' (Step-Body 'disks')
    # the disk is the user's now: a later redo keeps it (Retire-Tv); the launcher starts only it
    if (-not $DryRun) { Set-Content (In-Tv 'tv.qcow2.ready') (Get-Date -Format s) }
}
function Do-Cleanup {
    if ($KeepBuildFiles) { Say '-KeepBuildFiles: the OTA, its decrypted archive and the unpacked root''s image stay' DarkGray; return }
    $null = Run-Wsl 'cleanup' (Step-Body 'cleanup')
    # (ota\ without the .aea, gpu\ and the hash lists stay: a later redo of the disk steps reads them)
    foreach ($rel in 'tvos\build', 'tvos\tmp', "tvos\ota\$OtaName", "tvos\ota\$OtaName.part", "tvos\ota\$OtaName.part.done") {
        if (-not (Test-Path -LiteralPath (In-Work $rel))) { continue }
        Show-Cmd "del $rel"
        if ($DryRun) { continue }
        try { Remove-Item -LiteralPath (In-Work $rel) -Recurse -Force }
        catch {
            # a running tvOS's temporary files (Start-tvOS.ps1's TEMP)
            if ($rel -cne 'tvos\tmp') { throw }
            Say 'tvos\tmp is in use (tvOS is running): left' DarkGray
        }
    }
    if (-not $OtaFile) { Remove-Item (In-Work $OtaOk) -ErrorAction SilentlyContinue }
}
function Do-Shortcut {
    $cmd = Join-Path $repo 'Start-tvOS.cmd'
    Say "start it with $cmd"
    if ($NoShortcut -or $DryRun) { return }
    try {
        $dir = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\ASoftware'
        New-Item -ItemType Directory -Force $dir | Out-Null
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $dir 'ASoftware tvOS.lnk'))
        $s.TargetPath = $cmd
        $s.Arguments = "-Work `"$Work`""
        $s.WorkingDirectory = $repo
        $s.Save()
        Say "Start menu: ASoftware\ASoftware tvOS"
    } catch {
        Say "no Start menu shortcut ($($_.Exception.Message)): start it with $cmd" Yellow
    }
}

# Min: minutes on our PC (i7-13700HX, 24 threads, ~7 MB/s from Apple's CDN). Measured on the hand-built tvOS
# (notes/TVOS.md, 2026-11-08/09, its OTA files on a USB 2 drive): decrypt 5.5 min, the unpack 12.9 min + its
# signature check 24.1, the root copy 19 min, the patches 1 min, Home 75-96 s after a start; the download at 7 MB/s,
# liblzraven's build and the first boot's wait are estimates, as is the whole: the installer is not timed end to end.
# GB: what it downloads. Add: GB (10^9) the step takes on the work drive at its height, Keep: what it leaves
# (after its own removals; the cleanup's are in its own row)
$Steps = @(
    @{ Id = 'check';      Kind = 'always'; Min = 1;  GB = 0;     Add = 0.01; Keep = 0.01; Title = 'The iOS 26 base it builds on, WSL and its tools, the scripts' }
    @{ Id = 'qemu';       Kind = 'once';   Min = 1;  GB = 0.32;  Add = 0.6;  Keep = 0;    Title = 'The QEMU every guest runs on, the build tvOS was measured on (qemu\)' }
    @{ Id = 'lzraven';    Kind = 'once';   Min = 2;  GB = 0.001; Add = 0;    Keep = 0;    Title = 'liblzraven (pinned commit) and pbzm_dec, built in WSL' }
    @{ Id = 'download';   Kind = 'once';   Min = 12; GB = 4.97;  Add = 4.97; Keep = 4.97; Title = 'tvOS 27.2 full OTA for AppleTV14,1 (Apple, 4.97 GB, SHA-256 checked)' }
    @{ Id = 'decrypt';    Kind = 'once';   Min = 6;  GB = 0;     Add = 5.0;  Keep = 0.03; Title = 'Decrypt the OTA, index it, take out its boot files' }
    @{ Id = 'unpack';     Kind = 'once';   Min = 40; GB = 0;     Add = 13.0; Keep = 8.0;  Title = 'Unpack the root (LZRAVEN) into an ext4 image and check its signatures' }
    @{ Id = 'firmware';   Kind = 'once';   Min = 1;  GB = 0;     Add = 0.05; Keep = 0.05; Title = 'The tvOS kernel and device trees (4, 6 and 8 vCPUs; 4K and 1080p)' }
    @{ Id = 'gpu';        Kind = 'once';   Min = 1;  GB = 0;     Add = 0.01; Keep = 0.01; Title = 'The guest GPU driver for tvOS' }
    @{ Id = 'rootfs';     Kind = 'chain';  Min = 20; GB = 0;     Add = 10.3; Keep = -2.7; Title = 'The root disk, from the unpacked root (tvos\roott.qcow2)' }
    @{ Id = 'patches';    Kind = 'chain';  Min = 2;  GB = 0;     Add = 0.65; Keep = 0.65; Title = 'Tweaks, shared-cache patches, prefs and the GPU driver on it' }
    @{ Id = 'trustcache'; Kind = 'chain';  Min = 1;  GB = 0;     Add = 0;    Keep = 0;    Title = 'Its trust cache (tvos\roott.tc)' }
    @{ Id = 'firstboot';  Kind = 'chain';  Min = 5;  GB = 0;     Add = 1.3;  Keep = 1.3;  Title = 'First boot (tvos\roott-b.qcow2)' }
    @{ Id = 'persona';    Kind = 'chain';  Min = 1;  GB = 0;     Add = 0.05; Keep = 0.05; Title = 'Persona, MobileGestalt, activation and tvOS''s prefs' }
    @{ Id = 'homeboot';   Kind = 'chain';  Min = 5;  GB = 0;     Add = 0.3;  Keep = 0.3;  Title = 'Second boot, to Home' }
    @{ Id = 'disks';      Kind = 'chain';  Min = 1;  GB = 0;     Add = 0.01; Keep = 0.01; Title = 'The disk you use (tvos\tv.qcow2)' }
    @{ Id = 'cleanup';    Kind = 'always'; Min = 1;  GB = 0;     Add = 0;    Keep = 0;    Title = 'Remove what only the build needs' }
    @{ Id = 'shortcut';   Kind = 'always'; Min = 0;  GB = 0;     Add = 0;    Keep = 0;    Title = 'Start-tvOS.cmd and the Start menu shortcut' }
)
$ids = @($Steps | ForEach-Object { $_.Id })
foreach ($s in @($From, $Only)) { if ($s -and $ids -cnotcontains $s) { throw "no step $s (the steps: $($ids -join ', '))" } }
function Invoke-Step([string]$id) {
    switch -CaseSensitive ($id) {
        'check' { Do-Check } 'qemu' { Do-Qemu } 'lzraven' { Do-LzRaven } 'download' { Do-Download } 'decrypt' { Do-Decrypt }
        'unpack' { Do-Unpack } 'firmware' { Do-Firmware } 'gpu' { Do-Gpu } 'rootfs' { Do-Rootfs } 'patches' { Do-Patches }
        'trustcache' { Do-TrustCache } 'firstboot' { Do-FirstBoot } 'persona' { Do-Persona } 'homeboot' { Do-HomeBoot }
        'disks' { Do-Disks } 'cleanup' { Do-Cleanup } 'shortcut' { Do-Shortcut }
    }
}

# --- The iOS 26 install's settings ---------------------------------------------------------------
$cfg = $null
if (Test-Path $Config) { try { $cfg = Get-Content $Config -Raw | ConvertFrom-Json } catch { } }
if (-not $Work -and $cfg) { $Work = [string]$cfg.Work }
if (-not $Work) { throw "no iOS 26 install found ($Config has no work folder): install iOS 26 (or its base) first, or give -Work" }
$Work = [IO.Path]::GetFullPath($Work).TrimEnd('\')
# WSL reaches it as /mnt/<drive>/..., in scripts that do not quote every path (as Install-iOS26.ps1 checks)
if ($Work -cnotmatch '^[A-Za-z]:\\[^\s''"`$;&|<>()]+$') {
    throw "the work folder must be a drive-letter path without spaces or shell characters (WSL scripts use it): $Work"
}
$Distro = if ($cfg -and $cfg.Distro) { [string]$cfg.Distro } else { 'ios-emu' }
$LinuxDir = if ($cfg -and $cfg.Linux) { [string]$cfg.Linux } else { '/root/ios26' }
$LinuxMode = if ($cfg -and $cfg.LinuxMode) { [string]$cfg.LinuxMode } else { 'wsl' }
$Py = Join-Path $Work 'tools\python\python.exe'
if (-not (Test-Path $Py)) { $Py = (Get-Command python.exe -ErrorAction SilentlyContinue).Source }
if (-not $Py) { $Py = 'python.exe' }
# -OtaFile: nothing is downloaded (the step row says so), and no .aea on the work drive is removed after the
# decrypt (its archive is all it adds)
if ($OtaFile) {
    foreach ($s in $Steps) {
        if ($s.Id -ceq 'download') { $s.GB = 0; $s.Add = 0; $s.Keep = 0; $s.Min = 1 }
        if ($s.Id -ceq 'decrypt') { $s.Keep = $s.Add }
    }
}

if ($List -or $Estimate) {
    $tm = 0; $tg = 0
    # what is left: the minutes, the download and the room it takes (the peak less what finished steps left);
    # (0.0: an Int32 0 would take [Math]::Max's Int32 overload and round the peak)
    $cum = 0.0; $peak = 0.0; $there = 0.0
    foreach ($s in $Steps) {
        $done = $s.Kind -cne 'always' -and (Get-Mark $s.Id) -ceq (Step-Sig $s.Id)
        if ($List) {
            $m = if ($s.Kind -ceq 'always') { 'every run' } elseif ($done) { 'done' } elseif (Get-Mark $s.Id) { 'redo' } else { '-' }
            Say ("{0,-11} {1,-6} {2,-10} {3,6} {4,9}  {5}" -f $s.Id, $s.Kind, $m, $(if ($s.Min) { "$($s.Min) min" } else { '' }),
                 $(if ($s.GB -ge 0.01) { '{0:N2} GB' -f $s.GB } elseif ($s.GB) { '< 0.01 GB' } else { '' }), $s.Title)
        }
        if ($done) { $cum += $s.Keep; $there = $cum; $peak = [Math]::Max($peak, $cum); continue }
        $tm += $s.Min; $tg += $s.GB
        $peak = [Math]::Max($peak, $cum + $s.Add)
        $cum += $s.Keep
    }
    $freeNow = if (Test-Path -LiteralPath ([IO.Path]::GetPathRoot($Work))) { Free-GB } else { 0 }
    Say ("whole run about {0} h {1} min on our PC (an estimate: the installer is not timed end to end), {2:N1} GB from Apple and our releases" -f [Math]::Floor($tm / 60), ($tm % 60), $tg) DarkGray
    Say ("disk: about {0:N1} GB at the peak, {1:N1} GB when done (tvos\ and qemu\ of {2}); {3:N1} GB more are needed, {4:N1} GB are free on {5}" -f
         $peak, $cum, $Work, ($peak - $there), $freeNow, [IO.Path]::GetPathRoot($Work)) DarkGray
    if ($Estimate -and $freeNow -lt ($peak - $there) + 1) { Say ("not enough room on {0} for the peak: free some space first" -f [IO.Path]::GetPathRoot($Work)) Yellow }
    exit 0
}

# --- Run -----------------------------------------------------------------------------------------
Write-Host "ASoftware tvOS installer$(if ($DryRun) { ' (dry run: nothing is run)' })" -ForegroundColor Cyan
# said on the first screen and again at the end: what tvOS here is (TVOS.md, measured 2026-11-12)
function Preview-Notice {
    Write-Host '  tvOS is a RESEARCH PREVIEW, not a usable Apple TV. It reaches Home and Settings. What does not work:' -ForegroundColor Yellow
    Write-Host '    - Settings > General > About shows Activation: Failed'
    Write-Host '    - Search and the Apple TV app say they are not available'
    Write-Host '    - a key can take 3 to 20 seconds to show on screen'
    Write-Host '    - saves (quick save, Go back) have not been tested'
}
Preview-Notice
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
            Emit 'step', 'tv', ($i + 1), $Steps.Count, $s.Id, 'skip', $s.Title
            continue
        }
    }
    if ($Only -and $s.Kind -ceq 'always' -and $Only -cne $s.Id -and $s.Id -cne 'check') { continue }
    if (-not $DryRun -and (Pause-Requested)) {
        Emit 'paused', 'tv', $s.Id
        Write-Host ''
        Write-Host "Paused before step $($s.Id) (ASoftware.exe). Run this again to go on from it." -ForegroundColor Yellow
        exit 5
    }
    Step $label
    Emit 'step', 'tv', ($i + 1), $Steps.Count, $s.Id, 'start', $s.Title
    $script:Log = $null
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force (In-Work 'install\logs') | Out-Null
        $script:Log = In-Work "install\logs\tv-$($s.Id).log"
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
        Write-Host ("  Fix the cause and run Install-ASoftware.cmd (or tvos\Install-tvOS.cmd) again: it goes on " +
                    "from this step (Install-tvOS.cmd -Only $($s.Id) redoes just this one).") -ForegroundColor Yellow
        Emit 'step', 'tv', ($i + 1), $Steps.Count, $s.Id, 'fail', $_.Exception.Message
        Emit 'end', 'tv', 1
        exit 1
    }
    if ($s.Kind -cne 'always' -and -not $DryRun) { Set-Mark $s.Id (Step-Sig $s.Id) }
    Emit 'step', 'tv', ($i + 1), $Steps.Count, $s.Id, 'done', $s.Title
}
Emit 'end', 'tv', 0
Write-Host ''
if ($DryRun) { Write-Host 'Dry run: nothing was run.' -ForegroundColor Cyan }
elseif ($Only) { Write-Host "Done: $Only." -ForegroundColor Cyan }
else {
    Write-Host 'Done. Start tvOS with Start-tvOS.cmd or the Start menu shortcut.' -ForegroundColor Cyan
    Preview-Notice
}

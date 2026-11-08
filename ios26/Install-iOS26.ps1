# ASoftware iOS 26 installer: from a fresh Windows PC to a bootable iOS 26 (the research preview),
# as far as that can be scripted. It runs README.md's Build steps in order (the Linux ones through
# bash scripts it writes to <Work>\install\sh, run in WSL or in the helper VM: -Linux) and leaves a
# marker per step in <Work>\install, so running it again goes on where it stopped; redoing a disk
# step redoes the disk steps after it.
#
# The guest GPU driver (the menu's GpuMode): cloudos takes Apple's AppleParavirtGPUMetalIOGPUFamily.bundle
# out of the cloudOS IPSW it downloads anyway (the OS image carries its own AEA key) and adds the
# Metal compiler plugin cloudOS lacks, our CI build of vphone-cli's GraphicLoader ($GpuPluginRelease,
# or -GpuPlugin FILE); gpu copies a bundle folder you chose as it is; gpuless has no GPU layer
# (slower). Change it later (the menu's [G]) and run this again: it redoes the GPU layer and the
# wallpaper.
# The Linux steps (HFS+ and APFS disks) need Linux's file systems. -Linux wsl runs them in WSL 2,
# which needs an administrator and a restart to install (the installer says so and stops); -Linux
# helper runs them in the helper VM, installer\helper's small arm64 Linux in our QEMU, as the iOS 16
# installer does: no WSL, no administrator, slower (TCG). There ipsw.exe (blacktop/ipsw for
# Windows) decrypts Apple's images and unwraps the firmware on Windows itself.
# Our QEMU comes as a release package it downloads and checks ($QemuRelease below); -QemuFrom
# source builds it in MSYS2 instead (hours), -QemuFrom <folder> copies a build you have.
#
#   Install-iOS26.cmd [-Work D:\ios26] [-List] [-Check] [-DryRun] [-From STEP | -Only STEP] ...
#     -List          the steps, the README.md step each one runs, and which are done
#     -Check         what this PC has (Windows, the Linux tools, QEMU, the outputs); changes nothing
#     -Linux auto|wsl|helper   where the Linux steps run: WSL 2, or the helper VM; auto (the
#                    default): WSL if it is installed, else the helper VM. Remembered
#     -DryRun        print every command the steps would run; runs nothing
#     -From STEP     redo STEP and every step after it; -Only STEP redoes just that one (a disk
#                    step: the disk steps after it are redone on the next run)
#     -Collections   also build the lighter Collections wallpaper disk (README.md 5.3.6), as when
#                    the menu's wallpaper is collections; remembered (-NoCollections forgets it)
#     -QemuFrom auto|release|source|<folder>   auto: the release package set below (when it
#                    cannot be downloaded and MSYS2 is installed: source); with none set, the
#                    QEMU the work folder has, else source if MSYS2 is installed
#     -CloudOsIpsw / -IPhoneIpsw FILE   take Apple's files from an IPSW you have
#     -GpuPlugin FILE  the GPU driver's compiler plugin (GpuMode cloudos) from a file you have,
#                    not the release's download
#     -BakeMinutes N how long the wallpaper boot leaves iOS running once it is up (6)
#     -KeepBuildFiles  keep the decrypted images and the intermediate disk (about 32 GB)
# Folders, saved in the menu's config (%LOCALAPPDATA%\ASoftware iOS 26\ios26.config.json):
#   -Work (ASOFT26)      Apple's files, the disks and the runs; a drive-letter path without
#                        spaces. Default: the config's, else <fixed drive with most room>:\ios26.
#                        It never rebuilds disks it did not make: a folder with disks but no
#                        install\ (built by hand) is refused; give it a new or empty one
#   -Src (ASOFT26_SRC)   sources and the QEMU build (-QemuFrom source)
#   -LinuxDir (ASOFT26_LINUX)  scratch space inside WSL (/root/ios26)
#   -Distro              the WSL distro (the config's, else ios-emu, made if missing)
param(
    [string]$Work = '',
    [string]$Src = '',
    [string]$Distro = '',
    [string]$LinuxDir = '',
    [string]$Config = (Join-Path $env:LOCALAPPDATA 'ASoftware iOS 26\ios26.config.json'),
    [string]$QemuFrom = 'auto',
    [string]$CloudOsIpsw = '',
    [string]$IPhoneIpsw = '',
    [string]$GpuPlugin = '',
    [string]$From = '',
    [string]$Only = '',
    [switch]$DryRun,
    [switch]$Check,
    [switch]$List,
    [switch]$Collections,
    [switch]$NoCollections,
    [ValidateRange(1, 120)][int]$BakeMinutes = 6,
    [switch]$KeepBuildFiles,
    [switch]$NoShortcut,
    [ValidateSet('', 'auto', 'wsl', 'helper')][string]$Linux = ''
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = Split-Path $here

# --- What it downloads, pinned (one place) -------------------------------------------------------
# Our QEMU for Windows as a release package: win-build.sh's dist (qemu-system-aarch64.exe and the
# windowless w.exe, qemu-img.exe, the ANGLE, GTK and GLib runtime) zipped, 125 MB. 2026.11.03 is
# qemu-sptm asoft 7364c4e (-M vresearch, and -M virt for iOS 16) with reims-vgpu windows fd7bd0b5
# and metal2vulkan windows 79e1dd02. For a new build, installer\Make-QemuPackage.ps1 prints this line.
$QemuRelease = @{ Version = '2026.11.03'; Url = 'https://github.com/alpersamur3/qemu-sptm/releases/download/asoft-7364c4e/asoft-qemu-2026.11.03.zip'; Sha256 = 'C0D48F95ABEB467D8AFDE898BF2987123C60F19D62CFC8400C446F0569E4D5C2' }
# -QemuFrom source: the checkouts README.md step 1 clones, and the oldest commit of each the
# launcher works with (README.md, "Start menu and setup")
$Sources = @(
    @{ Dir = 'qemu-sptm'; Url = 'https://github.com/alpersamur3/qemu-sptm'; Branch = 'asoft'; Min = '7364c4e' }
    @{ Dir = 'reims-vgpu'; Url = 'https://github.com/alpersamur3/reims-vgpu'; Branch = 'windows'; Min = 'fd7bd0b5' }
    @{ Dir = 'metal2vulkan-win'; Url = 'https://github.com/alpersamur3/metal2vulkan'; Branch = 'windows'; Min = '79e1dd02' }
)
# MSYS2 UCRT64 packages: QEMU's build dependencies, plus Rust (reims-vgpu) and GMP (nettle's hogweed)
$MsysPackages = @('bison', 'diffutils', 'flex', 'git', 'grep', 'make', 'sed', 'tar', 'gzip', 'curl') +
    @('binutils', 'gcc', 'pkgconf', 'ninja', 'python', 'python-certifi', 'python-setuptools', 'python-wheel',
      'glib2', 'pixman', 'zstd', 'capstone', 'libslirp', 'gtk3', 'libepoxy', 'angleproject', 'SDL2', 'rust', 'gmp' |
      ForEach-Object { "mingw-w64-ucrt-x86_64-$_" })
# URL, SHA-256
$Pin = @{
    # python.org's embeddable Python for the Windows-side tools (MD5 as python.org lists it: fe8ef205...)
    Python  = @('https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip',
                '4ACBED6DD1C744B0376E3B1CF57CE906F9DC9E95E68824584C8099A63025A3C3')
    # darwin-vm's prebuilt iOS sysroot (bash, coreutils): the shell ramdisk and the root
    Sysroot = @('https://raw.githubusercontent.com/jprx/darwin-vm/edfc19433da8d04d5927a7b1932acce4034f307c/sysroot/ios_sysroot.tar.gz',
                'EE27653106055A6046428465D1CF68F5DFDC1BE5E9B6FFDF402BDD0B6034A8DC')
    # vresearch_dt_fixup.py of qemu-sptm asoft 52f3606, which dt-root26smp.py builds the device tree with
    DtFixup = @('https://raw.githubusercontent.com/alpersamur3/qemu-sptm/52f360682d261c03b3db94ced1ce1c8303a96478/scripts/darwin/vresearch_dt_fixup.py',
                '6DE7F5834430322DCBC0D7C09D99AE9B9D7E0A1E1F9C307CC3FF302FCCE5E608')
    # GNU nettle for win-nettle.sh (-QemuFrom source)
    Nettle  = @('https://ftp.gnu.org/gnu/nettle/nettle-3.10.1.tar.gz',
                'B0FCDD7FC0CDEA6E80DCF1DD85BA794AF0D5B4A57E26397EEE3BC193272D9132')
    # blacktop/ipsw for Windows (-Linux helper), the version wsl-setup.sh puts in WSL
    Ipsw    = @('https://github.com/blacktop/ipsw/releases/download/v3.1.739/ipsw_3.1.739_windows_x86_64.zip',
                '43D311CF87FFAB0617845B10FBF45D38518D63CB09484FD00D30DA23B21D8A79')
}
# Apple's files, from Apple's servers: cloudOS 26.4b (23E5207q), the IPSW of the Private Cloud
# Compute research VM (vphone600; the URL as vphone-cli's firmware catalog has it), and the
# iPhone17,3 iOS 26.6.2 (23G90) IPSW. Only these members are fetched (HTTP ranges, ipsw-get.py).
$CloudOsUrl = 'https://updates.cdn-apple.com/private-cloud-compute/c0ecdb4b310cf5239ab2b248dd3098eec297dc5aa3bbe6ada27273262b0b8b64'
$IPhoneUrl = 'https://updates.cdn-apple.com/2026SummerFCS/29d685ce-f70d-45a0-9823-b1cd115f3927/iPhone17,3_26.6.2_23G90_Restore.ipsw'
$CloudOsFiles = [ordered]@{    # member = bytes; into <Work>\cloudos, as in the IPSW
    'kernelcache.research.vphone600'                 = 14447937
    'kernelcache.release.vphone600'                  = 14124537
    'Firmware/sptm.vresearch1.release.im4p'          = 110129
    'Firmware/txm.iphoneos.research.im4p'            = 157084
    'Firmware/all_flash/DeviceTree.vphone600ap.im4p' = 8043
    '094-39914-031.dmg'                              = 232783899
    'Firmware/094-39914-031.dmg.trustcache'          = 7967
    # the OS image, only for the guest GPU driver (GpuMode cloudos; the gpu step removes it once
    # used), and the trust cache that lists the driver's CDHash
    '094-39278-029.dmg.aea'                          = 754974720
    'Firmware/094-39278-029.dmg.aea.trustcache'      = 6287
}
$CloudOsGpuImage = '094-39278-029.dmg'    # the cloudOS OS (AEA; its key is in its own header)
$OsImage = '094-97246-090.dmg'       # the OS (AEA)
$SysOsImage = '094-95368-092.dmg'    # the SystemOS cryptex (AEA)
$AppOsImage = '094-96441-094.dmg'    # the AppOS cryptex
$IPhoneFiles = [ordered]@{     # member = bytes; into <Work>\iphone, without the folder
    "$OsImage.aea"                        = 8187281408
    "$SysOsImage.aea"                     = 2013265920
    $AppOsImage                           = 14680064
    "Firmware/$OsImage.aea.trustcache"    = 85513
    "Firmware/$SysOsImage.aea.trustcache" = 2807
    "Firmware/$AppOsImage.trustcache"     = 431
}
# README.md 5.3's patches of the 23G90 dyld shared cache: address, old bytes, new bytes; and the
# subcaches they (and edge-patch.py, 5.4) are in, which are all the apps step copies off the disk
$DscPosterBoard = @('0x220649088', 'f6179f1a20070034', '3600805239000014')
$DscCollections = @('0x22066ebc0', 'a0000054', '05000014')
# Always On Display: libMobileGestalt's AlwaysOnDisplayFlipbook answer, mov w0,#1 -> mov w0,#0 (its
# "AlwaysOnTime, so a flipbook" shortcut): backboardd asserts on the paravirtual display's missing
# hardware flipbook otherwise. With dt-aod.py's /arm-io/disp0 and root26-aod.py (Auto-Lock Never).
$DscAod = @('0x1b22c75fc', '20008052', '00008052')
# The side button: SpringBoard's -[SBLockHardwareButtonActions disallowsLongPressForReason:] answers YES
# (mov w0,#1; ret). Under TCG SpringBoard's main thread stalls ~0.6 s on the press itself (iOS 26's
# button hint droplet), past the 0.4 s long-press time, so a click came out as a long press for Siri
# (there is no Siri here) and did nothing; without the long press a click is always a click. In the
# .42, on top of PosterBoard's patch.
$DscLockLongPress = @('0x224448a10', '7f2303d5f657bda9', '20008052c0035fd6')
$DscFiles = @('dyld_shared_cache_arm64e.42', 'dyld_shared_cache_arm64e.03', 'dyld_shared_cache_arm64e.15')
$GpuBundle = 'AppleParavirtGPUMetalIOGPUFamily.bundle'
# The guest GPU driver's Metal compiler plugin (GpuMode cloudos), which no cloudOS has: not Apple's
# but vphone-cli's GraphicLoader (MIT), built by .github/workflows/graphicloader.yml (arm64e, ad-hoc
# signed) with ios26/graphicloader/main.mm.patch, published as a release of this repository:
# graphicloader-9cadb5c is vphone-cli 57bbc93 + that patch (which also compiles OpenGL ES shaders),
# workflow run 41362155319 (Xcode 26.6, iphoneos SDK 26.5), CDHash f1f51a9a03dab30edcf5a33095942dd24dd41b05
$GpuPluginRelease = @{ Name = 'libAppleParavirtCompilerPluginIOGPUFamily.dylib'; Url = 'https://github.com/alpersamur3/asoft-ios/releases/download/graphicloader-9cadb5c/libAppleParavirtCompilerPluginIOGPUFamily.dylib'; Sha256 = '089E725E7733B0B84F5F7821E80DF4E7FC12BD876DD84D753493FA51BD57B8A5' }
# GB (10^9) a step adds on the work folder's drive at most, measured on our build; a build from
# nothing peaks at about 49 GB (during partition) and keeps about 25 GB
$Space = @{ cloudos = 1.1; iphone = 10.3; decrypt = 10.3; rootfs = 23.5; partition = 18.5; apps = 3.5
            gpu = 1.5; wallpaper = 3.0; collections = 1.5; qemu = 1.5 }

# --- Output, running tools ---------------------------------------------------------------------
function Step([string]$text) { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }
function Say([string]$text, [string]$color = 'Gray') { Write-Host "  $text" -ForegroundColor $color }
function Fail([string]$why) { throw $why }
function Q([string]$a) { if ($a -eq '' -or $a -cmatch '[\s"]') { '"' + $a + '"' } else { $a } }
function Show-Cmd([string]$text) { Write-Host "  > $text" -ForegroundColor DarkGray }

# A native tool, or with -DryRun only its command line. Its output goes to the screen and the
# step's log; a non-zero exit fails the step unless -NoFail ($script:Code has it). Windows
# PowerShell 5.1 turns a native tool's stderr into errors: here they are just lines.
$script:Log = $null
$script:Code = 0
function Run([string]$exe, [string[]]$argv, [switch]$NoFail, [switch]$Quiet, [switch]$Direct) {
    Show-Cmd ((@($exe) + $argv | ForEach-Object { Q $_ }) -join ' ')
    $script:Code = 0
    if ($DryRun) { return , @() }
    $lines = New-Object System.Collections.Generic.List[string]
    $w = if ($script:Log) { New-Object System.IO.StreamWriter($script:Log, $true) } else { $null }
    try {
        $ErrorActionPreference = 'Continue'
        if ($Direct) {
            # straight to the console (curl's progress meter): not captured, not in the log
            & $exe @argv
            if ($w) { $w.WriteLine("> $exe $($argv -join ' ')   (its output was on the screen only)") }
        } else {
            & $exe @argv 2>&1 | ForEach-Object {
                # a native tool's stderr line arrives as an error record (an empty one prints as its type)
                $t = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
                $l = ("$t" -replace "`0", '').TrimEnd()
                $lines.Add($l)
                if ($w) { $w.WriteLine($l) }
                if (-not $Quiet) { Write-Host "    $l" }
            }
        }
        $script:Code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = 'Stop'
        if ($w) { $w.Close() }
    }
    if ($script:Code -and -not $NoFail) { Fail "$([IO.Path]::GetFileName($exe)) exited with $($script:Code)" }
    return , $lines.ToArray()
}
function Py([string]$script, [string[]]$argv, [switch]$NoFail) {
    Run $Py (@('-I', '-B', (Join-Path $Scripts $script)) + $argv) -NoFail:$NoFail
}

# Windows paths as WSL and MSYS2 see them
function To-Wsl([string]$p) {
    $f = [IO.Path]::GetFullPath($p)
    '/mnt/' + $f.Substring(0, 1).ToLowerInvariant() + ($f.Substring(2) -replace '\\', '/')
}
function To-Msys([string]$p) {
    $f = [IO.Path]::GetFullPath($p)
    '/' + $f.Substring(0, 1).ToLowerInvariant() + ($f.Substring(2) -replace '\\', '/')
}

# A bash script for WSL: the prelude (the folders, the disk tools, in_root, overlay) and the
# step's body, written to <Work>\install\sh\NAME.sh and run as root in the build distro
function Prelude([string]$name) {
    $p = @'
#!/bin/bash
# Install-iOS26.ps1, {NAME}: written by the installer, run as root in WSL ({DISTRO})
set -euo pipefail
export ASOFT26={A} ASOFT26_LINUX={L}
A=$ASOFT26 L=$ASOFT26_LINUX S=$ASOFT26/scripts
export A L S
KVER=$(uname -r)
export HFSPLUS_KO=/root/work/wsl-kernel/linux-msft-wsl-${KVER%%-*}/fs/hfsplus/hfsplus.ko
mkdir -p "$L"
cd "$A"
# nbd and hfsplus loaded, and the first two free nbd devices from /dev/nbd12 as NBD and NBD2 (a
# mount namespace WSL leaked can keep one busy until WSL restarts)
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
# in_root DISK: the script on stdin, run on DISK's root mounted read-write as $R (root26-do.sh)
in_root() {
	local f
	f=$(mktemp /tmp/asoft-in-root.XXXXXX)
	cat > "$f"
	bash "$S/root26-do.sh" "$A/$1" "set -euo pipefail; . $f"
	rm -f "${f:?}"
}
# overlay BASE NEW: NEW, a new qcow2 overlay on BASE (its name relative, as the launcher's)
overlay() {
	local new=${A:?}/${2:?}
	rm -f "${new:?}"
	qemu-img create -q -f qcow2 -b "$1" -F qcow2 "$new"
	echo "$2: an overlay on $1"
}
# fresh PATH...: what the step makes anew, removed first
fresh() {
	local f
	for f; do rm -rf "${A:?}/${f:?}"; done
}
'@
    $p.Replace('{NAME}', $name).Replace('{DISTRO}', $Distro).Replace('{A}', (To-Wsl $Work)).Replace('{L}', $LinuxDir)
}
# The same for the helper VM (-Linux helper, Run-Helper): its tools are in the VM, the disks are
# QEMU's (linked where the files would be), and what the prelude's overlay and fresh do on the
# Windows side the installer did before the VM started
function Helper-Prelude([string]$name) {
    $p = @'
#!/bin/bash
# Install-iOS26.ps1, {NAME}: written by the installer, run as root in the helper VM (installer\helper)
set -euo pipefail
export ASOFT26=/work ASOFT26_LINUX=/root/ios26
A=$ASOFT26 L=$ASOFT26_LINUX S=$ASOFT26/scripts
export A L S
mkdir -p "$L"
cd "$A"
disk_tools() {
	grep -q hfsplus /proc/filesystems || { echo "the helper VM's kernel has no hfsplus"; exit 1; }
}
in_root() {
	local f
	f=$(mktemp /tmp/asoft-in-root.XXXXXX)
	cat > "$f"
	bash "$S/root26-do.sh" "$A/$1" "set -euo pipefail; . $f"
	rm -f "${f:?}"
}
overlay() {
	[ -b "$A/${2:?}" ] || { echo "$2 is not one of this VM's disks"; exit 1; }
	echo "$2: an overlay on $1"
}
fresh() { :; }
'@
    $p.Replace('{NAME}', $name)
}
# A Linux step's bash script, in WSL or in the helper VM (-Linux). The helper VM sees no Windows
# folder: -Disks are the disks QEMU opens for it, -In the files (relative to the work folder) it
# gets, -Out the files it hands back (Run-Helper); WSL ignores them.
function Run-Linux([string]$name, [string]$body, [object[]]$Disks = @(), [string[]]$In = @(), [string[]]$Out = @()) {
    if ($LinuxMode -ceq 'helper') { Run-Helper $name $body $Disks $In $Out } else { Run-Wsl $name $body }
}
# A Linux step's body: steps\NAME.sh beside this script (the Android app's setup reads the same files),
# its {PLACEHOLDERS} filled by the caller. Read from this release's own folder, never from a work folder.
function Step-Body([string]$name) {
    $f = Join-Path $here "steps\$name.sh"
    if (-not (Test-Path $f)) { Fail "no $f (this installer comes with its steps folder)" }
    ([IO.File]::ReadAllText($f) -replace "`r`n", "`n").TrimEnd("`n")
}
function Run-Wsl([string]$name, [string]$body) {
    $file = Join-Path $Work "install\sh\$name.sh"
    if ($DryRun) {
        Show-Cmd "wsl -d $Distro -u root -- bash $(To-Wsl $file)   (the prelude, then:)"
        foreach ($l in ($body.Trim() -split "`n")) { Write-Host ('      ' + $l.TrimEnd()) -ForegroundColor DarkGray }
        return , @()
    }
    New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
    # (a here-string ends without its last newline)
    $text = ((Prelude $name) + "`n" + $body.Trim() + "`n") -replace "`r`n", "`n"
    [IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding $false))
    $env:WSL_UTF8 = '1'
    Run 'wsl.exe' @('-d', $Distro, '-u', 'root', '--', 'bash', (To-Wsl $file))
}

# --- The helper VM (-Linux helper) -------------------------------------------------------------
# installer\helper's arm64 Linux (the linux step copies it to <Work>\tools\helper) in our QEMU, as
# the iOS 16 installer's Build-iOSDisk.ps1 runs it. Its job run (installer\helper\job-run.sh) takes
# a tar on the disk with serial in: the step's script (Helper-Prelude and the body), scripts\, the
# step's input files and .job\ (run: the script; disks: where each disk is linked, so the script
# finds it where it would find the file; out: what to hand back), and puts the outputs on the disk
# with serial out as a tar. QEMU opens the disks: the qcow2s with their backing chains, Apple's
# images raw (a UDIF image's size must be a multiple of 512: apfs-fuse reads its trailer from the
# disk's last sector).
#   Disks: @{ rw = 'root26g.qcow2' }, @{ ro = "os/$OsImage" }, @{ new = 'root26.qcow2'; size = '32G' },
#          each with at = where the script finds it, if not at that path in the work folder. The
#          body's in_root DISK and overlay BASE NEW lines add DISK and NEW (rw).
# The body's overlay and fresh lines are done here, before the VM starts.
$HelperCpus = [Math]::Min(8, [Environment]::ProcessorCount)
function Helper-Args([string]$job, [string[]]$drives) {
    $h = In-Work 'tools\helper'
    # cortex-a76, not max: pointer authentication, which max has, is slow under TCG
    @('-M', 'virt', '-cpu', 'cortex-a76', '-smp', "$HelperCpus", '-m', '4G',
      '-kernel', (Join-Path $h 'Image.gz'), '-initrd', (Join-Path $h 'initrd.gz'),
      '-append', "console=ttyAMA0 loglevel=4 asoft.job=$job",
      '-display', 'none', '-monitor', 'none', '-serial', 'stdio', '-no-reboot', '-nic', 'none') + $drives
}
function Helper-Drive([string]$file, [string]$id, [string]$format, [string]$more = '') {
    # (a comma in a -drive file name is doubled)
    @('-drive', "file=$($file -replace ',', ',,'),format=$format,if=none,id=$id$more", '-device', "virtio-blk-device,drive=$id,serial=$id")
}
function Helper-Done([string[]]$lines) {
    $l = $lines | Where-Object { "$_" -cmatch '^ASOFT: done -?\d+' } | Select-Object -Last 1
    if ($l -and "$l" -cmatch '^ASOFT: done (-?\d+)') { [int]$Matches[1] } else { $null }
}
function Plain-Rel([string]$p) { $p -cmatch '^[A-Za-z0-9_.+-]+(/[A-Za-z0-9_.+-]+)*$' -and $p -cnotmatch '(^|/)\.\.?(/|$)' }
# a file's size through a link too
function File-Size([string]$f) { $s = [IO.File]::OpenRead($f); try { $s.Length } finally { $s.Close() } }
function Run-Helper([string]$name, [string]$body, [object[]]$disks, [string[]]$in, [string[]]$out) {
    $img = In-Work 'qemu\qemu-img.exe'
    $fresh = @([regex]::Matches($body, '(?m)^fresh (.+)$') | ForEach-Object { $_.Groups[1].Value.Trim() -split '\s+' })
    $overlays = @([regex]::Matches($body, '(?m)^overlay (\S+) (\S+)\s*$') | ForEach-Object { , @($_.Groups[1].Value, $_.Groups[2].Value) })
    $all = @($disks | Where-Object { $_ })
    $named = @($all | ForEach-Object { if ($_.rw) { $_.rw } elseif ($_.ro) { $_.ro } else { $_.new } })
    $used = @($overlays | ForEach-Object { $_[1] }) + @([regex]::Matches($body, '(?m)^in_root (\S+)') | ForEach-Object { $_.Groups[1].Value })
    foreach ($d in $used) { if ($named -cnotcontains $d) { $all += @{ rw = $d }; $named += $d } }
    # what is left for the VM once the overlays and removals are done here
    $vm = @($body.Trim() -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -cnotmatch '^(disk_tools|overlay \S+ \S+|fresh .+)$' })
    $file = In-Work "install\sh\$name.sh"
    if ($DryRun) {
        foreach ($f in $fresh) { Show-Cmd "del $f   (if there)" }
        foreach ($o in $overlays) { Show-Cmd "qemu-img create -f qcow2 -b $($o[0]) -F qcow2 $($o[1])" }
        foreach ($d in $all) { if ($d.new) { Show-Cmd "qemu-img create -f qcow2 $($d.new) $($d.size)" } }
        if (-not $vm) { return , @() }
        Show-Cmd "helper VM ($HelperCpus CPUs), job run: bash /work/install/sh/$name.sh   (the prelude, then:)"
        foreach ($l in ($body.Trim() -split "`n")) { Write-Host ('      ' + $l.TrimEnd()) -ForegroundColor DarkGray }
        foreach ($d in $all) {
            $what = if ($d.ro) { "$($d.ro) (read-only)" } elseif ($d.new) { "$($d.new) (new)" } else { $d.rw }
            Show-Cmd ("  disk $what" + $(if ($d.at) { " at $($d.at)" } else { '' }))
        }
        if ($in) { Show-Cmd "  in: $($in -join ' ')" }
        if ($out) { Show-Cmd "  out: $($out -join ' ')" }
        return , @()
    }
    foreach ($f in $fresh) {
        if (-not (Plain-Rel $f)) { Fail "fresh $f`: not a plain relative path" }
        if (Test-Path (In-Work $f)) { Show-Cmd "del $f"; Remove-Item (In-Work $f) -Recurse -Force }
    }
    foreach ($o in $overlays) {
        Remove-Item (In-Work $o[1]) -ErrorAction SilentlyContinue
        $null = Run $img @('create', '-q', '-f', 'qcow2', '-b', $o[0], '-F', 'qcow2', (In-Work $o[1]))
        Say "$($o[1]): an overlay on $($o[0])"
    }
    foreach ($d in $all) {
        if (-not $d.new) { continue }
        Remove-Item (In-Work $d.new) -ErrorAction SilentlyContinue
        $null = Run $img @('create', '-q', '-f', 'qcow2', (In-Work $d.new), "$($d.size)")
    }
    if (-not $vm) { return , @() }

    $dir = In-Work "install\helper\$name"
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory -Force (Join-Path $dir '.job'), (Split-Path $file) | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $text = ((Helper-Prelude $name) + "`n" + $body.Trim() + "`n") -replace "`r`n", "`n"
    [IO.File]::WriteAllText($file, $text, $utf8)
    $drives = @()
    $links = @()
    $i = 0
    foreach ($d in $all) {
        $rel = if ($d.rw) { $d.rw } elseif ($d.ro) { $d.ro } else { $d.new }
        $f = In-Work ($rel -replace '/', '\')
        if (-not (Test-Path $f -PathType Leaf)) { Fail "$rel is not in $Work" }
        $format = if ($f -like '*.qcow2') { 'qcow2' } else { 'raw' }
        if ($format -ceq 'raw' -and (File-Size $f) % 512) { Fail "$rel is $(File-Size $f) bytes, not a multiple of 512: the helper VM cannot read it as a disk" }
        $more = if ($d.ro) { ',readonly=on' } elseif ($d.new) { ',cache=unsafe' } else { '' }
        $drives += Helper-Drive $f "d$i" $format $more
        $links += "d$i $(if ($d.at) { $d.at } else { $rel })"
        $i++
    }
    [IO.File]::WriteAllText((Join-Path $dir '.job\run'), "install/sh/$name.sh`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $dir '.job\disks'), (($links -join "`n") + "`n"), $utf8)
    [IO.File]::WriteAllText((Join-Path $dir '.job\out'), $(if ($out) { ($out -join "`n") + "`n" } else { '' }), $utf8)
    $items = @('scripts', "install/sh/$name.sh") + @($in | Where-Object { $_ })
    foreach ($p in $items) { if (-not (Plain-Rel $p) -or -not (Test-Path (In-Work $p))) { Fail "the helper VM's input $p is not in $Work" } }
    $tar = Join-Path $dir 'in.tar'
    $outQ = Join-Path $dir 'out.qcow2'
    $outT = Join-Path $dir 'out.tar'
    try {
        $null = Run 'tar.exe' (@('-cf', $tar, '-C', $Work) + $items + @('-C', $dir, '.job')) -Quiet
        $null = Run $img @('create', '-q', '-f', 'qcow2', $outQ, '8G')
        $drives = (Helper-Drive $tar 'in' 'raw' ',readonly=on') + (Helper-Drive $outQ 'out' 'qcow2' ',cache=unsafe') + $drives
        Say "the helper VM ($HelperCpus CPUs, TCG) runs $name.sh"
        $t0 = Get-Date
        $lines = Run (In-Work 'qemu\qemu-system-aarch64.exe') (Helper-Args 'run' $drives)
        $rc = Helper-Done $lines
        Say ("helper VM: {0:N1} min, exit {1}" -f ((Get-Date) - $t0).TotalMinutes, $(if ($null -eq $rc) { 'unknown' } else { $rc }))
        if ($rc -ne 0) { Fail "the helper VM's $name.sh failed (its output is above and in the step's log)" }
        if ($out) {
            $l = $lines | Where-Object { "$_" -cmatch '^ASOFT: out \d+' } | Select-Object -Last 1
            if (-not $l -or "$l" -cnotmatch '^ASOFT: out (\d+)') { Fail 'the helper VM handed nothing back' }
            $mb = [Math]::Ceiling([double]$Matches[1] / 1MB)
            $null = Run $img @('dd', '-f', 'qcow2', '-O', 'raw', 'bs=1M', "count=$mb", "if=$outQ", "of=$outT")
            $null = Run 'tar.exe' @('-xf', $outT, '-C', $Work)
            Say "back from the helper VM: $($out -join ', ')"
        }
    } finally {
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
    , $lines
}

# ipsw.exe (blacktop/ipsw for Windows; the linux step puts it in <Work>\tools\ipsw): with -Linux
# helper, what the Linux steps' ipsw does (decrypt Apple's images, unwrap the firmware) runs here
function Ipsw([string[]]$argv, [switch]$Quiet) { Run (In-Work 'tools\ipsw\ipsw.exe') $argv -Quiet:$Quiet }
# ipsw fw aea AEA -o DIR, as sysos.sh, m2-decrypt.sh and cloudos-gpu-driver.sh run it
function Decrypt-Aea([string]$aea, [string]$dir) {
    if (-not $DryRun) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $null = Ipsw @('fw', 'aea', $aea, '-o', $dir)
}

# url -> file, resumable (curl -C -), its SHA-256 checked
function Get-File([string]$url, [string]$out, [string]$sha256) {
    if (-not $DryRun -and (Test-Path $out) -and (Get-FileHash $out -Algorithm SHA256).Hash -eq $sha256) {
        Say "have $([IO.Path]::GetFileName($out))"
        return
    }
    if (-not $DryRun) { New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null }
    $null = Run 'curl.exe' @('-fL', '--retry', '5', '-C', '-', '-o', $out, $url) -NoFail -Direct
    if ($DryRun) { return }
    # what is there cannot be resumed (curl 22/33/36: the server refused the range, say), or it is
    # complete but wrong: once more from the start. Other errors (the network) keep it for a resume.
    $again = $script:Code -in 22, 33, 36
    if (-not $script:Code -and (-not (Test-Path $out) -or (Get-FileHash $out -Algorithm SHA256).Hash -ne $sha256)) { $again = $true }
    if ($again) {
        Remove-Item $out -ErrorAction SilentlyContinue
        $null = Run 'curl.exe' @('-fL', '--retry', '5', '-o', $out, $url) -NoFail -Direct
    }
    if ($script:Code) { Fail "could not download $url (curl $($script:Code)); run again to resume" }
    $h = (Get-FileHash $out -Algorithm SHA256).Hash
    if ($h -ne $sha256) { Remove-Item $out; Fail "$url has SHA-256 $h, not $sha256 (removed it)" }
}

# One member of an IPSW (the URL, or an IPSW on this PC) with ipsw-get.py: resumable, CRC-checked.
# install\got\ marks the members fetched in full.
function Get-IpswMember([string]$from, [string]$member, [string]$out, [long]$size) {
    $ok = Join-Path $Work ('install\got\' + [IO.Path]::GetFileName($out) + '.ok')
    if (-not $DryRun -and (Test-Path $ok) -and (Test-Path $out) -and (Get-Item $out).Length -eq $size) {
        Say "have $member"
        return
    }
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force (Split-Path $out), (Split-Path $ok) | Out-Null
        Remove-Item $ok -ErrorAction SilentlyContinue
    }
    $null = Py 'ipsw-get.py' @($from, $member, $out)
    if (-not $DryRun) { Set-Content $ok $member }
}
function CloudOs-Source { if ($CloudOsIpsw) { [IO.Path]::GetFullPath($CloudOsIpsw) } else { $CloudOsUrl } }
function IPhone-Source { if ($IPhoneIpsw) { [IO.Path]::GetFullPath($IPhoneIpsw) } else { $IPhoneUrl } }
function In-Work([string]$rel) { Join-Path $Work $rel }

function Free-GB { ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($Work))).AvailableFreeSpace / 1e9 }
function Need-Space([double]$gb) {
    if ($gb -le 0) { return }
    $drive = [IO.Path]::GetPathRoot($Work)
    if ($DryRun) { Say ("needs about {0:N1} GB free on {1}" -f $gb, $drive) DarkGray; return }
    $free = Free-GB
    if ($free -lt $gb + 1) {
        Fail ("{0:N1} GB free on {1}; this step needs about {2:N0} GB: free some space (or use -Work on another drive)" -f $free, $drive, ($gb + 1))
    }
}

# --- Config (the menu's) -----------------------------------------------------------------------
function Read-Config {
    if (Test-Path $Config) { try { return (Get-Content $Config -Raw | ConvertFrom-Json) } catch { } }
    $null
}
function Save-Keys([hashtable]$keys) {
    $o = [ordered]@{}
    $c = Read-Config
    if ($c) { foreach ($p in $c.PSObject.Properties) { $o[$p.Name] = $p.Value } }
    foreach ($k in $keys.Keys) { $o[$k] = $keys[$k] }
    New-Item -ItemType Directory -Force (Split-Path $Config) | Out-Null
    ($o | ConvertTo-Json) | Set-Content -Encoding UTF8 $Config
}
function Gpu-Driver {
    $c = Read-Config
    if ($c -and "$($c.GpuMode)" -ceq 'gpu' -and $c.GpuDriver) { return [string]$c.GpuDriver }
    $null
}
# Where the GPU layer's driver comes from: cloudos (Apple's bundle out of the cloudOS IPSW, with the
# compiler plugin), folder (the bundle you chose, Gpu-Driver), or $null (GPU-less: no GPU layer)
function Gpu-Route {
    $c = Read-Config
    if ($c -and "$($c.GpuMode)" -ceq 'cloudos') { return 'cloudos' }
    if (Gpu-Driver) { return 'folder' }
    $null
}
# The compiler plugin GpuMode cloudos adds: -GpuPlugin's file, else the release's download
function Gpu-Plugin {
    if ($GpuPlugin) { [IO.Path]::GetFullPath($GpuPlugin) } else { In-Work "downloads\$($GpuPluginRelease.Name)" }
}
function Plugin-Sig {
    if (-not $GpuPlugin) { return $GpuPluginRelease.Sha256 }
    $f = Gpu-Plugin
    if (Test-Path $f -PathType Leaf) { (Get-FileHash $f -Algorithm SHA256).Hash } else { $f }
}
# why the gpu step (cloudos) cannot have the compiler plugin, or nothing
function Plugin-Missing {
    if ($GpuPlugin) {
        if (Test-Path (Gpu-Plugin) -PathType Leaf) { return $null }
        return "-GpuPlugin $(Gpu-Plugin) is not there"
    }
    if ($GpuPluginRelease.Url) { return $null }
    'no release of the compiler plugin is set ($GpuPluginRelease): give the plugin with -GpuPlugin FILE, ' +
        'or choose a driver bundle you have (the menu''s [G])'
}
function Want-Collections {
    # -Collections (remembered in the config as Collections; -NoCollections forgets it), or the
    # menu's wallpaper collections
    $c = Read-Config
    $Collections -or ($c -and (($c.Collections -eq $true -and -not $NoCollections) -or "$($c.Wallpaper)" -ceq 'collections'))
}

# --- Markers -----------------------------------------------------------------------------------
function Mark-File([string]$id) { Join-Path $Work "install\$id.done" }
function Get-Mark([string]$id) {
    $f = Mark-File $id
    if (Test-Path $f) { (Get-Content $f -Raw).Trim() } else { $null }
}
function Set-Mark([string]$id, [string]$sig) { Set-Content -Path (Mark-File $id) -Value $sig -Encoding UTF8 }
function Clear-Mark([string]$id) { Remove-Item (Mark-File $id) -ErrorAction SilentlyContinue }

# --- Disks the installer did not make ----------------------------------------------------------
# It never rebuilds a disk it did not make. A work folder with disks and no install\ (built by hand,
# say root26g.qcow2 under a chain of overlays) is refused before any step. In its own work folder,
# install\owned.txt lists the disk files it made: a step's files go in before the step runs, so one
# that failed half way is resumed. A disk file a step would delete, make again or change, there and
# not listed, stops the run before any step, unless -From or -Only names the step that makes it (the
# installer then takes it over).
$Writes = @{
    rootfs      = @('root26.qcow2', 'root26.qcow2.hashes')
    trustcache  = @('root26.tc')
    partition   = @('root26g.qcow2')
    tweaks      = @('root26g.qcow2')
    firstboot   = @('root26g.qcow2')
    persona     = @('root26g.qcow2')
    activation  = @('root26-activation.qcow2', 'root26-activation.tc')
    apps        = @('root26-apps.qcow2', 'root26-apps.tc')
    gpu         = @('root26-gpu.qcow2', 'root26-gpu.tc')
    wallpaper   = @('root.qcow2', 'root.tc')
    collections = @('root-collections.qcow2', 'root-collections.tc')
}
$Retired = @('root.qcow2', 'root.tc', 'root-collections.qcow2', 'root-collections.tc')    # Retire-Top's
function Foreign-Disks {
    if (-not (Test-Path $Work) -or (Test-Path (In-Work 'install'))) { return @() }
    @(Get-ChildItem $Work -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension.ToLowerInvariant() -cin '.qcow2', '.tc' } | ForEach-Object Name)
}
function Foreign-Message([string[]]$names) {
    $list = (@($names | Select-Object -First 6) -join ', ') + $(if ($names.Count -gt 6) { ', ...' } else { '' })
    "$Work already has disks this installer did not make ($list): it would rebuild them from scratch. " +
        'Give it another -Work, or move those disks away.'
}
function Get-Owned {
    $f = In-Work 'install\owned.txt'
    if (Test-Path $f) { @(Get-Content $f | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) } else { @() }
}
function Is-Owned([string]$name) { (Get-Owned) -ccontains $name }
function Add-Owned([string[]]$names) {
    $have = Get-Owned
    $new = @($names | Where-Object { $_ -and $have -cnotcontains $_ } | Select-Object -Unique)
    if (-not $new) { return }
    New-Item -ItemType Directory -Force (In-Work 'install') | Out-Null
    Add-Content (In-Work 'install\owned.txt') $new -Encoding ASCII
}
# one it deleted (a file put there later under that name is not its)
function Drop-Owned([string[]]$names) {
    $have = Get-Owned
    $keep = @($have | Where-Object { $names -cnotcontains $_ })
    if ($keep.Count -ne $have.Count) { Set-Content (In-Work 'install\owned.txt') $keep -Encoding ASCII }
}
# The disk files the steps this run runs (picked as the loop below picks them) would touch and the
# installer did not make: "file (step id)"
function Find-NotOwned {
    $owned = @(Get-Owned)
    $bad = @()
    $chain = $false
    $retireSeen = $false
    for ($i = 0; $i -lt $Steps.Count; $i++) {
        $s = $Steps[$i]
        if ($s.Kind -cne 'chain') { continue }
        $forced = ($From -and $i -ge $fromIdx) -or ($Only -ceq $s.Id)
        if (-not $forced) {
            if ($Only -or ($From -and $i -lt $fromIdx)) { continue }
            if ((Get-Mark $s.Id) -ceq (Step-Sig $s.Id) -and -not $chain) { continue }
        }
        $chain = $true
        if ($s.Id -ceq 'collections' -and -not (Want-Collections)) { continue }
        $touch = @($Writes[$s.Id])
        if ($i -le $wallIdx -and -not $retireSeen) { $touch += $Retired; $retireSeen = $true }
        $named = ($Only -ceq $s.Id) -or ($From -ceq $s.Id)
        foreach ($f in @($touch | Select-Object -Unique)) {
            if (-not (Test-Path (In-Work $f)) -or $owned -ccontains $f) { continue }
            if ($named -and $Writes[$s.Id] -ccontains $f) {
                Say "$f was not made by this installer: -From/-Only $($s.Id) takes it over" Yellow
                $owned += $f
                continue
            }
            $bad += "$f (step $($s.Id))"
        }
        $owned += $Writes[$s.Id]
    }
    $bad
}

# --- WSL ---------------------------------------------------------------------------------------
function Get-Wsl {
    # distro name -> WSL version, from wsl -l -v; Ok is false without WSL
    $env:WSL_UTF8 = '1'
    $d = @{}
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return @{ Ok = $false; Distros = $d } }
    $ErrorActionPreference = 'Continue'
    $out = & wsl.exe -l -v 2>&1 | ForEach-Object { ("$_" -replace "`0", '').Trim() }
    $ok = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = 'Stop'
    if ($ok) {
        foreach ($l in @($out | Select-Object -Skip 1)) {
            $f = @(($l -replace '^\*\s*', '') -split '\s+' | Where-Object { $_ })
            if ($f.Count -ge 3) { $d[$f[0]] = $f[-1] }
        }
    }
    @{ Ok = $ok; Distros = $d }
}

# --- Booting iOS for a step (the launcher, as the menu runs it) ----------------------------------
function Assert-Slot {
    # an iOS 16 QEMU (-M virt), or a -M vresearch one on other ports, may stay: it has ports of its own
    $q = @(Get-CimInstance Win32_Process -Filter "Name like 'qemu-system-%'" | Where-Object {
        $_.CommandLine -cmatch '-M\s+"?vresearch' -and $_.CommandLine -cmatch '(port=|127\.0\.0\.1:)445[123]\b' })
    if ($q) { Fail ("an iOS 26 QEMU is running (pid {0}): this step boots iOS and needs ports 4451-4453; close it first" -f (($q | ForEach-Object ProcessId) -join ', ')) }
    $busy = @(Get-NetTCPConnection -State Listen -LocalPort 4451, 4452, 4453 -ErrorAction SilentlyContinue)
    if ($busy) { Fail ("ports 4451-4453 are in use (pid {0}); this step boots iOS on them" -f (($busy | ForEach-Object OwningProcess) -join ', ')) }
}
# QEMU's QMP (127.0.0.1:4453), as the iOS 16 installer's first start
function Send-Qmp([string]$command) {
    Show-Cmd "QMP 127.0.0.1:4453 $command"
    if ($DryRun) { return }
    try {
        $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4453)
        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $writer = New-Object System.IO.StreamWriter($stream)
            $writer.AutoFlush = $true
            [void]$reader.ReadLine()
            $writer.WriteLine('{"execute":"qmp_capabilities"}'); [void]$reader.ReadLine()
            $writer.WriteLine("{`"execute`":`"$command`"}"); [void]$reader.ReadLine()
        } finally { $client.Close() }
    } catch {
        Say "QMP: $($_.Exception.Message)" Yellow
    }
}
# Start-iOS26.ps1 -Keep (iOS writes the disk itself) -NoQuickBoot -NoIpa, in its window
function Start-Guest([string]$name, [string[]]$more) {
    if (-not $DryRun) { Assert-Slot }
    $run = In-Work "runs\$name"
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $here 'Start-iOS26.ps1'),
           '-Work', $Work, '-Name', $name, '-Keep', '-NoQuickBoot', '-NoIpa') + $more
    Show-Cmd ('powershell ' + (($a | ForEach-Object { Q $_ }) -join ' '))
    if ($DryRun) { return @{ Pid = 0; Dir = $run; Proc = $null } }
    Remove-Item (Join-Path $run 'stderr.log') -ErrorAction SilentlyContinue
    # its own process with its output in a file: QEMU, which it starts and leaves running, must
    # not hold a pipe of ours open
    $out = In-Work "install\logs\launch-$name.txt"
    $p = Start-Process powershell.exe -ArgumentList ($a | ForEach-Object { Q $_ }) -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    $null = $p.Handle
    $p.WaitForExit()
    $text = @(Get-Content $out, "$out.err" -ErrorAction SilentlyContinue)
    foreach ($l in $text) { if ($l) { Write-Host "    $l" } }
    $line = $text | Where-Object { "$_" -cmatch '^started .* pid \d+ -> ' } | Select-Object -Last 1
    if (-not $line -or -not ("$line" -cmatch 'pid (\d+) -> (.+)$')) { Fail 'the launcher did not start QEMU (its output is above)' }
    $id = [int]$Matches[1]
    @{ Pid = $id; Dir = $Matches[2].Trim(); Proc = (Get-Process -Id $id -ErrorAction SilentlyContinue) }
}
function Guest-Alive($g) { $g.Proc -and -not $g.Proc.HasExited }
# Run commands in the guest's root shell (guest-shell.py, console on 4451)
function Guest([int]$wait, [string[]]$cmds, [switch]$NoFail) {
    Py 'guest-shell.py' (@('4451', "$wait") + $cmds) -NoFail:$NoFail
}
function Wait-Ui($g, [int]$minutes) {
    $log = Join-Path $g.Dir 'stderr.log'
    Say "waiting for iOS's UI: 'frame N shown' with N >= 5 in $log (up to $minutes min)"
    if ($DryRun) { return }
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalMinutes -lt $minutes) {
        if (-not (Guest-Alive $g)) { Fail "QEMU ended before iOS's UI was up; see $($g.Dir)" }
        $n = 0
        $t = Get-Content $log -Raw -ErrorAction SilentlyContinue
        if ($t) { foreach ($m in [regex]::Matches($t, 'frame (\d+) shown')) { $n = [Math]::Max($n, [int]$m.Groups[1].Value) } }
        if ($n -ge 5) { Write-Progress -Activity 'iOS' -Completed; Say ("UI up after {0:N0} min" -f ((Get-Date) - $t0).TotalMinutes); return }
        Write-Progress -Activity 'iOS' -Status ("starting ({0:N0} min, frame {1})" -f ((Get-Date) - $t0).TotalMinutes, $n)
        Start-Sleep -Seconds 10
    }
    Fail "iOS showed no UI in $minutes minutes; see $($g.Dir)"
}
function Wait-Running($g, [int]$seconds, [string]$what) {
    Say "leaving iOS running for $([int]($seconds / 60)) min: $what"
    if ($DryRun) { return }
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $seconds) {
        if (-not (Guest-Alive $g)) { Fail "QEMU ended (the window was closed?) before $what; run again to redo this step" }
        $left = $seconds - ((Get-Date) - $t0).TotalSeconds
        Write-Progress -Activity 'iOS' -Status $what -SecondsRemaining ([int]$left) -PercentComplete ([Math]::Min(100, 100 * (1 - $left / $seconds)))
        Start-Sleep -Seconds 10
    }
    Write-Progress -Activity 'iOS' -Completed
}
# The launcher gives iOS the PC's time zone, region and clock over the serial shell once it is up
# (scripts\guest-clock.py, its log in the run folder): let it finish before Stop-Guest takes the
# console, so the disk is made with them
function Wait-PcTime($g) {
    $log = Join-Path $g.Dir 'host-time.log'
    Say "the PC's time zone, region and clock in iOS: $log"
    if ($DryRun) { return }
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalMinutes -lt 10 -and (Get-CimInstance Win32_Process -Filter "Name like 'python%'" |
           Where-Object { $_.CommandLine -and $_.CommandLine.Contains($log) })) { Start-Sleep -Seconds 5 }
    $lines = @(Get-Content $log -ErrorAction SilentlyContinue)
    if ($lines) { foreach ($l in $lines) { Say "  $l" DarkGray } }
    else { Say 'not set here (the launcher found no Python, or they were set before); the first start sets them' Yellow }
}
# DataMigration (root26-staged.py has it run in this boot) puts LastSystemVersion back into
# com.apple.migration when it is done; a disk stopped before that runs it again at every start from
# it, under the Apple logo's progress bar (20 min and more)
function Wait-Migration($g, [int]$minutes) {
    $plist = '/var/mobile/Library/Preferences/com.apple.migration.plist'
    Say "waiting for DataMigration to finish: LastSystemVersion in $plist (up to $minutes min, about 50 on our PC)"
    Say "the bar under the Apple logo can sit still that long, and the screen goes dark after the lock screen: leave the window open"
    if ($DryRun) { return }
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalMinutes -lt $minutes) {
        if (-not (Guest-Alive $g)) { Fail "QEMU ended (the window was closed?) before DataMigration was done; run again to redo this step" }
        $ErrorActionPreference = 'Continue'
        try { $out = & $Py -I -B (Join-Path $Scripts 'guest-shell.py') 4451 60 "cat $plist" 2>&1 | Out-String }
        finally { $ErrorActionPreference = 'Stop' }
        if ($out.Contains('LastSystemVersion')) {
            Write-Progress -Activity 'iOS' -Completed
            Say ("DataMigration done after {0:N0} min" -f ((Get-Date) - $t0).TotalMinutes)
            return
        }
        Write-Progress -Activity 'iOS' -Status ("DataMigration ({0:N0} min)" -f ((Get-Date) - $t0).TotalMinutes)
        Start-Sleep -Seconds 30
    }
    Fail "DataMigration was not done in $minutes minutes; run again to redo this step"
}
# sync the guest's disks, then quit QEMU (QMP); a QEMU that does not end is stopped
function Stop-Guest($g, [switch]$NoSync) {
    $synced = $true
    if (-not $NoSync) {
        $null = Guest 180 @('sync') -NoFail
        $synced = ($script:Code -eq 0)
    }
    Send-Qmp 'quit'
    if ($DryRun -or -not $g.Proc) { return $synced }
    if (-not $g.Proc.WaitForExit(120000)) { Stop-Process -Id $g.Pid -Force -ErrorAction SilentlyContinue }
    $synced
}
function Boot-Failed($g) { if (-not $DryRun -and (Guest-Alive $g)) { $null = Stop-Guest $g -NoSync } }

# --- Disk files the launcher builds on what this redoes ------------------------------------------
# root.qcow2 and the disks made on it rest on the layers a redone step changes: they go (the step
# that makes them comes later), and what iOS wrote on top of them (-Persist, .ipa installs) is kept
# as .old, as the launcher cannot boot it any more.
function Retire-Top([switch]$CollectionsOnly) {
    # (.host.txt: what the launcher gave iOS of the PC's time zone, region and clock on that disk)
    $derived = @('root-collections.qcow2', 'root-collections.tc', 'root-collections.host.txt')
    $user = @('root-collections-user.qcow2', 'root-collections-user.tc', 'root-collections-user.host.txt',
              'root-collections-apps.qcow2', 'root-collections-apps.tc', 'root-collections-apps.host.txt')
    if (-not $CollectionsOnly) {
        $derived = @('root.qcow2', 'root.tc', 'root.host.txt') + $derived
        $user = @('root26-user.qcow2', 'root-user.tc', 'root26-user.host.txt', 'root-apps.qcow2', 'root-apps.tc', 'root-apps.host.txt') + $user
    }
    foreach ($f in $derived) {
        if (Test-Path (In-Work $f)) { Show-Cmd "del $f"; if (-not $DryRun) { Remove-Item (In-Work $f); Drop-Owned $f } }
    }
    foreach ($f in $user) {
        if (Test-Path (In-Work $f)) {
            Say "$f rests on the old disk: kept as $f.old" Yellow
            if (-not $DryRun) { Move-Item (In-Work $f) (In-Work "$f.old") -Force }
        }
    }
}

# The decrypted OS image (4.1 and 5.3 read it). The cleanup removes it, so a step redone later
# gets it again: its .aea from Apple, decrypted, the .aea removed.
function Need-OsImage {
    if (-not $DryRun -and (Test-Path (In-Work "os\$OsImage"))) { return }
    if ($DryRun) { Say "(only if os\$OsImage is not there, as after the cleanup:)" DarkGray }
    else { Say "the decrypted $OsImage is not here (the cleanup removes it): getting it again" Yellow }
    if ($DryRun -or -not (Test-Path (In-Work "iphone\$OsImage.aea"))) {
        Need-Space 8.2
        Get-IpswMember (IPhone-Source) "$OsImage.aea" (In-Work "iphone\$OsImage.aea") $IPhoneFiles["$OsImage.aea"]
    }
    Need-Space 8.2
    if ($LinuxMode -ceq 'helper') { Decrypt-Aea (In-Work "iphone\$OsImage.aea") (In-Work 'os') }
    else { $null = Run-Wsl 'decrypt-os' 'bash $S/m2-decrypt.sh' }
    Drop-Aea $OsImage
}
function Drop-Aea([string]$image, [string]$dir = 'iphone') {
    if ($KeepBuildFiles) { return }
    Show-Cmd "del $dir\$image.aea   (decrypted; -KeepBuildFiles keeps it)"
    if (-not $DryRun) {
        Remove-Item (In-Work "$dir\$image.aea"), (In-Work "install\got\$image.aea.ok") -ErrorAction SilentlyContinue
    }
}
# The cloudOS OS image the GPU driver comes out of, and its trust cache. The gpu step removes the
# image once used, so a gpu step redone later gets it again.
function Need-GpuImage {
    $aea = In-Work "cloudos\$CloudOsGpuImage.aea"
    $need = if ($DryRun -or -not (Test-Path $aea)) { $CloudOsFiles["$CloudOsGpuImage.aea"] / 1e9 } else { 0 }
    Need-Space ($need + $Space.gpu)
    foreach ($m in "$CloudOsGpuImage.aea", "Firmware/$CloudOsGpuImage.aea.trustcache") {
        Get-IpswMember (CloudOs-Source) $m (In-Work ('cloudos\' + ($m -replace '/', '\'))) $CloudOsFiles[$m]
    }
}
# The overlay the wallpaper step builds root.qcow2 on: the top of the disk chain
function Top-Layer {
    if (Gpu-Route) { 'root26-gpu' } else { 'root26-apps' }
}
# CDHashes from cdhash.py output
function Hashes([string[]]$lines) { @($lines | ForEach-Object { if ("$_" -cmatch '^([0-9a-f]{40}) ') { $Matches[1] } }) }

# --- The steps ---------------------------------------------------------------------------------
function Do-Setup {
    $menu = Join-Path $here 'Start-iOS26-Menu.ps1'
    Show-Cmd "md $Work"
    Show-Cmd "powershell -File $(Q $menu) -SetupOnly -Config $(Q $Config) -Work $Work"
    Show-Cmd "config: Distro=$Distro Src=$Src Linux=$LinuxDir LinuxMode=$Linux"
    $dst = In-Work 'scripts'
    Show-Cmd "copy ios26\scripts, ios26\installer\wsl-setup.sh, scripts\wsl-build-hfsplus.sh -> $dst (.sh with LF)"
    if ($DryRun) { return }
    New-Item -ItemType Directory -Force $Work, (In-Work 'install\logs') | Out-Null
    # the menu owns the config: the work folder, and the GPU driver question (a folder picker)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $menu -SetupOnly -Config $Config -Work $Work
    if ($LASTEXITCODE) { Fail 'the setup did not finish' }
    Save-Keys @{ Distro = $Distro; Src = $Src; Linux = $LinuxDir; LinuxMode = $Linux }
    switch (Gpu-Route) {
        'cloudos' { Say "GPU driver: Apple's, out of the cloudOS IPSW ($CloudOsGpuImage.aea), with the compiler plugin $(if ($GpuPlugin) { Gpu-Plugin } else { 'of our release' })" }
        'folder' { Say "GPU driver: $(Gpu-Driver)" }
        default { Say 'GPU-less: iOS draws on the CPU (slower); the menu''s [G] adds a driver later' Yellow }
    }
    # the gpu step comes hours later: a plugin it cannot have stops the run now
    if ((Gpu-Route) -ceq 'cloudos' -and (Get-Mark 'gpu') -cne (Step-Sig 'gpu')) {
        $why = Plugin-Missing
        if ($why) { Fail $why }
    }
    # the build's scripts, next to its files where WSL reads them (bash wants LF)
    New-Item -ItemType Directory -Force $dst | Out-Null
    $files = @(Get-ChildItem (Join-Path $here 'scripts') -File) +
             @(Get-Item (Join-Path $here 'installer\wsl-setup.sh'), (Join-Path $repo 'scripts\wsl-build-hfsplus.sh'))
    foreach ($f in $files) {
        $to = Join-Path $dst $f.Name
        if ($f.Extension -ceq '.sh') {
            $t = [IO.File]::ReadAllText($f.FullName) -replace "`r`n", "`n"
            [IO.File]::WriteAllText($to, $t, (New-Object System.Text.UTF8Encoding $false))
        } else {
            Copy-Item $f.FullName $to -Force
        }
    }
}

function Do-Prereq([switch]$Report) {
    # $Report (-Check): say what is missing instead of failing
    if ($DryRun) {
        Say "would check: Windows 10 2004+ 64-bit, cores and RAM, Vulkan loader, curl/tar/robocopy, free space, WSL (the Linux steps: $LinuxMode)" DarkGray
        return
    }
    $bad = @()
    $os = [Environment]::OSVersion.Version
    Say ("Windows {0}, {1}" -f $os, $(if ([Environment]::Is64BitOperatingSystem) { '64-bit' } else { '32-bit' }))
    if (-not [Environment]::Is64BitOperatingSystem -or $os.Build -lt 19041) { $bad += 'Windows 10 2004 (build 19041) or later, 64-bit (WSL 2)' }
    $cores = [Environment]::ProcessorCount
    $ram = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $low = ($cores -lt 8 -or $ram -lt 16)
    Say "$cores logical processors, $ram GB RAM$(if ($low) { ': README.md asks for 8 or more cores and 16 GB (the guest gets 4 GB)' })" $(if ($low) { 'Yellow' } else { 'Gray' })
    $gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object Name) -join ', '
    $vk = Test-Path (Join-Path $env:SystemRoot 'System32\vulkan-1.dll')
    Say "GPU: $gpus; Vulkan loader: $(if ($vk) { 'yes' } else { 'no' })" $(if ($vk) { 'Gray' } else { 'Yellow' })
    if (-not $vk) { $bad += 'a Vulkan driver (vulkan-1.dll): your GPU vendor''s driver' }
    Say 'the GPU driver needs VK_EXT_external_memory_host (tested: NVIDIA RTX 4080 Laptop); not checked here' DarkGray
    foreach ($t in 'curl.exe', 'tar.exe', 'robocopy.exe') {
        if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { $bad += "$t (Windows 10 1803 and later have it)" }
    }
    $free = Free-GB
    $color = if ($free -lt 56) { 'Yellow' } else { 'Gray' }
    Say ("{0:N1} GB free on {1}: a build from nothing needs about 49 GB there at its peak and keeps about 25 GB" -f $free, [IO.Path]::GetPathRoot($Work)) $color
    $w = Get-Wsl
    if ($LinuxMode -ceq 'helper') {
        Say "the Linux steps: the helper VM (-Linux helper$(if (-not $w.Ok) { '; WSL is not installed' }))"
    } elseif (-not $w.Ok) {
        Say 'WSL: not installed (the linux step says how; -Linux helper needs none)' Yellow
    } elseif ($w.Distros.ContainsKey($Distro)) {
        Say "WSL: $Distro (WSL $($w.Distros[$Distro]))"
    } else {
        Say "WSL: no distro $Distro yet (the linux step makes it); have: $(@($w.Distros.Keys) -join ', ')" Yellow
    }
    if ($LinuxMode -ceq 'wsl') {
        Say ("C: has {0:N1} GB free (WSL's disk: the hfsplus module build takes about 5 GB)" -f (([IO.DriveInfo]::new('C:\')).AvailableFreeSpace / 1e9)) DarkGray
    }
    $msys = Test-Path 'C:\msys64\usr\bin\bash.exe'
    Say "MSYS2 (for -QemuFrom source): $(if ($msys) { 'C:\msys64' } else { 'not installed' })" DarkGray
    if ($bad) {
        if ($Report) { foreach ($b in $bad) { Say "missing: $b" Yellow } } else { Fail ('missing: ' + ($bad -join '; ')) }
    }
}

function Do-Linux {
    if ($LinuxMode -ceq 'helper') { Do-Helper } else { Do-Wsl }
}
# -Linux helper: ipsw.exe, the helper VM (installer\helper\out, from build-kernel.sh and
# build-rootfs.sh or the ASoftware release package), and its self-test
function Do-Helper {
    $zip = In-Work 'downloads\ipsw_3.1.739_windows_x86_64.zip'
    Get-File $Pin.Ipsw[0] $zip $Pin.Ipsw[1]
    $to = In-Work 'tools\ipsw'
    Show-Cmd "Expand-Archive $zip $to"
    if (-not $DryRun) { Expand-Archive $zip $to -Force }
    $null = Ipsw @('version')
    $from = Join-Path $repo 'installer\helper\out'
    $h = In-Work 'tools\helper'
    Show-Cmd "copy $from\Image.gz, initrd.gz -> $h"
    if (-not $DryRun) {
        foreach ($f in 'Image.gz', 'initrd.gz') {
            if (-not (Test-Path (Join-Path $from $f))) {
                Fail ("no helper VM in $from ($f): build it (installer\helper\build-kernel.sh and build-rootfs.sh, " +
                      'README.md "Without WSL"), copy it there from the ASoftware release package, or use -Linux wsl')
            }
        }
        New-Item -ItemType Directory -Force $h | Out-Null
        Copy-Item (Join-Path $from 'Image.gz'), (Join-Path $from 'initrd.gz') $h -Force
    }
    $qemu = In-Work 'qemu\qemu-system-aarch64.exe'
    if (-not $DryRun -and -not (Test-Path $qemu)) { Fail "no $qemu (the qemu step puts it there)" }
    # the tools the steps use, in the VM (installer\helper\job-selftest.sh)
    $lines = Run $qemu (Helper-Args 'selftest' @())
    if (-not $DryRun -and (Helper-Done $lines) -ne 0) { Fail 'the helper VM''s self-test failed (its output is above)' }
    # an older helper (the iOS 16 installer's before 2026-11-02) has no job-run.sh, sgdisk or awk
    if (-not $DryRun -and -not ($lines -cmatch '^\s*ASOFT: ok   test -x /asoft/job-run\.sh')) {
        Fail ("the helper VM in $from is too old for the iOS 26 steps (no job-run.sh): build it again " +
              '(README.md "Without WSL") or use -Linux wsl')
    }
}

function Do-Wsl {
    if ($DryRun) {
        Show-Cmd "wsl --install Ubuntu-24.04 --name $Distro --no-launch   (if there is no distro $Distro)"
    } else {
        $w = Get-Wsl
        if (-not $w.Ok) {
            Fail 'WSL is not installed: in an administrator PowerShell run "wsl --install --no-distribution", restart Windows, then run this again'
        }
        if (-not $w.Distros.ContainsKey($Distro)) {
            $null = Run 'wsl.exe' @('--install', 'Ubuntu-24.04', '--name', $Distro, '--no-launch')
            $w = Get-Wsl
            if (-not $w.Distros.ContainsKey($Distro)) {
                Fail "WSL did not make the distro $Distro`: run 'wsl --update', or make an Ubuntu 24.04 distro yourself and pass -Distro NAME"
            }
        }
        if ("$($w.Distros[$Distro])" -cne '2') { Fail "$Distro is a WSL $($w.Distros[$Distro]) distro; the build needs WSL 2: wsl --set-version $Distro 2" }
    }
    # apt packages, ipsw, apfs-fuse, python3, the hfsplus module (built for this WSL kernel)
    $null = Run-Wsl 'linux' 'bash $S/wsl-setup.sh install'
}

function Do-Python {
    $zip = In-Work 'downloads\python-3.12.10-embed-amd64.zip'
    Get-File $Pin.Python[0] $zip $Pin.Python[1]
    Show-Cmd "Expand-Archive $zip $(Split-Path $Py)"
    if (-not $DryRun) { Expand-Archive $zip (Split-Path $Py) -Force }
    $null = Run $Py @('--version')
}

function Do-Qemu {
    $dest = In-Work 'qemu'
    $exe = Join-Path $dest 'qemu-system-aarch64w.exe'
    $msys = Test-Path 'C:\msys64\usr\bin\bash.exe'
    $mode = $QemuFrom
    if ($mode -ceq 'auto') {
        if ($QemuRelease.Url) { $mode = 'release' }
        elseif (Test-Path $exe) { $mode = 'keep' }
        elseif ($msys) { $mode = 'source' }
        elseif ($DryRun) { $mode = 'source'; Say '(auto: no release package set, no QEMU here: shown as -QemuFrom source)' DarkGray }
        else {
            Fail ('no release package is set in Install-iOS26.ps1 ($QemuRelease). Run again with -QemuFrom source (builds it in ' +
                  'MSYS2, installed with winget if missing; a few hours) or -QemuFrom FOLDER (a build you have: win-build.sh''s dist)')
        }
    }
    Need-Space $Space.qemu
    if ($mode -ceq 'release') {
        if (-not $QemuRelease.Url) { Fail 'no release package is set in Install-iOS26.ps1 ($QemuRelease): use -QemuFrom source or FOLDER' }
        Say "release package $($QemuRelease.Version): $($QemuRelease.Url)" DarkGray
        $zip = In-Work "downloads\asoft-qemu-$($QemuRelease.Version).zip"
        try {
            Get-File $QemuRelease.Url $zip $QemuRelease.Sha256
        } catch {
            # auto on a PC that has MSYS2 builds QEMU instead; one without stops (run again to resume)
            if ($QemuFrom -cne 'auto' -or -not $msys) { throw }
            Say $_.Exception.Message Yellow
            Say 'auto: the release package could not be had; building QEMU from source instead (MSYS2 is installed)' Yellow
            $mode = 'source'
        }
    }
    if ($mode -ceq 'keep') {
        Say "keeping the QEMU in $dest (-QemuFrom release, source or FOLDER replaces it)"
    } elseif ($mode -ceq 'release') {
        # the same package unpacked here already (iOS 16's installer's, or a QEMU from it running) stays
        $seen = Join-Path $dest 'package.sha256'
        if (-not $DryRun -and (Test-Path $exe) -and (Test-Path $seen) -and (Get-Content $seen -Raw).Trim() -ceq $QemuRelease.Sha256) {
            Say "keeping the QEMU in $dest`: package $($QemuRelease.Version) is unpacked there"
        } else {
            Show-Cmd "Expand-Archive $zip $dest"
            if (-not $DryRun) {
                if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
                Expand-Archive $zip $dest
                Set-Content $seen $QemuRelease.Sha256 -Encoding ASCII
            }
        }
    } elseif ($mode -ceq 'source') {
        Build-Qemu
        Copy-Tree (Join-Path $Src 'dist') $dest
    } else {
        if (-not $DryRun -and -not (Test-Path (Join-Path $mode 'qemu-system-aarch64.exe'))) { Fail "$mode has no qemu-system-aarch64.exe (-QemuFrom FOLDER: win-build.sh's dist)" }
        Copy-Tree $mode $dest
    }
    if ($DryRun) { return }
    if (-not (Test-Path $exe) -and -not (Test-Path (Join-Path $dest 'qemu-system-aarch64.exe'))) { Fail "no qemu-system-aarch64w.exe in $dest" }
    $build = Join-Path $dest 'BUILD.txt'
    if (Test-Path $build) { foreach ($l in Get-Content $build) { Say $l } }
    Say 'the launcher needs qemu-sptm 7364c4e, reims-vgpu fd7bd0b5 and metal2vulkan 79e1dd02 or later, built together' DarkGray
    if (-not (Test-Path (Join-Path $dest 'qemu-img.exe'))) {
        Say "no qemu-img.exe in $dest`: quick boot (saved states) needs one there or in C:\Program Files\qemu" Yellow
    }
}
function Copy-Tree([string]$from, [string]$to) {
    Show-Cmd "robocopy $(Q $from) $(Q $to) /MIR /XD backup-*"
    if ($DryRun) { return }
    $ErrorActionPreference = 'Continue'
    robocopy $from $to /MIR /XD 'backup-*' /NFL /NDL /NJH /NJS /NP | Out-Null
    $rc = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($rc -ge 8) { Fail "robocopy $from -> $to failed ($rc)" }
}
# README.md step 1 in MSYS2 UCRT64: the three checkouts, nettle, reims-vgpu, QEMU -> <Src>\dist
function Build-Qemu {
    $msys = 'C:\msys64'
    $bash = "$msys\usr\bin\bash.exe"
    $fresh = $false
    if ($DryRun) {
        Show-Cmd 'winget install --id MSYS2.MSYS2 -e --source winget   (if there is no C:\msys64)'
    } elseif (-not (Test-Path $bash)) {
        if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
            Fail 'MSYS2 is not installed (C:\msys64) and there is no winget: install MSYS2 from https://www.msys2.org, then run this again'
        }
        $null = Run 'winget.exe' @('install', '--id', 'MSYS2.MSYS2', '-e', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements')
        if (-not (Test-Path $bash)) { Fail "winget installed MSYS2 somewhere else than $msys`: install it to C:\msys64" }
        $fresh = $true
    }
    $env:MSYSTEM = 'UCRT64'; $env:CHERE_INVOKING = '1'; $env:LANG = 'C'; $env:LC_ALL = 'C'
    $env:ASOFT26_SRC = To-Msys $Src
    if ($fresh -or $DryRun) {
        # a new MSYS2 updates itself first (twice: the first round can update only pacman's own)
        if ($DryRun) { Say '(only for an MSYS2 the installer has just installed:)' DarkGray }
        $null = Run $bash @('-lc', 'pacman -Syu --noconfirm') -NoFail
        $null = Run $bash @('-lc', 'pacman -Syu --noconfirm')
    }
    # --needed: only what is missing; an MSYS2 you have is not upgraded
    $null = Run $bash @('-lc', "pacman -S --needed --noconfirm $($MsysPackages -join ' ')")
    if (-not $DryRun) { New-Item -ItemType Directory -Force $Src | Out-Null }
    $body = @'
#!/bin/bash
# Install-iOS26.ps1: README.md step 1 in MSYS2 UCRT64 (written by the installer)
set -eu
R=$ASOFT26_SRC
H='{HERE}'
mkdir -p "$R/deps/dl"
clone() {	# URL BRANCH DIR OLDEST
	[ -d "$R/$3/.git" ] || git clone -b "$2" "$1" "$R/$3"
	echo "$3: $(git -C "$R/$3" rev-parse --short HEAD) on $(git -C "$R/$3" rev-parse --abbrev-ref HEAD)"
	git -C "$R/$3" merge-base --is-ancestor "$4" HEAD || { echo "$3 is older than $4, which the launcher needs: git -C $R/$3 pull"; exit 1; }
}
{CLONES}
f=$R/deps/dl/nettle-3.10.1.tar.gz
[ -f "$f" ] || { curl -fL --retry 5 -o "$f.part" {NETTLE_URL}; mv "$f.part" "$f"; }
echo "{NETTLE_SHA}  $f" | sha256sum -c -
[ -f "$R/deps/nettle/lib/libnettle.a" ] || bash "$H/win-nettle.sh"
bash "$H/reims-build.sh"
bash "$H/win-build.sh" {JOBS}
'@
    $clones = ($Sources | ForEach-Object { "clone $($_.Url) $($_.Branch) $($_.Dir) $($_.Min)" }) -join "`n"
    # win-build.sh takes the window's logo from the repo (assets\), so it runs from here
    $body = $body.Replace('{HERE}', (To-Msys (Join-Path $here 'scripts'))).Replace('{CLONES}', $clones).
        Replace('{NETTLE_URL}', $Pin.Nettle[0]).Replace('{NETTLE_SHA}', $Pin.Nettle[1].ToLowerInvariant()).
        Replace('{JOBS}', "$([Environment]::ProcessorCount)")
    $file = In-Work 'install\sh\qemu-source.sh'
    if ($DryRun) {
        Show-Cmd "C:\msys64\usr\bin\bash.exe -lc `"bash '$(To-Msys $file)'`"   (MSYSTEM=UCRT64 ASOFT26_SRC=$(To-Msys $Src)):"
        foreach ($l in @($body.Trim() -split "`n" | Select-Object -Skip 2)) { Write-Host ('      ' + $l.TrimEnd()) -ForegroundColor DarkGray }
        return
    }
    New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
    [IO.File]::WriteAllText($file, ($body -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding $false))
    $null = Run $bash @('-lc', "bash '$(To-Msys $file)'")
}

function Do-Sysroot {
    Get-File $Pin.Sysroot[0] (In-Work 'downloads\ios_sysroot.tar.gz') $Pin.Sysroot[1]
}

function Do-CloudOs {
    Need-Space $Space.cloudos
    foreach ($m in $CloudOsFiles.Keys) {
        # the OS image only for a GPU layer still to be made from it (the gpu step gets it again if
        # it is not here)
        if ($m -ceq "$CloudOsGpuImage.aea") {
            if ((Gpu-Route) -cne 'cloudos') { Say "$m`: not needed (the GPU driver is not taken from cloudOS)" DarkGray; continue }
            if ((Get-Mark 'gpu') -ceq (Step-Sig 'gpu')) { Say "$m`: its GPU driver is on the disk already"; continue }
        }
        Get-IpswMember (CloudOs-Source) $m (In-Work ('cloudos\' + ($m -replace '/', '\'))) $CloudOsFiles[$m]
    }
}

function Do-IPhone {
    $need = 0
    $todo = @()
    foreach ($m in $IPhoneFiles.Keys) {
        $leaf = ($m -split '/')[-1]
        # the encrypted images are not needed once decrypted (the SystemOS once on the disk)
        if ($m -ceq "$OsImage.aea" -and (Get-Mark 'decrypt') -and (Test-Path (In-Work "os\$OsImage"))) { Say "$m`: decrypted already"; continue }
        if ($m -ceq "$SysOsImage.aea" -and (Get-Mark 'rootfs')) { Say "$m`: on the disk already"; continue }
        $todo += $m
        if (-not (Test-Path (In-Work "iphone\$leaf"))) { $need += $IPhoneFiles[$m] / 1e9 }
    }
    Need-Space $need
    foreach ($m in $todo) {
        Get-IpswMember (IPhone-Source) $m (In-Work ('iphone\' + ($m -split '/')[-1])) $IPhoneFiles[$m]
    }
}

function Do-Decrypt {
    Need-Space $Space.decrypt
    $body = Step-Body 'decrypt'
    if ($LinuxMode -ceq 'helper') {
        # the same with ipsw.exe
        foreach ($i in $SysOsImage, $OsImage) {
            $aea = In-Work "iphone\$i.aea"
            if (-not $DryRun -and -not (Test-Path $aea) -and -not (Test-Path (In-Work "os\$i"))) { Fail "neither iphone\$i.aea nor os\$i`: run Install-iOS26.cmd -From iphone" }
            if ($DryRun -or (Test-Path $aea)) {
                if (-not $DryRun) { Remove-Item (In-Work "os\$i") -ErrorAction SilentlyContinue }
                Decrypt-Aea $aea (In-Work 'os')
            }
        }
    } else {
        $null = Run-Wsl 'decrypt' $body.Replace('{OS}', $OsImage).Replace('{SYSOS}', $SysOsImage)
    }
    # 8.2 GB: the OS is read decrypted from now on (the SystemOS .aea stays until the root is built)
    Drop-Aea $OsImage
}

function Do-Firmware {
    $body = Step-Body 'firmware'
    if ($LinuxMode -cne 'helper') { $null = Run-Wsl 'firmware' $body; return }
    # the same with ipsw.exe
    if (-not $DryRun) { New-Item -ItemType Directory -Force (In-Work 'cloud'), (In-Work 'fw') | Out-Null }
    $null = Ipsw @('img4', 'im4p', 'extract', (In-Work 'cloudos\Firmware\all_flash\DeviceTree.vphone600ap.im4p'), '-o', (In-Work 'cloud\vphone600ap.adt'))
    foreach ($k in 'research', 'release') {
        $null = Ipsw @('kernel', 'dec', (In-Work "cloudos\kernelcache.$k.vphone600"), '-o', (In-Work 'cloud'))
        $kexts = Ipsw @('kernel', 'kexts', (In-Work "cloud\kernelcache.$k.vphone600.decompressed")) -Quiet
        if (-not $DryRun) { Set-Content (In-Work "cloud\kexts.$k.txt") $kexts; Say "kexts.$k.txt: $(@($kexts).Count) lines" }
    }
    $null = Ipsw @('img4', 'im4p', 'extract', (In-Work 'cloudos\Firmware\sptm.vresearch1.release.im4p'), '-o', (In-Work 'fw\sptm'))
    $null = Ipsw @('img4', 'im4p', 'extract', (In-Work 'cloudos\Firmware\txm.iphoneos.research.im4p'), '-o', (In-Work 'fw\txm'))
    Show-Cmd 'copy cloud\kernelcache.research.vphone600.decompressed fw\bootkc; copy cloud\vphone600ap.adt fw\dtree.orig'
    if (-not $DryRun) {
        Copy-Item (In-Work 'cloud\kernelcache.research.vphone600.decompressed') (In-Work 'fw\bootkc') -Force
        Copy-Item (In-Work 'cloud\vphone600ap.adt') (In-Work 'fw\dtree.orig') -Force
    }
}

function Do-DeviceTree {
    # vresearch_dt_fixup.py, pinned (qemu-sptm asoft 52f3606: it fills the product's syscfg keys)
    $qs = In-Work 'tools\qemu-sptm'
    Get-File $Pin.DtFixup[0] (Join-Path $qs 'scripts\darwin\vresearch_dt_fixup.py') $Pin.DtFixup[1]
    Show-Cmd "QEMU_SPTM=$qs"
    $env:QEMU_SPTM = $qs
    foreach ($n in 4, 8) {
        $null = Py 'dt-root26smp.py' @((In-Work 'fw\dtree.orig'), (In-Work "dtree-smp$n"), '--cpus', "$n")
    }
    Aod-DeviceTrees
}

function Do-Ramdisk {
    $body = Step-Body 'ramdisk'
    $rd = 'install\work\rd.apfs'
    if ($LinuxMode -ceq 'helper') {
        if (-not $DryRun) { New-Item -ItemType Directory -Force (In-Work 'install\work') | Out-Null }
        $null = Ipsw @('img4', 'im4p', 'extract', (In-Work 'cloudos\094-39914-031.dmg'), '-o', (In-Work $rd))
    }
    $null = Run-Linux 'ramdisk' $body -Disks @(@{ ro = ($rd -replace '\\', '/'); at = '/root/ios26/rd/rd.apfs' }) `
        -In @('downloads/ios_sysroot.tar.gz', 'cloudos/Firmware/094-39914-031.dmg.trustcache') -Out @('rd-shell.hfs', 'cloud/rd.trustcache.im4p')
    if ($LinuxMode -ceq 'helper' -and -not $DryRun) { Remove-Item (In-Work $rd) -ErrorAction SilentlyContinue }
}

function Do-Rootfs {
    Need-OsImage
    if (-not $DryRun -and -not (Test-Path (In-Work "os\$SysOsImage")) -and -not (Test-Path (In-Work "iphone\$SysOsImage.aea"))) {
        Get-IpswMember (IPhone-Source) "$SysOsImage.aea" (In-Work "iphone\$SysOsImage.aea") $IPhoneFiles["$SysOsImage.aea"]
    }
    if (-not $DryRun -and -not (Test-Path (In-Work "iphone\$AppOsImage"))) {
        Get-IpswMember (IPhone-Source) $AppOsImage (In-Work "iphone\$AppOsImage") $IPhoneFiles[$AppOsImage]
    }
    Need-Space $Space.rootfs
    $body = Step-Body 'rootfs'
    $sysos = In-Work "os\$SysOsImage"
    if ($LinuxMode -ceq 'helper' -and ($DryRun -or -not (Test-Path $sysos))) { Decrypt-Aea (In-Work "iphone\$SysOsImage.aea") (In-Work 'os') }
    $null = Run-Linux 'rootfs' $body.Replace('{SYSOS}', $SysOsImage) `
        -Disks @(@{ ro = "os/$OsImage" }, @{ ro = "os/$SysOsImage" }, @{ ro = "iphone/$AppOsImage" }, @{ new = 'root26.qcow2'; size = '32G' }) `
        -In @('downloads/ios_sysroot.tar.gz') -Out @('root26.qcow2.hashes')
    # the SystemOS is on the disk now (mk-root26.sh removed its decrypted image; in the helper VM
    # only the link to it)
    if ($LinuxMode -ceq 'helper') { Show-Cmd "del os\$SysOsImage"; if (-not $DryRun) { Remove-Item $sysos -ErrorAction SilentlyContinue } }
    Drop-Aea $SysOsImage
}

function Do-TrustCache {
    $tcs = @("$OsImage.aea.trustcache", "$SysOsImage.aea.trustcache", "$AppOsImage.trustcache") | ForEach-Object { In-Work "iphone\$_" }
    $null = Py 'mktc.py' (@('-2', (In-Work 'root26.tc')) + $tcs + @(In-Work 'root26.qcow2.hashes'))
}

function Do-Partition {
    Need-Space $Space.partition
    $body = Step-Body 'partition'
    # the helper VM's new disk: as big as mk-root26g.sh makes it (the root, 16 GiB of Data, 2 MiB)
    $size = '(root26.qcow2 + 16 GiB + 2 MiB)'
    if ($LinuxMode -ceq 'helper' -and -not $DryRun) {
        $info = (Run (In-Work 'qemu\qemu-img.exe') @('info', '--output=json', (In-Work 'root26.qcow2')) -Quiet) -join "`n" | ConvertFrom-Json
        $size = "$([long]$info.'virtual-size' + 16GB + 2MB)"
    }
    $null = Run-Linux 'partition' $body -Disks @(@{ ro = 'root26.qcow2' }, @{ new = 'root26g.qcow2'; size = $size })
    if (-not $KeepBuildFiles -and -not $DryRun -and -not (Is-Owned 'root26.qcow2')) {
        Say 'root26.qcow2 stays: this installer did not make it' DarkGray
    } elseif (-not $KeepBuildFiles) {
        Show-Cmd 'del root26.qcow2   (partitioned now; -KeepBuildFiles keeps it)'
        if (-not $DryRun) { Remove-Item (In-Work 'root26.qcow2'); Drop-Owned 'root26.qcow2' }
    }
}

function Do-Tweaks {
    $body = Step-Body 'tweaks'
    $null = Run-Linux 'tweaks' $body
}

function Do-FirstBoot {
    # 4.5: boot once, so usermanagerd writes the persona manifest and the user session (persona.kb,
    # usersession.kb) the persona step completes. HFS+ lets it write them only when they are new.
    # -NoAod: this disk has no libMobileGestalt patch yet (the apps step's)
    $g = Start-Guest 'install-firstboot' @('-Disk', 'root26g.qcow2', '-Tc', 'root26.tc', '-NoAod')
    try {
        $test = 'test -e /private/var/keybags/persona.kb && test -e /private/var/keybags/usersession.kb && echo __READY__ || echo __WAIT__'
        Say 'waiting for /private/var/keybags/persona.kb and usersession.kb in the guest (up to 30 min)'
        if ($DryRun) {
            $null = Guest 90 @($test)
        } else {
            $t0 = Get-Date
            while ($true) {
                if (-not (Guest-Alive $g)) { Fail "QEMU ended during the first boot; see $($g.Dir)" }
                $out = Guest 90 @($test) -NoFail
                # a line of its own: the command (printed as "$ cmd" above it) has the word too
                if (@($out | Where-Object { "$_".Trim() -ceq '__READY__' }).Count) { break }
                if (((Get-Date) - $t0).TotalMinutes -gt 30) { Fail "no persona.kb after 30 min; see $($g.Dir)\serial.log" }
                Start-Sleep -Seconds 30
            }
            Say ("there after {0:N0} min" -f ((Get-Date) - $t0).TotalMinutes)
            Start-Sleep -Seconds 30
        }
        if (-not (Stop-Guest $g)) { Fail 'the guest did not answer sync; run again to redo the first boot' }
    } catch { Boot-Failed $g; throw }
}

function Do-Persona {
    # root26-prefs.py again: its activation record needs mobileactivationd's container, which the
    # first boot made (it is idempotent)
    $body = Step-Body 'persona'
    $null = Run-Linux 'persona' $body
}

function Do-Activation {
    # 5.1: mobileactivationd answers should_hactivate YES; its new CDHash keeps the original's
    # constraint category (tc-like.py)
    $orig = In-Work 'install\work\mobileactivationd.orig'
    $new = In-Work 'install\work\mobileactivationd'
    $body = Step-Body 'activation-get'
    $null = Run-Linux 'activation-get' $body -Out @('install/work/mobileactivationd.orig')
    $null = Py 'hact_patch.py' @($orig, $new)
    $out = Py 'reattest.py' @($orig, $new)
    $h = if ($DryRun) { @('OLD_CDHASH', 'NEW_CDHASH') } else {
        $l = $out | Where-Object { "$_" -cmatch '^[0-9a-f]{40} [0-9a-f]{40} ' } | Select-Object -First 1
        if (-not $l) { Fail 'reattest.py printed no CDHashes' }
        @("$l".Split(' ')[0], "$l".Split(' ')[1])
    }
    $null = Py 'tc-like.py' @((In-Work 'root26-activation.tc'), (In-Work 'root26.tc'), $h[0], $h[1])
    $body = Step-Body 'activation-put'
    $null = Run-Linux 'activation-put' $body -In @('install/work/mobileactivationd')
}

function Do-Apps {
    # 5.3.1-5.3.5 and 5.4: the staged system apps, PosterBoard's purgeable-file patch and the side
    # button's (.42), UIKitCore's touch edge patch (.03) and libMobileGestalt's Always On Display
    # patch (.15, with Auto-Lock Never: root26-aod.py), the apps into /Applications, no scene watchdogs
    Need-OsImage
    Need-Space $Space.apps
    $body = Step-Body 'apps-get'
    $dsc = ($DscFiles | ForEach-Object { '$C/' + $_ }) -join ' '
    # (apply-staged.sh and apply-apps.sh read the staged apps off the OS image)
    $osDisk = @{ ro = "os/$OsImage" }
    $null = Run-Linux 'apps-get' $body.Replace('{DSC}', $dsc) -Disks @($osDisk) -Out @('dsc')
    $null = Py 'dsc-patch.py' (@((In-Work 'dsc')) + $DscPosterBoard + @(In-Work 'dscpatch-pb'))
    # the side button's patch on top of PosterBoard's (both in the .42): only this .42 goes on the disk
    $pb = Py 'dsc-patch.py' (@((In-Work 'dscpatch-pb')) + $DscLockLongPress + @(In-Work 'dscpatch-lp'))
    $edge = Py 'edge-patch.py' @((In-Work 'dsc'), (In-Work 'dscpatch-edge'))
    $aod = Py 'dsc-patch.py' (@((In-Work 'dsc')) + $DscAod + @(In-Work 'dscpatch-aod'))
    $hashes = if ($DryRun) { @('NEW_42', 'NEW_03', 'NEW_15') } else {
        $a = @($pb | Where-Object { "$_" -cmatch '^dyld_shared_cache_arm64e\.\d+ [0-9a-f]{40} [0-9a-f]{40}$' } | ForEach-Object { "$_".Split(' ')[2] })
        $b = @($edge | Where-Object { "$_" -cmatch '^dyld_shared_cache_arm64e\.\d+ [0-9a-f]{40} ' } | ForEach-Object { "$_".Split(' ')[1] })
        $c = @($aod | Where-Object { "$_" -cmatch '^dyld_shared_cache_arm64e\.\d+ [0-9a-f]{40} [0-9a-f]{40}$' } | ForEach-Object { "$_".Split(' ')[2] })
        if ($a.Count -ne 1 -or $b.Count -ne 1 -or $c.Count -ne 1) { Fail 'dsc-patch.py / edge-patch.py printed no new CDHash' }
        @($a[0], $b[0], $c[0])
    }
    $list = In-Work 'install\work\apps.hashes'
    Show-Cmd "dscpatch = dscpatch-lp\$($DscFiles[0]) + dscpatch-edge\$($DscFiles[1]) + dscpatch-aod\$($DscFiles[2]); $list = $($hashes -join ' ')"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force (In-Work 'dscpatch'), (In-Work 'install\work') | Out-Null
        Copy-Item (In-Work "dscpatch-lp\$($DscFiles[0])"), (In-Work "dscpatch-edge\$($DscFiles[1])"), (In-Work "dscpatch-aod\$($DscFiles[2])") (In-Work 'dscpatch')
        Set-Content $list $hashes -Encoding ASCII
    }
    $null = Py 'mktc.py' @('-2', (In-Work 'root26-apps.tc'), (In-Work 'root26-activation.tc'), $list)
    $body = Step-Body 'apps-put'
    $null = Run-Linux 'apps-put' $body -Disks @($osDisk) -In @('dsc', 'dscpatch')
    # the device trees with /arm-io/disp0, for the disks from this one up (Start-iOS26.ps1 takes
    # dtree-smpN-aod when it is there)
    Aod-DeviceTrees -Make
}

# dtree-smpN-aod: dtree-smpN with Always On Display's /arm-io/disp0 (dt-aod.py). Only a disk with the
# apps step's libMobileGestalt patch may boot with it (backboardd asserts without), so the apps step
# makes them (-Make) and the device tree step, which writes dtree-smpN again, renews the ones there.
function Aod-DeviceTrees([switch]$Make) {
    $env:QEMU_SPTM = In-Work 'tools\qemu-sptm'
    foreach ($n in 4, 8) {
        $aodTree = In-Work "dtree-smp$n-aod"
        if ($Make -or (Test-Path $aodTree)) { $null = Py 'dt-aod.py' @((In-Work "dtree-smp$n"), $aodTree) }
    }
}

# fw\bootkc: the kernelcache as the firmware step left it, with OpenGL ES's personality keys
# (kc-gles.py) when the compiler plugin is the release's. GL shaders crash another plugin's guest
# compiler or fault an older QEMU's GPU, so a driver folder or -GpuPlugin FILE gets the plain one.
function Set-BootKc([bool]$gles) {
    $plain = In-Work 'cloud\kernelcache.research.vphone600.decompressed'
    $kc = In-Work 'fw\bootkc'
    if ($gles) {
        $null = Py 'kc-gles.py' @($plain, $kc)
    } else {
        Show-Cmd 'copy cloud\kernelcache.research.vphone600.decompressed fw\bootkc'
        if (-not $DryRun) { Copy-Item $plain $kc -Force }
    }
}

function Do-Gpu {
    # 5.2: the guest GPU driver into /System/Library/Extensions (root:wheel, 755/644), its Mach-Os'
    # CDHashes into the trust cache. GpuMode cloudos: Apple's bundle out of the cloudOS OS image
    # (cloudos-gpu-driver.sh: its binary's CDHash must be in that image's trust cache) and the
    # compiler plugin; gpu: the folder you chose, as it is. Without one (GPU-less) no GPU layer.
    $route = Gpu-Route
    Set-BootKc ($route -ceq 'cloudos' -and -not $GpuPlugin)
    if (-not $route) {
        Say 'GPU-less (no guest GPU driver in the config): no GPU layer' Yellow
        foreach ($f in 'root26-gpu.qcow2', 'root26-gpu.tc') { if (Test-Path (In-Work $f)) { Show-Cmd "del $f"; if (-not $DryRun) { Remove-Item (In-Work $f); Drop-Owned $f } } }
        return
    }
    $copy = In-Work "install\work\gpu\$GpuBundle"
    if ($route -ceq 'cloudos') {
        $driver = "cloudos\$CloudOsGpuImage.aea"
        $plugin = Gpu-Plugin
        $why = Plugin-Missing
        if ($why) {
            if ($DryRun) { Say "(a real run stops here) $why" Yellow } else { Fail $why }
        } elseif (-not $GpuPlugin) {
            Get-File $GpuPluginRelease.Url $plugin $GpuPluginRelease.Sha256
        }
        Need-GpuImage
        Show-Cmd "del install\work\gpu (if there)"
        if (-not $DryRun) { Remove-Item (In-Work 'install\work\gpu') -Recurse -Force -ErrorAction SilentlyContinue }
        $body = 'bash $S/cloudos-gpu-driver.sh cloudos/{IMG}.aea install/work/gpu cloudos/Firmware/{IMG}.aea.trustcache'
        if ($LinuxMode -ceq 'helper') {
            # decrypted by ipsw.exe; the helper VM reads the bundle off it (apfs-fuse)
            Decrypt-Aea (In-Work "cloudos\$CloudOsGpuImage.aea") (In-Work 'install\work\gpu-img')
            $body = $body.Replace('{IMG}.aea ', '{IMG} ')
        }
        $null = Run-Linux 'gpu-driver' $body.Replace('{IMG}', $CloudOsGpuImage) `
            -Disks @(@{ ro = "install/work/gpu-img/$CloudOsGpuImage"; at = "cloudos/$CloudOsGpuImage" }) `
            -In @("cloudos/Firmware/$CloudOsGpuImage.aea.trustcache") -Out @('install/work/gpu')
        if ($LinuxMode -ceq 'helper' -and -not $DryRun) { Remove-Item (In-Work 'install\work\gpu-img') -Recurse -Force -ErrorAction SilentlyContinue }
        Show-Cmd "copy $plugin $copy"
        if (-not $DryRun) { Copy-Item $plugin (Join-Path $copy $GpuPluginRelease.Name) -Force }
    } else {
        $driver = Gpu-Driver
        if (-not $DryRun -and -not (Test-Path $driver -PathType Container)) {
            Fail "the GPU driver folder $driver is not there: choose it again with the menu's [G] (Start-iOS26.cmd)"
        }
        Need-Space $Space.gpu
        Copy-Tree $driver $copy
    }
    $files = if ($DryRun) { @("$copy\...") } else { @(Get-ChildItem $copy -Recurse -File | ForEach-Object FullName) }
    $hashes = Hashes (Py 'cdhash.py' $files)
    if (-not $DryRun -and -not $hashes) { Fail "no signed Mach-O in $driver (is it $GpuBundle?)" }
    if (-not $DryRun -and $route -ceq 'cloudos' -and $hashes.Count -lt 2) { Fail "the compiler plugin $plugin is not a signed Mach-O" }
    $list = In-Work 'install\work\gpu.hashes'
    Show-Cmd "$list = the CDHashes above"
    if (-not $DryRun) { New-Item -ItemType Directory -Force (Split-Path $list) | Out-Null; Set-Content $list $hashes -Encoding ASCII }
    $null = Py 'mktc.py' @('-2', (In-Work 'root26-gpu.tc'), (In-Work 'root26-apps.tc'), $list)
    $body = Step-Body 'gpu'
    $null = Run-Linux 'gpu' $body.Replace('{BUNDLE}', $GpuBundle) -In @('install/work/gpu')
    # kept for the other guests (Install-watchOS.ps1 retargets its own copy): a few MB, which the
    # cleanup leaves, where the 755 MB image it came out of would otherwise be downloaded again
    # (copied under another name and renamed: an interrupted copy never looks like the driver)
    $shared = In-Work "gpu-driver\$GpuBundle"
    Show-Cmd "copy $copy -> $shared"
    if (-not $DryRun) {
        $new = In-Work 'gpu-driver\.new'
        Remove-Item $new -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force $new | Out-Null
        Copy-Item $copy (Join-Path $new $GpuBundle) -Recurse -Force
        Remove-Item $shared -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item (Join-Path $new $GpuBundle) $shared
        Remove-Item $new -Force
    }
    # the driver is out of it (a gpu step redone later gets the image again)
    if ($route -ceq 'cloudos') { Drop-Aea $CloudOsGpuImage 'cloudos' }
}

function Do-Wallpaper {
    # 5.3.6: root.qcow2 on the top layer, booted once with -Keep: DataMigration (since
    # root26-staged.py) and then PosterBoard's first run write into it (a throwaway start would redo
    # them every time).
    $top = Top-Layer
    Need-Space $Space.wallpaper
    Retire-Top
    $null = Run-Linux 'wallpaper' "disk_tools`noverlay $top.qcow2 root.qcow2"
    Show-Cmd "copy $top.tc root.tc"
    if (-not $DryRun) { Copy-Item (In-Work "$top.tc") (In-Work 'root.tc') -Force }
    $g = Start-Guest 'install-wallpaper' @('-Disk', 'root.qcow2', '-Tc', 'root.tc')
    try {
        Wait-Ui $g 40
        Wait-PcTime $g
        Wait-Migration $g 90
        Wait-Running $g ($BakeMinutes * 60) 'PosterBoard writes its poster store'
        if (-not (Stop-Guest $g)) { Fail 'the guest did not answer sync; run again to redo the wallpaper' }
    } catch { Boot-Failed $g; throw }
}

function Do-Collections {
    if (-not (Want-Collections)) {
        # one built before stays (one on an older root.qcow2 went with it, Retire-Top)
        $had = if (Test-Path (In-Work 'root-collections.qcow2')) { '; the one there stays' } else { '' }
        Say "not asked for (-Collections, or the menu's wallpaper collections, builds it)$had" DarkGray
        return
    }
    # 5.3.6, optional: iOS 17's Collections wallpaper, unconditional in PosterBoard (a second patch
    # on the .42 the disk has now), in an overlay on root.qcow2 with its own trust cache
    Need-Space $Space.collections
    Retire-Top -CollectionsOnly
    $body = Step-Body 'collections-get'
    $null = Run-Linux 'collections-get' $body.Replace('{N}', $DscFiles[0]) -Out @('dsc-wp')
    $out = Py 'dsc-patch.py' (@((In-Work 'dsc-wp')) + $DscCollections + @(In-Work 'dscpatch-wp'))
    $h = if ($DryRun) { 'NEW_42' } else {
        $l = @($out | Where-Object { "$_" -cmatch '^dyld_shared_cache_arm64e\.\d+ [0-9a-f]{40} [0-9a-f]{40}$' })
        if ($l.Count -ne 1) { Fail 'dsc-patch.py printed no new CDHash' }
        "$($l[0])".Split(' ')[2]
    }
    $list = In-Work 'install\work\collections.hashes'
    Show-Cmd "$list = $h"
    if (-not $DryRun) { New-Item -ItemType Directory -Force (Split-Path $list) | Out-Null; Set-Content $list $h -Encoding ASCII }
    $null = Py 'mktc.py' @('-2', (In-Work 'root-collections.tc'), (In-Work 'root.tc'), $list)
    $body = Step-Body 'collections-put'
    $null = Run-Linux 'collections-put' $body -In @('dsc-wp', 'dscpatch-wp')
    $g = Start-Guest 'install-collections' @('-Wallpaper', 'collections', '-Disk', 'root-collections.qcow2', '-Tc', 'root-collections.tc')
    try {
        Wait-Ui $g 40
        Wait-Running $g ($BakeMinutes * 60) 'PosterBoard sets the Collections wallpaper up'
        Wait-PcTime $g
        if (-not (Stop-Guest $g)) { Fail 'the guest did not answer sync; run again to redo this step' }
    } catch { Boot-Failed $g; throw }
}

function Do-Cleanup {
    if ($KeepBuildFiles) { Say '-KeepBuildFiles: the decrypted images and the build''s intermediates stay' DarkGray; return }
    # what only the build reads (a step redone later gets it again)
    $gone = @('os', 'dsc', 'dsc-wp', 'dscpatch', 'dscpatch-pb', 'dscpatch-edge', 'dscpatch-wp', 'install\work', 'install\helper', 'root26.qcow2',
              "iphone\$OsImage.aea", "iphone\$SysOsImage.aea", "install\got\$OsImage.aea.ok", "install\got\$SysOsImage.aea.ok",
              "cloudos\$CloudOsGpuImage.aea", "install\got\$CloudOsGpuImage.aea.ok")
    $bytes = 0
    $any = $false
    foreach ($rel in $gone) {
        $p = In-Work $rel
        if (-not (Test-Path $p)) {
            if ($DryRun) { Show-Cmd "del $rel   (if there)" }
            continue
        }
        if ($rel -ceq 'root26.qcow2' -and -not $DryRun -and -not (Is-Owned $rel)) { Say "$rel stays: this installer did not make it" DarkGray; continue }
        $any = $true
        $bytes += (@(Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue) | Measure-Object Length -Sum).Sum
        Show-Cmd "del $rel"
        if (-not $DryRun) { Remove-Item $p -Recurse -Force; Drop-Owned $rel }
    }
    if (-not $any -and -not $DryRun) { Say 'nothing to remove' DarkGray; return }
    if (-not $DryRun) { Say ("freed {0:N1} GB" -f ($bytes / 1e9)) }
    # (the helper VM's scratch went with it)
    if ($LinuxMode -cne 'helper') { $null = Run-Wsl 'cleanup' 'rm -rf "${L:?}/rd/rd.apfs" /tmp/sysroot-signed' }
}

# The files the launcher needs, the step that makes each and the README.md step it follows
$Needs = @(
    @('fw\bootkc', 'firmware', '3.2'), @('fw\sptm', 'firmware', '3.2'), @('fw\txm', 'firmware', '3.2'),
    @('dtree-smp4', 'devicetree', '3.3'), @('dtree-smp8', 'devicetree', '3.3'), @('rd-shell.hfs', 'ramdisk', '3.5'),
    @('root.qcow2', 'wallpaper', '4-5'), @('root.tc', 'wallpaper', '4-5'),
    @('qemu\qemu-system-aarch64w.exe', 'qemu', '1')
)
function Show-Checklist {
    $missing = 0
    foreach ($n in $Needs) {
        $ok = Test-Path (In-Work $n[0])
        if (-not $ok -and $n[0] -clike 'qemu\*w.exe') { $ok = Test-Path (In-Work 'qemu\qemu-system-aarch64.exe') }
        if (-not $ok) { $missing++ }
        Say ("{0} {1,-30} step {2,-11} README.md step {3}" -f $(if ($ok) { '[ok]  ' } else { '[need]' }), $n[0], $n[1], $n[2]) $(if ($ok) { 'Green' } else { 'Yellow' })
    }
    foreach ($o in @(@('qemu\qemu-img.exe', 'quick boot''s saved states'), @('root-collections.qcow2', 'the Collections wallpaper (-Collections)'))) {
        $ok = Test-Path (In-Work $o[0])
        Say ("{0} {1,-30} optional: {2}" -f $(if ($ok) { '[ok]  ' } else { '[--]  ' }), $o[0], $o[1]) $(if ($ok) { 'Green' } else { 'DarkGray' })
    }
    $missing
}

function Do-Shortcut {
    $missing = Show-Checklist
    if ($missing) { Say "not ready: $missing file(s) missing (the steps above make them)" Yellow }
    if ($NoShortcut) { return }
    $cmd = Join-Path $here 'Start-iOS26.cmd'
    $lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\ASoftware iOS 26.lnk'
    Show-Cmd "shortcut $lnk -> $cmd"
    if ($DryRun) { return }
    try {
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
        $s.TargetPath = $cmd
        $s.WorkingDirectory = $here
        $s.Description = 'iOS 26 in a window (research preview)'
        $s.Save()
    } catch {
        Say "could not make the shortcut ($($_.Exception.Message))" Yellow
    }
}

# Id, README.md Build step, what, kind: always (every run), chain (a disk step: redoing it redoes
# the disk steps after it), or once
$Steps = @(
    @{ Id = 'setup';       Readme = 'Start menu and setup'; Kind = 'always'; Title = 'Setup: work folder, GPU driver, config, scripts' }
    @{ Id = 'prereq';      Readme = 'You need';             Kind = 'always'; Title = 'Windows prerequisites' }
    @{ Id = 'python';      Readme = '-';                    Kind = 'once';   Title = 'Python for the Windows-side tools' }
    @{ Id = 'qemu';        Readme = '1';                    Kind = 'once';   Title = 'QEMU and the GPU library' }
    @{ Id = 'linux';       Readme = 'You need';             Kind = 'once';   Title = 'The Linux steps'' tools: WSL 2 (ipsw, apfs-fuse, hfsplus, python3) or the helper VM and ipsw.exe' }
    @{ Id = 'sysroot';     Readme = 'You need';             Kind = 'once';   Title = "darwin-vm's iOS sysroot" }
    @{ Id = 'cloudos';     Readme = '2';                    Kind = 'once';   Title = 'cloudOS 26.4b files (Apple)' }
    @{ Id = 'iphone';      Readme = '2';                    Kind = 'once';   Title = 'iPhone17,3 iOS 26.6.2 files (Apple, about 10 GB)' }
    @{ Id = 'decrypt';     Readme = '2';                    Kind = 'once';   Title = 'Decrypt the OS and SystemOS images' }
    @{ Id = 'firmware';    Readme = '3.1, 3.2';             Kind = 'once';   Title = 'Firmware: device tree, kernelcache, SPTM, TXM' }
    @{ Id = 'devicetree';  Readme = '3.3';                  Kind = 'once';   Title = 'The device trees for 4 and 8 vCPUs' }
    @{ Id = 'ramdisk';     Readme = '3.4, 3.5';             Kind = 'once';   Title = 'Sysroot check and the shell ramdisk' }
    @{ Id = 'rootfs';      Readme = '4.1';                  Kind = 'chain';  Title = 'The root file system (root26.qcow2)' }
    @{ Id = 'trustcache';  Readme = '4.2';                  Kind = 'chain';  Title = 'Its trust cache (root26.tc)' }
    @{ Id = 'partition';   Readme = '4.3';                  Kind = 'chain';  Title = 'The partitioned disk (root26g.qcow2)' }
    @{ Id = 'tweaks';      Readme = '4.4';                  Kind = 'chain';  Title = 'Prefs, keybag, launchd trims' }
    @{ Id = 'firstboot';   Readme = '4.5';                  Kind = 'chain';  Title = 'First boot (iOS writes its persona files)' }
    @{ Id = 'persona';     Readme = '4.5';                  Kind = 'chain';  Title = 'Persona and MobileGestalt fixes' }
    @{ Id = 'activation';  Readme = '5.1';                  Kind = 'chain';  Title = 'Activation (root26-activation.qcow2)' }
    @{ Id = 'apps';        Readme = '5.3.1-5.3.5, 5.4';     Kind = 'chain';  Title = 'Apps, dyld cache patches, gestures (root26-apps.qcow2)' }
    @{ Id = 'gpu';         Readme = '5.2';                  Kind = 'chain';  Title = 'The guest GPU driver (root26-gpu.qcow2), unless GPU-less' }
    @{ Id = 'wallpaper';   Readme = '5.3.6';                Kind = 'chain';  Title = 'root.qcow2 and its wallpaper (boots iOS once)' }
    @{ Id = 'collections'; Readme = '5.3.6';                Kind = 'chain';  Title = 'The Collections wallpaper disk, if asked for' }
    @{ Id = 'cleanup';     Readme = '-';                    Kind = 'always'; Title = 'Remove what only the build needs' }
    @{ Id = 'shortcut';    Readme = 'Start menu and setup'; Kind = 'always'; Title = 'Checklist and Start menu shortcut' }
)
# The files a step builds on, and the step that makes each: checked before the step (or the run
# loop, for a disk step) changes anything
$Boot = @(@('fw\bootkc', 'firmware'), @('fw\sptm', 'firmware'), @('fw\txm', 'firmware'), @('dtree-smp4', 'devicetree'),
          @('rd-shell.hfs', 'ramdisk'), @('qemu\qemu-system-aarch64w.exe', 'qemu'))
$Inputs = @{
    trustcache  = @(, @('root26.qcow2.hashes', 'rootfs'))
    partition   = @(, @('root26.qcow2', 'rootfs'))
    tweaks      = @(, @('root26g.qcow2', 'partition'))
    firstboot   = @(@('root26g.qcow2', 'partition'), @('root26.tc', 'trustcache')) + $Boot
    persona     = @(, @('root26g.qcow2', 'partition'))
    activation  = @(@('root26g.qcow2', 'partition'), @('root26.tc', 'trustcache'))
    apps        = @(@('root26-activation.qcow2', 'activation'), @('root26-activation.tc', 'activation'))
}
function Assert-Inputs([string]$id) {
    $need = @($Inputs[$id] | Where-Object { $_ })
    if ($id -ceq 'gpu' -and (Gpu-Route)) { $need = @(@('root26-apps.qcow2', 'apps'), @('root26-apps.tc', 'apps')) }
    if ($id -ceq 'wallpaper') {
        $t = Top-Layer
        $by = if ($t -ceq 'root26-gpu') { 'gpu' } else { 'apps' }
        $need = @(@("$t.qcow2", $by), @("$t.tc", $by)) + $Boot
    }
    if ($id -ceq 'collections' -and (Want-Collections)) { $need = @(@('root.qcow2', 'wallpaper'), @('root.tc', 'wallpaper')) + $Boot }
    foreach ($n in $need) {
        $ok = Test-Path (In-Work $n[0])
        if (-not $ok -and $n[0] -clike 'qemu\*w.exe') { $ok = Test-Path (In-Work 'qemu\qemu-system-aarch64.exe') }
        if (-not $ok) {
            $why = if ($n[0] -ceq 'root26.qcow2') { ', and the partition step removes it once done' } else { '' }
            Fail "$($n[0]) is missing in $Work (step $($n[1]) makes it$why): run Install-iOS26.cmd -From $($n[1])"
        }
    }
}
# what a step's marker must say for it to count as done (others: done)
function Step-Sig([string]$id) {
    switch -CaseSensitive ($id) {
        # cloudos: a new image or plugin redoes the GPU layer
        'gpu' {
            $r = Gpu-Route
            if ($r -ceq 'cloudos') { return "cloudos $CloudOsGpuImage plugin $(Plugin-Sig)" }
            if ($r) { return "gpu $(Gpu-Driver)" } else { return 'gpuless' }
        }
        'collections' { if (Want-Collections) { return 'on' } else { return 'off' } }
        # aod: the apps step with Always On Display and Auto-Lock Never (an install before it redoes
        # apps and the layers on it)
        'apps' { return 'aod lock-longpress' }
        # the other -Linux has its own tools
        'linux' { return $LinuxMode }
    }
    'done'
}
function Invoke-Step([string]$id) {
    switch -CaseSensitive ($id) {
        'setup' { Do-Setup }
        'prereq' { Do-Prereq }
        'linux' { Do-Linux }
        'python' { Do-Python }
        'qemu' { Do-Qemu }
        'sysroot' { Do-Sysroot }
        'cloudos' { Do-CloudOs }
        'iphone' { Do-IPhone }
        'decrypt' { Do-Decrypt }
        'firmware' { Do-Firmware }
        'devicetree' { Do-DeviceTree }
        'ramdisk' { Do-Ramdisk }
        'rootfs' { Do-Rootfs }
        'trustcache' { Do-TrustCache }
        'partition' { Do-Partition }
        'tweaks' { Do-Tweaks }
        'firstboot' { Do-FirstBoot }
        'persona' { Do-Persona }
        'activation' { Do-Activation }
        'apps' { Do-Apps }
        'gpu' { Do-Gpu }
        'wallpaper' { Do-Wallpaper }
        'collections' { Do-Collections }
        'cleanup' { Do-Cleanup }
        'shortcut' { Do-Shortcut }
    }
}

# --- Folders -----------------------------------------------------------------------------------
$Cfg = Read-Config
if (-not $Work) { $Work = $env:ASOFT26_WORK }
if (-not $Work -and $Cfg -and $Cfg.Work) { $Work = [string]$Cfg.Work }
if (-not $Work) {
    $best = [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } |
        Sort-Object AvailableFreeSpace -Descending | Select-Object -First 1
    $Work = Join-Path $best.Name 'ios26'
}
$Work = [IO.Path]::GetFullPath($Work).TrimEnd('\')
# WSL reaches it as /mnt/<drive>/..., in scripts that do not quote every path
if ($Work -cnotmatch '^[A-Za-z]:\\[^\s''"`$;&|<>()]+$') {
    throw "the work folder must be a drive-letter path without spaces or shell characters (WSL scripts use it): $Work"
}
if (-not $Src) {
    if ($env:ASOFT26_SRC -and $env:ASOFT26_SRC -cmatch '^/([a-zA-Z])/(.*)$') { $Src = $Matches[1].ToUpperInvariant() + ':\' + ($Matches[2] -replace '/', '\') }
    elseif ($env:ASOFT26_SRC) { $Src = $env:ASOFT26_SRC }
    elseif ($Cfg -and $Cfg.Src) { $Src = [string]$Cfg.Src }
    else { $Src = Join-Path ([IO.Path]::GetPathRoot($Work)) 'asoft26-src' }
}
$Src = [IO.Path]::GetFullPath($Src).TrimEnd('\')
if (-not $LinuxDir) {
    if ($env:ASOFT26_LINUX) { $LinuxDir = $env:ASOFT26_LINUX }
    elseif ($Cfg -and $Cfg.Linux) { $LinuxDir = [string]$Cfg.Linux }
    else { $LinuxDir = '/root/ios26' }
}
if ($LinuxDir -cnotmatch '^/[A-Za-z0-9._/-]+$') { throw "-LinuxDir must be an absolute Linux path of plain characters: $LinuxDir" }
if (-not $Distro) { if ($Cfg -and $Cfg.Distro) { $Distro = [string]$Cfg.Distro } else { $Distro = 'ios-emu' } }
# where the Linux steps run: -Linux, else the config's (LinuxMode), else auto: WSL if it is
# installed (faster), else the helper VM
if (-not $Linux) { $Linux = if ($Cfg -and "$($Cfg.LinuxMode)" -cin 'auto', 'wsl', 'helper') { [string]$Cfg.LinuxMode } else { 'auto' } }
$LinuxMode = $Linux
if ($LinuxMode -ceq 'auto') { $LinuxMode = if ((Get-Wsl).Ok) { 'wsl' } else { 'helper' } }
$Scripts = In-Work 'scripts'
$Py = In-Work 'tools\python\python.exe'

$ids = @($Steps | ForEach-Object { $_.Id })
$From = $From.ToLowerInvariant(); $Only = $Only.ToLowerInvariant()
# (the linux step was called wsl)
if ($From -ceq 'wsl') { $From = 'linux' }
if ($Only -ceq 'wsl') { $Only = 'linux' }
foreach ($x in @($From, $Only)) { if ($x -and $ids -cnotcontains $x) { throw "no step '$x'; the steps: $($ids -join ', ')" } }
if ($From -and $Only) { throw 'give -From or -Only, not both' }

# --- -List, -Check -----------------------------------------------------------------------------
if ($List) {
    Write-Host "Work folder: $Work"
    $i = 0
    foreach ($s in $Steps) {
        $i++
        $m = Get-Mark $s.Id
        $state = if ($s.Kind -ceq 'always') { 'every run' } elseif ($m -and $m -ceq (Step-Sig $s.Id)) { 'done' } elseif ($m) { 'redo' } else { '-' }
        Write-Host ("  {0,2} {1,-12} {2,-9} README.md {3,-22} {4}" -f $i, $s.Id, $state, $s.Readme, $s.Title)
    }
    $foreign = Foreign-Disks
    if ($foreign) { Write-Host (Foreign-Message $foreign) -ForegroundColor Yellow }
    exit 0
}
if ($Check) {
    Step "Check (reads only): work folder $Work"
    Do-Prereq -Report
    if ($LinuxMode -ceq 'helper') {
        Step "The Linux steps: the helper VM (-Linux $Linux)"
        foreach ($f in 'tools\helper\Image.gz', 'tools\helper\initrd.gz', 'tools\ipsw\ipsw.exe') {
            $ok = Test-Path (In-Work $f)
            Say ("{0} {1}" -f $(if ($ok) { '[ok]  ' } else { '[need]' }), $f) $(if ($ok) { 'Green' } else { 'Yellow' })
        }
        $from = Join-Path $repo 'installer\helper\out\initrd.gz'
        Say "the linux step copies the helper VM from $(Split-Path $from)$(if (-not (Test-Path $from)) { ': not there (build it, README.md "Without WSL")' })" DarkGray
    } else {
        Step "WSL tools in $Distro (-Linux $Linux)"
        $w = Get-Wsl
        if ($w.Ok -and $w.Distros.ContainsKey($Distro)) {
            $env:WSL_UTF8 = '1'
            $null = Run 'wsl.exe' @('-d', $Distro, '-u', 'root', '--', 'bash', (To-Wsl (Join-Path $here 'installer\wsl-setup.sh')), 'check') -NoFail
        } else { Say "no WSL distro $Distro" Yellow }
    }
    Step 'QEMU'
    $build = In-Work 'qemu\BUILD.txt'
    if (Test-Path $build) { foreach ($l in Get-Content $build) { Say $l } } else { Say "no $build" Yellow }
    Step 'Outputs the launcher needs'
    $null = Show-Checklist
    Step 'Steps done (markers in install\)'
    foreach ($s in $Steps) {
        if ($s.Kind -ceq 'always') { continue }
        $m = Get-Mark $s.Id
        Say ("{0,-12} {1}" -f $s.Id, $(if ($m) { $m } else { '-' })) $(if ($m) { 'Gray' } else { 'DarkGray' })
    }
    $foreign = Foreign-Disks
    if ($foreign) { Say (Foreign-Message $foreign) Yellow }
    elseif (Test-Path (In-Work 'install')) { Say "disks this installer made (install\owned.txt): $(@(Get-Owned) -join ', ')" DarkGray }
    exit 0
}

# --- Run ---------------------------------------------------------------------------------------
# -Collections is remembered (a later run that redoes the disk builds the Collections one again)
if ($Collections -and $NoCollections) { throw 'give -Collections or -NoCollections, not both' }
Write-Host "ASoftware iOS 26 installer$(if ($DryRun) { ' (dry run: nothing is run)' })" -ForegroundColor Cyan
if ($LinuxMode -ceq 'helper') {
    Write-Host "  Work $Work, the Linux steps in the helper VM (-Linux $Linux), sources $Src"
} else {
    Write-Host "  Work $Work (WSL: $(To-Wsl $Work)), WSL distro $Distro, Linux scratch $LinuxDir (-Linux $Linux), sources $Src"
}
$fromIdx = if ($From) { [array]::IndexOf($ids, $From) } else { -1 }
$wallIdx = [array]::IndexOf($ids, 'wallpaper')
# disks it did not make: a real run stops before any step (-DryRun says so and goes on)
$stop = $null
$foreign = Foreign-Disks
if ($foreign) {
    $stop = Foreign-Message $foreign
} else {
    $bad = @(Find-NotOwned)
    if ($bad) {
        $stop = "these disks in $Work were not made by this installer, and the steps this run runs would delete, rebuild or " +
            "change them: $($bad -join ', '). Move them away, or name the step that makes one with -From or -Only to let the installer take it over."
    }
}
if ($stop -and -not $DryRun) { Write-Host ''; Write-Host $stop -ForegroundColor Red; exit 1 }
if ($stop) { Write-Host "  (a real run stops here) $stop" -ForegroundColor Yellow }
if (($Collections -or $NoCollections) -and -not $DryRun) { Save-Keys @{ Collections = [bool]$Collections } }
$chainRedone = $false
$topRetired = $false
for ($i = 0; $i -lt $Steps.Count; $i++) {
    $s = $Steps[$i]
    $forced = ($From -and $i -ge $fromIdx) -or ($Only -ceq $s.Id)
    $label = "{0}/{1} {2}: {3} (README.md, Build: {4})" -f ($i + 1), $Steps.Count, $s.Id, $s.Title, $s.Readme
    if ($s.Kind -cne 'always' -and -not $forced) {
        if ($Only -or ($From -and $i -lt $fromIdx)) { continue }
        if ((Get-Mark $s.Id) -ceq (Step-Sig $s.Id) -and -not ($s.Kind -ceq 'chain' -and $chainRedone)) {
            Write-Host "== $label  [done]" -ForegroundColor DarkGray
            continue
        }
    }
    # -Only STEP: the setup and the checks still run, the other every-run steps do not
    if ($Only -and $s.Kind -ceq 'always' -and $Only -cne $s.Id -and $s.Id -cne 'setup' -and $s.Id -cne 'prereq') { continue }
    Step $label
    $script:Log = $null
    if (-not $DryRun -and (Test-Path $Work)) {
        New-Item -ItemType Directory -Force (In-Work 'install\logs') | Out-Null
        $script:Log = In-Work "install\logs\$($s.Id).log"
        Add-Content $script:Log ("`n=== {0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $label)
    }
    try {
        if (-not $DryRun) { Assert-Inputs $s.Id }
        if ($s.Kind -ceq 'chain') {
            $chainRedone = $true
            # what was built on this step is redone after it
            for ($j = $i + 1; $j -lt $Steps.Count; $j++) {
                if ($Steps[$j].Kind -ceq 'chain' -and -not $DryRun) { Clear-Mark $Steps[$j].Id }
            }
            if (-not $topRetired -and $i -lt $wallIdx) { Retire-Top; $topRetired = $true }
        }
        # the disk files it makes are the installer's from now on (before it runs: a resume after a
        # failure half way finds them listed)
        $makes = $Writes[$s.Id] -and -not ($s.Id -ceq 'collections' -and -not (Want-Collections)) -and -not ($s.Id -ceq 'gpu' -and -not (Gpu-Route))
        if (-not $DryRun -and $makes) { Add-Owned $Writes[$s.Id] }
        Invoke-Step $s.Id
    } catch {
        Write-Host ''
        Write-Host "Step $($s.Id) failed (README.md, Build: $($s.Readme)): $($_.Exception.Message)" -ForegroundColor Red
        if ($script:Log) { Write-Host "  log: $script:Log" }
        Write-Host "  Fix the cause and run Install-iOS26.cmd again: it goes on from this step (-Only $($s.Id) redoes just this one)." -ForegroundColor Yellow
        exit 1
    }
    if ($s.Kind -cne 'always' -and -not $DryRun) { Set-Mark $s.Id (Step-Sig $s.Id) }
}
Write-Host ''
if ($DryRun) {
    Write-Host 'Dry run: nothing was run.' -ForegroundColor Cyan
} elseif ($Only) {
    Write-Host "Done: $Only. Run Install-iOS26.cmd again to go on with what is not done (-List shows it)." -ForegroundColor Cyan
} else {
    Write-Host 'Done. Start iOS 26 with Start-iOS26.cmd (the menu) or the Start menu shortcut.' -ForegroundColor Cyan
}

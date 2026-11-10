# Install an .ipa into the iOS 26 disk, the way the system apps are installed. The live installd
# path (asoftinstalld -> LSApplicationWorkspace) needs an APFS Data volume, and this disk is HFS+,
# so installd refuses with -4. This instead does what apply-apps.sh does for the system apps: it
# places the .ipa's .app into /Applications in an overlay on the base disk, adds every Mach-O's
# CDHash to a trust cache (so AMFI lets them run), and rebuilds LaunchServices so SpringBoard shows
# the app. The guest must be shut down (it edits the disk offline, in WSL or in the helper VM).
#
#   Install-Ipa.ps1 -Ipa app.ipa [-Work D:\ios26] [-Wallpaper ios26|collections]
#                   [-Disk base.qcow2] [-Tc base.tc] [-AppsDisk out.qcow2] [-AppsTc out.tc]
#                   [-Linux wsl|helper] [-WslDistro name]
#
# -Linux, -WslDistro: as the installer's, whose config has them. The config's LinuxMode gives way
# to the other one when it cannot run here and the other can; -Linux does not. Left to itself, WSL
# if it has the distro, else the helper VM in <Work>\tools\helper.
#
# It writes an "apps" overlay (<base>-apps.qcow2) and trust cache (<base-tc>-apps.tc) next to the
# base, accumulating every .ipa installed, and prints the pair to boot with:
#   Start-iOS26.ps1 -Disk <apps.qcow2> -Tc <apps.tc> -Keep
# Start-iOS26.ps1 -InstallIpa app.ipa does this and then boots that pair.
param(
    [Parameter(Mandatory)][string]$Ipa,
    [string]$Work = $env:ASOFT26_WORK,
    [ValidateSet('ios26', 'collections')][string]$Wallpaper = 'ios26',
    [string]$Disk = '',
    [string]$Tc = '',
    [string]$AppsDisk = '',
    [string]$AppsTc = '',
    [ValidateSet('', 'wsl', 'helper')][string]$Linux = '',
    [string]$WslDistro = ''
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
function Fail($m) { Write-Error $m; exit 1 }
function To-Wsl([string]$p) { '/mnt/' + $p.Substring(0, 1).ToLower() + ($p.Substring(2) -replace '\\', '/') }

if (-not (Test-Path $Ipa)) { Fail "no such .ipa: $Ipa" }
$Ipa = (Resolve-Path $Ipa).Path

# the base disk and trust cache (as Start-iOS26.ps1 resolves them)
if ($Work) { $Work = (Resolve-Path $Work).Path }
function In-Work([string]$p) { if (-not $p) { $p } elseif ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $Work $p } }
$pair = @{ ios26 = @('root.qcow2', 'root.tc'); collections = @('root-collections.qcow2', 'root-collections.tc') }[$Wallpaper]
if (-not $Disk) { $Disk = In-Work $pair[0] }
if (-not $Tc) { $Tc = In-Work $pair[1] }
foreach ($f in @($Disk, $Tc)) { if (-not (Test-Path $f)) { Fail "missing $f (give -Disk/-Tc, or -Work)" } }
$Disk = (Resolve-Path $Disk).Path; $Tc = (Resolve-Path $Tc).Path
if (-not $AppsDisk) { $AppsDisk = [IO.Path]::ChangeExtension($Disk, $null).TrimEnd('.') + '-apps.qcow2' }
if (-not $AppsTc) { $AppsTc = [IO.Path]::ChangeExtension($Tc, $null).TrimEnd('.') + '-apps.tc' }

# the guest must not be running on the overlay we write
$running = Get-CimInstance Win32_Process -Filter "Name like 'qemu-system%'" |
    Where-Object { $_.CommandLine -and ($_.CommandLine.Contains([IO.Path]::GetFileName($AppsDisk)) -or $_.CommandLine.Contains([IO.Path]::GetFileName($Disk))) } |
    Select-Object -First 1
if ($running) { Fail "iOS is running (QEMU $($running.ProcessId)); shut it down first" }

# python and the tools next to this script (published) or the dev scripts: the installer's Python
# first (on PATH python.exe may be the Store's stub)
$python = "$Work\tools\python\python.exe"
if (-not $Work -or -not (Test-Path $python)) { $python = (Get-Command python.exe -ErrorAction SilentlyContinue).Source }
if (-not $python) { $python = (Get-Command py -ErrorAction SilentlyContinue).Source }
if (-not $python) { Fail 'need Python (the installer''s tools\python, or python.exe on PATH)' }
function Py { param([string]$script) & $python '-I' $script @args }
$scriptsDir = if (Test-Path (Join-Path $here 'scripts\cdhash.py')) { Join-Path $here 'scripts' } else { $here }
$cdhashPy = Join-Path $scriptsDir 'cdhash.py'
$mktcPy = Join-Path $scriptsDir 'mktc.py'
$doSh = Join-Path $scriptsDir 'root26-do.sh'
foreach ($t in @($cdhashPy, $mktcPy, $doSh)) { if (-not (Test-Path $t)) { Fail "missing tool $t" } }
$qemuImg = @("$here\qemu\qemu-img.exe", "$Work\qemu\qemu-img.exe", 'C:\Program Files\qemu\qemu-img.exe') |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $qemuImg) { Fail 'no qemu-img.exe (looked next to the launcher and in Program Files)' }

# where the offline edit runs: -Linux as given; else the config's LinuxMode, or the other one when
# that one cannot run here and the other can (a config from another PC or install); else WSL if it
# has the distro, else the helper VM
$cfgFile = Join-Path $env:LOCALAPPDATA 'ASoftware iOS 26\ios26.config.json'
$cfg = if (Test-Path $cfgFile) { Get-Content $cfgFile -Raw | ConvertFrom-Json } else { $null }
$distroFrom = if ($WslDistro) { '-WslDistro' } elseif ($cfg -and $cfg.Distro) { "Distro in $cfgFile" } else { 'the default' }
if (-not $WslDistro) { $WslDistro = if ($cfg -and $cfg.Distro) { [string]$cfg.Distro } else { 'ios-emu' } }
$helperDir = "$Work\tools\helper"
# Why WSL or the helper VM cannot run here ('' when it can)
function Wsl-Lacks {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return 'there is no WSL (wsl.exe)' }
    $env:WSL_UTF8 = '1'
    $ErrorActionPreference = 'Continue'
    $distros = @(& wsl.exe -l -q 2>&1 | ForEach-Object { ("$_" -replace "`0", '').Trim() })
    $listed = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = 'Stop'
    if ($listed -and $distros -ccontains $WslDistro) { return '' }
    "WSL has no distro $WslDistro ($distroFrom)$(if (-not $listed) { " (wsl -l -q: $(@($distros | Where-Object { $_ }) -join ' '))" })"
}
function Helper-Lacks {
    if (-not $Work) { return 'the helper VM needs -Work (its tools\helper and qemu)' }
    $miss = @(@("$helperDir\Image.gz", "$helperDir\initrd.gz", "$Work\qemu\qemu-system-aarch64.exe") | Where-Object { -not (Test-Path $_) })
    if (-not $miss) { return '' }
    "the helper VM's $($miss -join ', ') $(if ($miss.Count -gt 1) { 'are' } else { 'is' }) missing" +
        $(if (@($miss | Where-Object { $_.StartsWith($helperDir) })) { " (the installer's linux step puts the helper VM in $helperDir)" })
}
function Lacks([string]$mode) { if ($mode -ceq 'wsl') { Wsl-Lacks } else { Helper-Lacks } }
$modeName = @{ wsl = 'WSL'; helper = 'the helper VM' }
if ($Linux) {
    # as given, even when it cannot run here
    $Linux = $Linux.ToLowerInvariant()
    $why = Lacks $Linux
    if ($why) { Fail "-Linux $Linux, but $why" }
} elseif ($cfg -and "$($cfg.LinuxMode)" -cin 'wsl', 'helper') {
    $Linux = [string]$cfg.LinuxMode
    $why = Lacks $Linux
    if ($why) {
        $other = if ($Linux -ceq 'wsl') { 'helper' } else { 'wsl' }
        $whyOther = Lacks $other
        if ($whyOther) { Fail "LinuxMode $Linux in $cfgFile, but $why; and $whyOther, so $($modeName[$other]) cannot stand in either" }
        Write-Host "LinuxMode $Linux in $cfgFile, but $why; using $($modeName[$other]) instead$(if ($other -ceq 'wsl') { " (distro $WslDistro)" } else { " (in $helperDir)" })"
        $Linux = $other
    }
} else {
    # auto: WSL if it has the distro, else the helper VM
    $whyWsl = Wsl-Lacks
    $Linux = 'wsl'
    if ($whyWsl) {
        $why = Helper-Lacks
        $from = if (-not $cfg) { "no $cfgFile" } elseif ($cfg.LinuxMode) { "LinuxMode $($cfg.LinuxMode) in $cfgFile" } else { "no LinuxMode in $cfgFile" }
        if ($why) { Fail "no -Linux and $from, so WSL or else the helper VM: $whyWsl, and $why" }
        $Linux = 'helper'
    }
}

# The helper VM's job (installer\helper\job-run.sh) on the disk and the app: scripts in a tar, QEMU
# opens the disk with its backing chain, the app goes in as a second tar (it may not fit in /work)
function Run-HelperJob([string]$jobDir, [string]$appTar, [string]$disk) {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    New-Item -ItemType Directory -Force "$jobDir\.job" | Out-Null
    Copy-Item $doSh "$jobDir\root26-do.sh"
    [IO.File]::WriteAllText("$jobDir\run.sh", "set -eu`nbash root26-do.sh /work/disk 'bash /work/place.sh'`n", $utf8)
    [IO.File]::WriteAllText("$jobDir\.job\run", "run.sh`n", $utf8)
    [IO.File]::WriteAllText("$jobDir\.job\disks", "d0 disk`nd1 app.tar`n", $utf8)
    $inTar = Join-Path $tmp 'in.tar'
    & tar.exe -cf $inTar -C $jobDir .
    if ($LASTEXITCODE) { Fail 'tar could not pack the helper VM''s job' }
    $d = @()
    foreach ($x in @(@($inTar, 'in', 'raw', ',readonly=on'), @($disk, 'd0', 'qcow2', ''), @($appTar, 'd1', 'raw', ',readonly=on'))) {
        # (a comma in a -drive file name is doubled)
        $d += '-drive', "file=$($x[0] -replace ',', ',,'),format=$($x[2]),if=none,id=$($x[1])$($x[3])", '-device', "virtio-blk-device,drive=$($x[1]),serial=$($x[1])"
    }
    # cortex-a76, not max: pointer authentication, which max has, is slow under TCG
    $a = @('-M', 'virt', '-cpu', 'cortex-a76', '-smp', "$([Math]::Min(8, [Environment]::ProcessorCount))", '-m', '4G',
           '-kernel', "$helperDir\Image.gz", '-initrd', "$helperDir\initrd.gz",
           '-append', 'console=ttyAMA0 loglevel=4 asoft.job=run',
           '-display', 'none', '-monitor', 'none', '-serial', 'stdio', '-no-reboot', '-nic', 'none') + $d
    $rc = $null
    # Windows PowerShell 5.1 turns a native tool's stderr into errors: here they are just lines
    $ErrorActionPreference = 'Continue'
    & "$Work\qemu\qemu-system-aarch64.exe" @a 2>&1 | ForEach-Object {
        $l = "$(if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ })".TrimEnd()
        if ($l -cmatch '^ASOFT: done (-?\d+)') { $rc = [int]$Matches[1] }
        Write-Host "  $l"
    }
    $ErrorActionPreference = 'Stop'
    $rc
}

# work area (extract + generated scripts), under the base disk's folder
$tmp = Join-Path ([IO.Path]::GetDirectoryName($AppsDisk)) ('.ipa-' + [IO.Path]::GetFileNameWithoutExtension($Ipa))
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    Write-Host "Extracting $([IO.Path]::GetFileName($Ipa))..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $ex = Join-Path $tmp 'extract'
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Ipa, $ex)
    $app = Get-ChildItem (Join-Path $ex 'Payload') -Directory -Filter *.app -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $app) { Fail 'no Payload\*.app in the .ipa' }
    Write-Host "App: $($app.Name)"

    # CDHash of every Mach-O in the .app (main binary, frameworks, plug-ins): cdhash.py prints
    # "<40hex> <type> <path>" for a signed Mach-O and nothing for other files.
    $hashes = [System.Collections.Generic.List[string]]::new()
    foreach ($f in Get-ChildItem $app.FullName -Recurse -File) {
        $out = (Py $cdhashPy $f.FullName) 2>$null
        foreach ($line in $out) {
            if ("$line" -match '^([0-9a-fA-F]{40})\b') { $hashes.Add($Matches[1].ToLower()) }
        }
    }
    $hashes = $hashes | Select-Object -Unique
    if (-not $hashes) { Fail 'no signed Mach-O found in the app (is it code-signed?)' }
    Write-Host "CDHashes: $($hashes.Count)"
    $hashFile = Join-Path $tmp 'cdhashes.txt'
    # a non-zero-hex char first so mktc.py reads it as a hash list, not a trust cache
    Set-Content -Encoding ASCII $hashFile (($hashes | Sort-Object { $_ -notmatch '^[3-9a-f]' }) -join "`n")

    # apps trust cache = base tc (first time) or the existing apps tc, plus the new hashes
    $tcBase = if (Test-Path $AppsTc) { $AppsTc } else { $Tc }
    Write-Host "Trust cache -> $([IO.Path]::GetFileName($AppsTc))"
    Py $mktcPy '-2' $AppsTc $tcBase $hashFile
    if ($LASTEXITCODE) { Fail 'mktc.py failed' }

    # apps overlay on the base disk (create once)
    if (-not (Test-Path $AppsDisk)) {
        $backing = if (([IO.Path]::GetDirectoryName($AppsDisk)) -eq ([IO.Path]::GetDirectoryName($Disk))) { [IO.Path]::GetFileName($Disk) } else { $Disk }
        & $qemuImg create -q -f qcow2 -b $backing -F qcow2 $AppsDisk
        if ($LASTEXITCODE) { Fail "qemu-img could not create $AppsDisk" }
        Write-Host "New apps overlay $([IO.Path]::GetFileName($AppsDisk)) (on $([IO.Path]::GetFileName($Disk)))"
    }

    # place the .app into /Applications and rebuild LaunchServices, offline. WSL copies it from the
    # Windows folder, with every file 0777; the helper VM unpacks it, with those modes too (a tar
    # from Windows has no x bits).
    $jobDir = Join-Path $tmp 'job'
    New-Item -ItemType Directory -Force $jobDir | Out-Null
    $inner = Join-Path $jobDir 'place.sh'
    $copy = if ($Linux -ceq 'wsl') { "cp -a `"$(To-Wsl $app.FullName)`" `"`$DST`" 2>/dev/null || true" }
            else { "tar -xf /work/app.tar -C `"`$R/Applications`" && chmod -R 777 `"`$DST`" || true" }
    @"
set -eu
DST="`$R/Applications/$($app.Name)"
rm -rf "`$DST"
$copy
[ -e "`$DST" ] || { echo "COPY FAILED"; exit 1; }
chown -R 0:0 "`$DST"
chown 0:80 "`$DST"
chmod 775 "`$DST"
echo "placed `$DST"
find "`$R/private/var/mobile/Containers/Data/InternalDaemon" -maxdepth 4 -name 'com.apple.LaunchServices-*.csstore' 2>/dev/null | while read f; do mv "`$f" "`$f.stale"; echo "stale: `${f#`$R}"; done
echo done
"@ | Set-Content -Encoding ASCII -NoNewline $inner
    # LF line endings for bash
    (Get-Content $inner -Raw) -replace "`r`n", "`n" | Set-Content -Encoding ASCII -NoNewline $inner

    if ($Linux -ceq 'wsl') {
        Write-Host "Placing into /Applications (WSL $WslDistro)..."
        # as the installer's prelude: the hfsplus module it built (gone from the kernel after a WSL
        # restart), and a free nbd device
        $run = Join-Path $jobDir 'run.sh'
        @"
set -eu
KVER=`$(uname -r)
export HFSPLUS_KO=/root/work/wsl-kernel/linux-msft-wsl-`${KVER%%-*}/fs/hfsplus/hfsplus.ko
modprobe nbd max_part=0 2> /dev/null || true
for n in 12 13 14 15; do
	if [ -b /dev/nbd`$n ] && [ ! -s /sys/block/nbd`$n/pid ]; then export NBD=/dev/nbd`$n; break; fi
done
bash "$(To-Wsl $doSh)" "$(To-Wsl $AppsDisk)" "bash $(To-Wsl $inner)"
"@ | Set-Content -Encoding ASCII -NoNewline $run
        (Get-Content $run -Raw) -replace "`r`n", "`n" | Set-Content -Encoding ASCII -NoNewline $run
        & wsl -d $WslDistro -u root -- bash (To-Wsl $run)
        if ($LASTEXITCODE) { Fail 'the offline disk edit failed' }
    } else {
        Write-Host 'Placing into /Applications (the helper VM)...'
        $appTar = Join-Path $tmp 'app.tar'
        & tar.exe -cf $appTar -C (Split-Path $app.FullName) $app.Name
        if ($LASTEXITCODE) { Fail 'tar could not pack the app' }
        $rc = Run-HelperJob $jobDir $appTar $AppsDisk
        if ($rc -ne 0) { Fail "the offline disk edit failed in the helper VM (exit $(if ($null -eq $rc) { 'unknown' } else { $rc }))" }
    }

    Write-Host ''
    Write-Host "Installed $($app.Name). Boot it with:" -ForegroundColor Green
    Write-Host "  Start-iOS26.ps1 -Disk `"$AppsDisk`" -Tc `"$AppsTc`" -Keep" -ForegroundColor Green
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

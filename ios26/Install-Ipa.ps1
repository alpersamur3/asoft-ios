# Install an .ipa into the iOS 26 disk, the way the system apps are installed. The live installd
# path (asoftinstalld -> LSApplicationWorkspace) needs an APFS Data volume, and this disk is HFS+,
# so installd refuses with -4. This instead does what apply-apps.sh does for the system apps: it
# places the .ipa's .app into /Applications in an overlay on the base disk, adds every Mach-O's
# CDHash to a trust cache (so AMFI lets them run), and rebuilds LaunchServices so SpringBoard shows
# the app. The guest must be shut down (it edits the disk offline, in WSL or in the helper VM).
#
#   Install-Ipa.ps1 -Ipa app.ipa [-Work D:\ios26] [-Wallpaper ios26|collections]
#                   [-Disk base.qcow2] [-Tc base.tc] [-AppsDisk out.qcow2] [-AppsTc out.tc]
#                   [-Linux wsl|helper] [-WslDistro name] [-NoExceptionPortEntitlement]
#
# -Linux, -WslDistro: as the installer's, whose config has them. The config's LinuxMode gives way
# to the other one when it cannot run here and the other can; -Linux does not. Left to itself, WSL
# if it has the distro, else the helper VM in <Work>\tools\helper.
#
# Every main executable of the app (its own, app extensions, XPC services) also gets the entitlement
# com.apple.private.set-exception-port: the iOS 26 kernel kills a task that sets exception ports without it (EXC_GUARD,
# what Sentry's crash reporter does, six seconds after the launch). -NoExceptionPortEntitlement leaves it out (a test).
#
# Signatures and placing are the Android app's own code, copied beside the other scripts (adhoc.py,
# ipa-hashes.py, ipa-place.py: see their first lines): every 64-bit slice of every Mach-O is signed again ad hoc
# with one SHA-256 code directory, whatever signature it came with, and the install fails unless each slice
# ends with exactly one CDHash that goes into the trust cache. The app is made in /Applications/.asoft-stage
# and takes the place of an app of the same name only when it is whole; an app of Apple's (no mark of ours,
# a com.apple.* bundle id or no readable Info.plist) is never replaced.
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
    [string]$WslDistro = '',
    [switch]$NoExceptionPortEntitlement
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
function Fail($m) { Write-Error $m; exit 1 }
function To-Wsl([string]$p) { '/mnt/' + $p.Substring(0, 1).ToLower() + ($p.Substring(2) -replace '\\', '/') }
function Sh-Quote([string]$s) { "'" + ($s -replace "'", "'\''") + "'" }
# The reason ipa-place.py gave for refusing or failing ("ASOFT: ipa-fail ..."), for the message that ends the install
$script:placeFail = ''

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
$nogetPy = Join-Path $scriptsDir 'noget.py'
$ipaHashesPy = Join-Path $scriptsDir 'ipa-hashes.py'   # needs cdhash.py (above) and adhoc.py beside it
$adhocPy = Join-Path $scriptsDir 'adhoc.py'
$placePy = Join-Path $scriptsDir 'ipa-place.py'
$doSh = Join-Path $scriptsDir 'root26-do.sh'
$settleSh = Join-Path $scriptsDir 'hfs-settle.sh'
foreach ($t in @($cdhashPy, $mktcPy, $nogetPy, $ipaHashesPy, $adhocPy, $placePy, $doSh, $settleSh)) { if (-not (Test-Path $t)) { Fail "missing tool $t" } }
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
# opens the disk with its backing chain, the signed app goes in as a second disk: a zip (a .ipa), as the phone's job
# gets it
function Run-HelperJob([string]$jobDir, [string]$appIpa, [string]$disk) {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    New-Item -ItemType Directory -Force "$jobDir\.job" | Out-Null
    Copy-Item $doSh "$jobDir\root26-do.sh"
    Copy-Item $settleSh "$jobDir\hfs-settle.sh"	# root26-do.sh sources it
    Copy-Item $placePy "$jobDir\ipa-place.py"
    [IO.File]::WriteAllText("$jobDir\run.sh", "set -eu`nbash root26-do.sh /work/disk 'bash /work/place.sh'`n", $utf8)
    [IO.File]::WriteAllText("$jobDir\.job\run", "run.sh`n", $utf8)
    [IO.File]::WriteAllText("$jobDir\.job\disks", "d0 disk`nd1 app.ipa`n", $utf8)
    $inTar = Join-Path $tmp 'in.tar'
    & tar.exe -cf $inTar -C $jobDir .
    if ($LASTEXITCODE) { Fail 'tar could not pack the helper VM''s job' }
    $d = @()
    foreach ($x in @(@($inTar, 'in', 'raw', ',readonly=on'), @($disk, 'd0', 'qcow2', ''), @($appIpa, 'd1', 'raw', ',readonly=on'))) {
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
        if ($l -cmatch '^ASOFT: ipa-fail (.+)') { $script:placeFail = $Matches[1] }
        Write-Host "  $l"
    }
    $ErrorActionPreference = 'Stop'
    $rc
}

# The script that runs on the mounted disk ($R), in WSL or in the helper VM (root26-do.sh): the phone's ipa-place.py
# puts the .ipa's app in /Applications/.asoft-stage and, when that went well, swaps it in for an app of the same name.
# ipa-place.py keeps two small result files in /work, which only the phone's helper VM has: here they go in a temporary
# folder (sed on a copy, so the script stays the phone's own). LaunchServices builds its list again at the next start.
function Get-PlaceScript([string]$placeAt, [string]$ipaAt, [string]$ipaName) {
    $t = @'
set -eu
W=$(mktemp -d /tmp/ipa-place.XXXXXX)
trap 'rm -rf "$W"' EXIT
sed "s#/work/#$W/#g" {PLACE} > "$W/ipa-place.py"
if grep -q '/work' "$W/ipa-place.py"; then echo "ASOFT: ipa-fail ipa-place.py names a /work path this installer does not know"; exit 1; fi
drop() { python3 -I "$W/ipa-place.py" --drop "$R" || true; }
python3 -I "$W/ipa-place.py" {IPA} "$R" {NAME} || { rc=$?; drop; exit $rc; }
APP=$(cat "$W/ipa.name")
python3 -I "$W/ipa-place.py" --swap "$R" "$APP" || { rc=$?; drop; exit $rc; }
echo "placed $R/Applications/$APP"
find "$R/private/var/mobile/Containers/Data/InternalDaemon" -maxdepth 4 -name 'com.apple.LaunchServices-*.csstore' 2>/dev/null | while read f; do mv "$f" "$f.stale"; echo "stale: ${f#$R}"; done
echo done
'@
    ($t.Replace('{PLACE}', (Sh-Quote $placeAt)).Replace('{IPA}', (Sh-Quote $ipaAt)).Replace('{NAME}', (Sh-Quote $ipaName))) -replace "`r`n", "`n"
}

# A folder (Payload) as a stored zip whose entries are Payload/..., with / in the names: ZipFile.CreateFromDirectory in
# Windows PowerShell 5.1 writes \ and ipa-place.py, on Linux, then finds no Payload/NAME.app
function Pack-Payload([string]$dir, [string]$zipPath) {
    Add-Type -AssemblyName System.IO.Compression
    $root = (Get-Item -LiteralPath $dir).Parent.FullName.TrimEnd('\') + '\'
    $fs = [IO.File]::Create($zipPath)
    $z = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($item in @(Get-Item -LiteralPath $dir) + @(Get-ChildItem -LiteralPath $dir -Recurse -Force)) {
            $name = $item.FullName.Substring($root.Length) -replace '\\', '/'
            if ($item.PSIsContainer) { [void]$z.CreateEntry($name + '/'); continue }
            $e = $z.CreateEntry($name, [System.IO.Compression.CompressionLevel]::NoCompression)
            $es = $e.Open(); $in = [IO.File]::OpenRead($item.FullName)
            try { $in.CopyTo($es) } finally { $in.Dispose(); $es.Dispose() }
        }
    } finally { $z.Dispose(); $fs.Dispose() }
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

    # A developer-signed .app has get-task-allow = true, which AMFI in the guest refuses (Developer Mode
    # is off). noget.py switches it off in every Mach-O (XML + DER entitlements, same length, special
    # slots rehashed); the CDHashes below are then read from the changed files. Others are left as they are.
    $ErrorActionPreference = 'Continue'   # Windows PowerShell 5.1 turns a native tool's stderr into errors
    $ng = @(Py $nogetPy $app.FullName 2>&1 | ForEach-Object { "$(if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ })".TrimEnd() })
    $ngRc = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $ngDone = @($ng | Where-Object { $_ -cmatch '^get-task-allow off: ' })
    foreach ($l in $ng) { if ($l -cmatch '^FAILED ') { Write-Warning "get-task-allow: $l" } }
    if ($ngRc -and -not ($ng | Where-Object { $_ -cmatch '^FAILED ' })) { Write-Warning "noget.py exited with ${ngRc}: $($ng -join ' | ')" }
    if ($ngDone) { Write-Host "get-task-allow switched off in $($ngDone.Count) file$(if ($ngDone.Count -ne 1) { 's' })" }

    # Every 64-bit slice of every Mach-O gets a signature of ours (adhoc.py, run by ipa-hashes.py): one SHA-256
    # code directory, whatever it came with. A foreign signature that looks usable is not trusted: on the phone a
    # library with restricted entitlements died in dyld ("code signature invalid"). Libraries are signed without
    # entitlements, the main executable keeps its own. Then each slice's CDHash is read back; the install fails
    # unless every slice ends with exactly one that is in the list for the trust cache.
    $rawHashes = Join-Path $tmp 'ipa.hashes'
    $ipaArgs = @($scriptsDir, $app.FullName, $rawHashes)
    if ($NoExceptionPortEntitlement) {
        # ipa-hashes.py's optional 4th argument: a file of entitlement lines; "-default" leaves its default key out
        $entsFile = Join-Path $tmp 'ipa.ents'
        Set-Content -Encoding ASCII $entsFile '-default'
        $ipaArgs += $entsFile
    }
    $ErrorActionPreference = 'Continue'
    $ih = @(Py $ipaHashesPy @ipaArgs 2>&1 | ForEach-Object { "$(if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ })".TrimEnd() })
    $ihRc = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $ihFail = @($ih | Where-Object { $_ -cmatch '^ASOFT: ipa-fail ' })
    if ($ihRc -or $ihFail) {
        Fail "the app's signatures: $(if ($ihFail) { ($ihFail[0] -replace '^ASOFT: ipa-fail ', '') } else { "ipa-hashes.py exited with ${ihRc}: $($ih -join ' | ')" })"
    }
    foreach ($l in $ih) { if ($l -cmatch '^ASOFT: ipa-warn (.+)') { Write-Warning $Matches[1] } }
    $signed = @($ih | Where-Object { $_ -cmatch '^ASOFT: ipa-signed ' })
    if ($signed) { Write-Host "$($signed.Count) file$(if ($signed.Count -ne 1) { 's' }) signed again here so that iOS 26 accepts them" }
    $entAdded = @($ih | Where-Object { $_ -cmatch '^ASOFT: ipa-ent ' } | ForEach-Object { $_ -replace '^ASOFT: ipa-ent ', '' })
    if ($entAdded) { Write-Host "entitlement added to $($entAdded.Count) executable$(if ($entAdded.Count -ne 1) { 's' }): $($entAdded -join ', ')" }
    elseif ($NoExceptionPortEntitlement) { Write-Host 'the exception-port entitlement was left out (-NoExceptionPortEntitlement)' }
    $dropped = @($ih | Where-Object { $_ -cmatch '^ASOFT: ipa-ents-dropped ' } | ForEach-Object { ($_ -split ' ')[2] })
    if ($dropped) { Write-Host "the entitlements of $($dropped.Count) librar$(if ($dropped.Count -ne 1) { 'ies' } else { 'y' }) were left out (only the main executable's count): $($dropped -join ', ')" }
    $hashes = @(Get-Content $rawHashes -ErrorAction SilentlyContinue | Where-Object { "$_" -match '^[0-9a-f]{40}$' })
    if (-not $hashes) { Fail 'no Mach-O with 64-bit code found in the app' }
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

    # The signed app as a .ipa (a zip, stored, Payload\NAME.app\...): what ipa-place.py reads, as on the phone. The
    # extracted folder goes first, so the two never take room together with the guest's disk. (Symlinks of the .ipa came
    # out of the extraction as files, as they always did here.)
    $signedIpa = Join-Path $tmp 'signed.ipa'
    Pack-Payload (Join-Path $ex 'Payload') $signedIpa
    Remove-Item -Recurse -Force $ex
    # (a whole number of sectors for the helper VM's disk; the zip's end record is found from the back past zeros)
    $pad = (512 - ((Get-Item $signedIpa).Length % 512)) % 512
    if ($pad) { $fs = [IO.File]::Open($signedIpa, 'Append'); $fs.Write((New-Object byte[] $pad), 0, $pad); $fs.Close() }

    # place the app into /Applications and rebuild LaunchServices, offline: ipa-place.py (the phone's) makes it in
    # /Applications/.asoft-stage and then swaps it in; root owns it, the folder is root:wheel 0775, every file 0777.
    $jobDir = Join-Path $tmp 'job'
    New-Item -ItemType Directory -Force $jobDir | Out-Null
    $inner = Join-Path $jobDir 'place.sh'
    $placeAt = if ($Linux -ceq 'wsl') { To-Wsl $placePy } else { '/work/ipa-place.py' }
    $ipaAt = if ($Linux -ceq 'wsl') { To-Wsl $signedIpa } else { '/work/app.ipa' }
    (Get-PlaceScript $placeAt $ipaAt ([IO.Path]::GetFileName($Ipa))) | Set-Content -Encoding ASCII -NoNewline $inner

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
        # Windows PowerShell 5.1 turns a native tool's stderr into errors: here they are just lines
        $ErrorActionPreference = 'Continue'
        & wsl -d $WslDistro -u root -- bash (To-Wsl $run) 2>&1 | ForEach-Object {
            $l = "$(if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ })".TrimEnd()
            if ($l -cmatch '^ASOFT: ipa-fail (.+)') { $script:placeFail = $Matches[1] }
            Write-Host $l
        }
        $placeRc = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($placeRc) { Fail "the offline disk edit failed$(if ($script:placeFail) { ": $script:placeFail" })" }
    } else {
        Write-Host 'Placing into /Applications (the helper VM)...'
        $rc = Run-HelperJob $jobDir $signedIpa $AppsDisk
        if ($rc -ne 0) { Fail "the offline disk edit failed in the helper VM$(if ($script:placeFail) { ": $script:placeFail" } else { " (exit $(if ($null -eq $rc) { 'unknown' } else { $rc }))" })" }
    }

    Write-Host ''
    Write-Host "Installed $($app.Name). Boot it with:" -ForegroundColor Green
    Write-Host "  Start-iOS26.ps1 -Disk `"$AppsDisk`" -Tc `"$AppsTc`" -Keep" -ForegroundColor Green
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

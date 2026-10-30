# Install an .ipa into the iOS 26 disk, the way the system apps are installed. The live installd
# path (asoftinstalld -> LSApplicationWorkspace) needs an APFS Data volume, and this disk is HFS+,
# so installd refuses with -4. This instead does what apply-apps.sh does for the system apps: it
# places the .ipa's .app into /Applications in an overlay on the base disk, adds every Mach-O's
# CDHash to a trust cache (so AMFI lets them run), and rebuilds LaunchServices so SpringBoard shows
# the app. The guest must be shut down (it edits the disk offline through WSL).
#
#   Install-Ipa.ps1 -Ipa app.ipa [-Work D:\ios26] [-Wallpaper ios26|collections]
#                   [-Disk base.qcow2] [-Tc base.tc] [-AppsDisk out.qcow2] [-AppsTc out.tc]
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
    [string]$WslDistro = 'ios-emu'
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

# python and the tools next to this script (published) or the dev scripts
$python = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
if (-not $python) { $python = (Get-Command py -ErrorAction SilentlyContinue).Source }
if (-not $python) { Fail 'need Python on PATH' }
function Py { param([string]$script) & $python '-I' $script @args }
$scriptsDir = if (Test-Path (Join-Path $here 'scripts\cdhash.py')) { Join-Path $here 'scripts' } else { $here }
$cdhashPy = Join-Path $scriptsDir 'cdhash.py'
$mktcPy = Join-Path $scriptsDir 'mktc.py'
$doSh = Join-Path $scriptsDir 'root26-do.sh'
foreach ($t in @($cdhashPy, $mktcPy, $doSh)) { if (-not (Test-Path $t)) { Fail "missing tool $t" } }
$qemuImg = @("$here\qemu\qemu-img.exe", "$Work\qemu\qemu-img.exe", 'C:\Program Files\qemu\qemu-img.exe') |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $qemuImg) { Fail 'no qemu-img.exe (looked next to the launcher and in Program Files)' }

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

    # place the .app into /Applications and rebuild LaunchServices, offline through WSL
    $inner = Join-Path $tmp 'place.sh'
    $appWsl = To-Wsl $app.FullName
    @"
set -eu
SRC="$appWsl"
DST="`$R/Applications/$($app.Name)"
rm -rf "`$DST"
cp -a "`$SRC" "`$DST" 2>/dev/null || true
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

    Write-Host "Placing into /Applications (WSL)..."
    & wsl -d $WslDistro -u root -- bash (To-Wsl $doSh) (To-Wsl $AppsDisk) "bash $(To-Wsl $inner)"
    if ($LASTEXITCODE) { Fail 'the offline disk edit failed' }

    Write-Host ''
    Write-Host "Installed $($app.Name). Boot it with:" -ForegroundColor Green
    Write-Host "  Start-iOS26.ps1 -Disk `"$AppsDisk`" -Tc `"$AppsTc`" -Keep" -ForegroundColor Green
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

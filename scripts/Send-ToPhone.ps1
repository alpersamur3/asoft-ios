<#
  Send-ToPhone.ps1: the iOS 16 this PC has installed (ASoftware iOS for Windows) as one file the
  Android app imports, sent to the phone over adb when one is attached.

  The app: ASoftware iOS for Android (com.asoft.ios). Its Set up screen takes the file.

    Send-ToPhone.cmd                     iOS as it was installed (your PC settings and apps stay here)
    Send-ToPhone.cmd -WithMyData         with what iOS on this PC wrote since (settings, apps)
    Send-ToPhone.cmd -NoSend             only make the file; copy it to the phone yourself and pick it
                                         in the app (Set up > Choose file)

  The file holds iOS's disk (one compressed qcow2) and the kernel with this iPhone's device tree
  (payload.bin), made from what the PC installer downloaded from Apple. It stays on your devices:
  do not share it.
#>
param(
    [string]$Dir,
    [string]$Work,
    [string]$Out = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'ASoftware-iOS16.asoft'),
    [switch]$WithMyData,
    [switch]$NoSend
)
$ErrorActionPreference = 'Stop'
$Package = 'com.asoft.ios'
# the boot-args the phone uses; the app puts the phone's time zone, region and clock in at import
$CmdLine = 'debug=0xc serial=3 cpus=4 keepsyms=1 -enable_kprintf_spam -noprogress rd=vblkroot0 vblkrw=1 ' +
    'rootrw=1 unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin ' +
    'launchd_unsecure_cache=1 wdt=-1 sweetfb_hz=30 launchd_disable_all_timeouts=1 sweetfb_noconsole=1 ' +
    'sweetfb_keepon=1'

function Say($s) { Write-Host $s }

# A native tool, its output shown, its exit code checked (PowerShell 5.1 turns a native
# program's stderr into errors under -ErrorAction Stop)
function Run([string]$exe, [string[]]$a) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $exe @a 2>&1 | ForEach-Object { Write-Host "  $_" }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($code) { throw "$([IO.Path]::GetFileName($exe)) failed ($code)" }
}

# -- where the PC install is: the folder this script is in (an install or a checkout), else the installer's record
if (-not $Dir -and (Test-Path (Join-Path $PSScriptRoot '..\tools\mkpayload.py'))) { $Dir = (Resolve-Path "$PSScriptRoot\..").Path }
if (-not $Dir) {
    $setup = Join-Path $env:LOCALAPPDATA 'ASoftware\setup.json'
    if (Test-Path $setup) { $Dir = (Get-Content $setup -Raw | ConvertFrom-Json).Dir }
    if (-not $Dir -or -not (Test-Path $Dir)) { $Dir = Join-Path $env:LOCALAPPDATA 'ASoftware iOS' }
}
if (-not (Test-Path "$Dir\tools\mkpayload.py")) {
    throw "No ASoftware iOS install in ${Dir}: install iOS 16 on this PC first, or give -Dir"
}
if (-not $Work) { $Work = if ($env:ASOFT_WORK) { $env:ASOFT_WORK } else { "$Dir\work" } }

$base = @("$Work\root\ios16-base.qcow2", "$Work\root\ios16-root-20H392-v5.qcow2") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $base) { throw "No iOS 16 disk in $Work\root: install iOS 16 on this PC first" }
$disk = $base
if ($WithMyData) {
    if (-not (Test-Path "$Work\root\ios16-user.qcow2")) { throw "No $Work\root\ios16-user.qcow2: iOS has not run on this PC yet" }
    $disk = "$Work\root\ios16-user.qcow2"
}
$qemuImg = @("$Work\qemu\qemu-img.exe", "$Work\qemu\v11.1.2-asoft\qemu-img.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $qemuImg) { $qemuImg = (Get-Command qemu-img -ErrorAction SilentlyContinue).Source }
if (-not $qemuImg) { throw "No qemu-img in $Work\qemu" }
$python = "$Dir\python\python.exe"
if (-not (Test-Path $python)) { $python = (py -3.12 -c 'import sys; print(sys.executable)') }
$kernel = Get-ChildItem "$Dir\xnu\out-*\kernel.development.sweet" -ErrorAction SilentlyContinue |
    Sort-Object { $_.Directory.Name } | Select-Object -Last 1
if (-not $kernel) { throw "No kernel in $Dir\xnu" }
$adt = @("$Work\firmware\d22ap.adt", "$Dir\research\ipsw-x\d22ap.adt") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $adt) { throw "No device tree ($Work\firmware\d22ap.adt)" }

Say "iOS disk:  $disk"
Say "Kernel:    $($kernel.FullName)"
$tmp = "$Work\tmp\phone-bundle"
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    # -- the kernel with this iPhone's device tree
    $env:ASOFT_DEVICE_TREE = $adt
    Run $python @("$Dir\tools\mkadt.py", "$tmp\qemu.adt", '--qemu', '--highmem')
    Run $python @("$Dir\tools\mkpayload.py", $kernel.FullName, "$tmp\qemu.adt", "$tmp\payload.bin", '--cmdline', $CmdLine)

    # -- the disk: its backing chain in one file, zstd-compressed clusters (the phone reads them as they are)
    $free = (Get-PSDrive ([IO.Path]::GetPathRoot($tmp).Substring(0, 1))).Free
    Say "Packing the disk (a few minutes; $([math]::Round($free / 1GB)) GB free on that drive)"
    Run $qemuImg @('convert', '-p', '-O', 'qcow2', '-c', '-o', 'compression_type=zstd', $disk, "$tmp\disk.qcow2")

    @{ format = 1; ios = '16'; build = '20H392'; kernel = $kernel.Directory.Name; withMyData = [bool]$WithMyData
       made = (Get-Date).ToString('s'); diskBytes = (Get-Item "$tmp\disk.qcow2").Length } |
        ConvertTo-Json | Set-Content -Encoding ASCII "$tmp\asoft-bundle.json"

    # -- one file: tar (Windows' own bsdtar), manifest first so the app can check it before the rest
    Remove-Item -Force $Out -ErrorAction SilentlyContinue
    Run "$env:SystemRoot\System32\tar.exe" @('-cf', $Out, '-C', $tmp, 'asoft-bundle.json', 'payload.bin', 'disk.qcow2')
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
$size = (Get-Item $Out).Length
Say "Made $Out ($([math]::Round($size / 1GB, 1)) GB)"

# -- to the phone
$adb = @((Get-Command adb -ErrorAction SilentlyContinue).Source, "$Work\platform-tools\adb.exe",
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe") | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
$sent = $false
if (-not $NoSend -and $adb) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $state = (& $adb get-state 2>$null)
    $ErrorActionPreference = $old
    if ($state -eq 'device') {
        $dest = "/sdcard/Android/data/$Package/files/import"
        Say "Sending to the phone ($dest)"
        Run $adb @('shell', "mkdir -p $dest")
        Run $adb @('push', $Out, "$dest/")
        $sent = $true
    }
}
if ($sent) {
    Say 'Done. On the phone: open ASoftware iOS, Set up > Import.'
} else {
    Say 'Copy the file to the phone (USB cable, File Explorer: the phone''s Download folder),'
    Say 'then on the phone: ASoftware iOS > Set up > Choose file.'
}

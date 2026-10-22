# ASoftware iOS: build the iOS disk from an IPSW, on Windows alone. Our QEMU starts the
# helper VM (installer/helper: a small arm64 Linux), which reads the IPSW in place,
# unpacks what it must, and writes the iOS root onto a new qcow2 disk. No WSL, no admin.
#   powershell -ExecutionPolicy Bypass -File installer\Build-iOSDisk.ps1 -Ipsw X.ipsw -Out root.qcow2
param(
    [Parameter(Mandatory = $true)] [string]$Ipsw,
    [Parameter(Mandatory = $true)] [string]$Out,
    [string]$Qemu = "$env:ASOFT_WORK\qemu\v11.1.2-asoft\qemu-system-aarch64.exe",
    # Image.gz and initrd.gz from installer/helper/build-*.sh
    [string]$Helper = "$PSScriptRoot\helper\out",
    [int]$Cpus = 4,
    # the helper's serial log, next to the new disk unless given
    [string]$Log = "$Out.log"
)
$ErrorActionPreference = 'Stop'
if (Test-Path $Out) { throw "$Out exists already" }
$qemuImg = Join-Path (Split-Path $Qemu) 'qemu-img.exe'
foreach ($f in $Ipsw, $Qemu, $qemuImg, "$Helper\Image.gz", "$Helper\initrd.gz") {
    if (-not (Test-Path $f)) { throw "missing: $f" }
}

# The new disk, and scratch room for the images the IPSW's zip deflated (2.7 GB for 20H392)
$scratch = "$Out.scratch.qcow2"
& $qemuImg create -q -f qcow2 $Out 16G
& $qemuImg create -q -f qcow2 $scratch 4G
if ($LASTEXITCODE) { throw 'qemu-img failed' }

# A comma in a -drive file name must be doubled (IPSW names have one: iPhone10,3_...)
function Escape([string]$path) { $path -replace ',', ',,' }

# cortex-a76, not max: pointer authentication, which max has, is slow under TCG.
# cache=unsafe: no flushes while the disk is built; a crash means building it again anyway.
$qemuArgs = @('-M', 'virt', '-cpu', 'cortex-a76', '-smp', $Cpus, '-m', '3G',
    '-kernel', "$Helper\Image.gz", '-initrd', "$Helper\initrd.gz",
    '-append', 'console=ttyAMA0 loglevel=4 asoft.job=build-root',
    '-display', 'none', '-monitor', 'none', '-serial', 'stdio', '-no-reboot', '-nic', 'none',
    '-drive', "file=$(Escape $Ipsw),format=raw,readonly=on,if=none,id=ipsw",
    '-device', 'virtio-blk-device,drive=ipsw,serial=ipsw',
    '-drive', "file=$(Escape $Out),format=qcow2,if=none,id=root,cache=unsafe",
    '-device', 'virtio-blk-device,drive=root,serial=root',
    '-drive', "file=$(Escape $scratch),format=qcow2,if=none,id=scratch,cache=unsafe",
    '-device', 'virtio-blk-device,drive=scratch,serial=scratch')

$started = Get-Date
$result = $null
& $Qemu @qemuArgs 2>&1 | ForEach-Object {
    $line = "$_"
    Add-Content -Path $Log -Value $line
    if ($line -match '^ASOFT: progress (\d+) (.*)$') {
        $pct = [int]$Matches[1]
        $elapsed = [int]((Get-Date) - $started).TotalMinutes
        Write-Progress -Activity 'Building the iOS disk' -Status "$($Matches[2]) ($elapsed min)" -PercentComplete $pct
    } elseif ($line -match '^ASOFT: done (\d+)') {
        $result = [int]$Matches[1]
    } elseif ($line -match '^ASOFT: ') {
        Write-Host $line
    }
}
Write-Progress -Activity 'Building the iOS disk' -Completed
Remove-Item $scratch -ErrorAction SilentlyContinue
if ($result -ne 0) {
    Remove-Item $Out -ErrorAction SilentlyContinue
    throw "building the iOS disk failed (helper exit $result); log: $Log"
}
Write-Host "iOS disk: $Out ($([int]((Get-Date) - $started).TotalMinutes) min)"

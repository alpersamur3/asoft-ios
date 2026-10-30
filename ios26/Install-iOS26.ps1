# iOS 26 installer: the setup the research preview needs on this PC, in one place.
#
# Unlike the iOS 16 installer, iOS 26 is a research preview: the disk, firmware, device tree, trust
# cache and GPU driver are *built* from your own Apple downloads by the steps in README.md (WSL and
# several hours), and some steps are still by hand. So this does not download Apple's files or build
# the disk for you. What it does:
#   1. Setup: ask where the work folder is and whether you have the guest GPU driver (a folder
#      picker), and save it to the config. Without a driver iOS runs GPU-less (slower).
#   2. Check: report which build outputs are present in the work folder and which the README build
#      steps still need, so you know what is left.
#   3. Shortcut: a Start Menu shortcut to Start-iOS26.cmd (the menu launcher), unless -NoShortcut.
#
#   powershell -ExecutionPolicy Bypass -File ios26\Install-iOS26.ps1 [-Work D:\ios26] [-NoShortcut]
param(
    [string]$Work = $env:ASOFT26_WORK,
    [string]$Config = (Join-Path $env:LOCALAPPDATA 'ASoftware iOS 26\ios26.config.json'),
    [switch]$NoShortcut
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

function Step([string]$t) { Write-Host ''; Write-Host "== $t" -ForegroundColor Cyan }

Step '1/3 Setup (work folder, GPU driver)'
# The menu owns the config and the GPU-driver question; run it in setup-only mode.
$menu = Join-Path $here 'Start-iOS26-Menu.ps1'
$menuArgs = @('-SetupOnly', '-Config', $Config)
if ($Work) { $menuArgs += @('-Work', $Work) }
& powershell -NoProfile -ExecutionPolicy Bypass -File $menu @menuArgs
if ($LASTEXITCODE) { throw 'setup did not finish' }
$cfg = Get-Content $Config -Raw | ConvertFrom-Json
$Work = $cfg.Work

Step '2/3 What the work folder has'
# The build outputs Start-iOS26.ps1 needs, and the README step that makes each one.
$needs = [ordered]@{
    'fw\bootkc'     = '3 (unwrap-fw.sh)'
    'fw\sptm'       = '3 (unwrap-fw.sh)'
    'fw\txm'        = '3 (unwrap-fw.sh)'
    'dtree-smp4'    = '3 (dt-root26smp.py --cpus 4)'
    'rd-shell.hfs'  = '3 (mk-ramdisk.sh)'
    'root.tc'       = '4-5 (mktc.py)'
    'root.qcow2'    = '4-5 (mk-root26*.sh + overlays)'
    'qemu\qemu-system-aarch64w.exe' = '1 (win-build.sh), or qemu\qemu-system-aarch64.exe'
}
$missing = @()
foreach ($rel in $needs.Keys) {
    $alt = if ($rel -like 'qemu\*w.exe') { Join-Path $Work 'qemu\qemu-system-aarch64.exe' } else { $null }
    $ok = (Test-Path (Join-Path $Work $rel)) -or ($alt -and (Test-Path $alt))
    $mark = if ($ok) { '[ok]  ' } else { '[need]' }
    $color = if ($ok) { 'Green' } else { 'Yellow' }
    Write-Host ("  {0} {1,-32} README step {2}" -f $mark, $rel, $needs[$rel]) -ForegroundColor $color
    if (-not $ok) { $missing += $rel }
}
if ($cfg.GpuMode -eq 'gpu' -and $cfg.GpuDriver) {
    Write-Host ("  note: the disk must be built with your GPU driver baked in (README step 5.2):") -ForegroundColor DarkGray
    Write-Host ("        $($cfg.GpuDriver)") -ForegroundColor DarkGray
} elseif ($cfg.GpuMode -eq 'gpuless') {
    Write-Host "  note: GPU-less setup - build the disk without step 5.2; iOS draws on the CPU (slower)." -ForegroundColor DarkGray
}
Write-Host "  build: the launcher needs qemu-sptm ios26 4eee4e5+ and reims-vgpu windows 65e09172+" -ForegroundColor DarkGray
Write-Host "         (older QEMU rejects usb-kbd idle-reports and will not boot); rebuild if older." -ForegroundColor DarkGray

Step '3/3 Shortcut'
if ($missing.Count) {
    Write-Host ("Not ready yet: {0} build output(s) still needed. Follow README.md > Build for the steps above." -f $missing.Count) -ForegroundColor Yellow
}
if (-not $NoShortcut) {
    $cmd = Join-Path $here 'Start-iOS26.cmd'
    $lnkDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $lnk = Join-Path $lnkDir 'ASoftware iOS 26.lnk'
    try {
        $sh = New-Object -ComObject WScript.Shell
        $s = $sh.CreateShortcut($lnk)
        $s.TargetPath = $cmd
        $s.WorkingDirectory = $here
        $s.Description = 'iOS 26 in a window (research preview)'
        $s.Save()
        Write-Host "Shortcut: $lnk" -ForegroundColor Green
    } catch {
        Write-Host "could not create the shortcut ($($_.Exception.Message))" -ForegroundColor Yellow
    }
}
Write-Host ''
Write-Host 'Done. Start with Start-iOS26.cmd (the menu) when the work folder is complete.' -ForegroundColor Cyan

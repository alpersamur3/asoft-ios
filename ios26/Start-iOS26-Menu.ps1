# iOS 26 start menu: remembers your setup and offers the start options every time, as the iOS 16
# launcher does. Start-iOS26.cmd runs this; it then calls Start-iOS26.ps1 with your choices.
#
# The config is %LOCALAPPDATA%\ASoftware iOS 26\ios26.config.json: the work folder, the guest GPU
# driver, the wallpaper, the disk mode, the network. First run (or an empty setting) asks for it,
# with a folder picker for the work folder and the GPU driver; later starts reuse it.
#
# The guest GPU driver (AppleParavirtGPUMetalIOGPUFamily.bundle, which you extract yourself, see
# README.md) is baked into the disk when the disk is built, not read at run time. So this records
# where it is and whether the disk was built with it (GpuMode). Without it iOS draws on the CPU and
# the host only shows the frames: it still reaches the home screen, but everything is slower.
#
#   Start-iOS26-Menu.ps1 [-Work D:\ios26] [-NoMenu]   (-NoMenu: start at once with the saved setup)
param(
    [string]$Work = $env:ASOFT26_WORK,
    [switch]$NoMenu,
    # -SetupOnly: fill the config (work folder, GPU driver) and exit, without the menu or starting.
    # The installer (Install-iOS26.ps1) uses it so the setup lives in one place.
    [switch]$SetupOnly,
    # the config file; default under %LOCALAPPDATA%
    [string]$Config = (Join-Path $env:LOCALAPPDATA 'ASoftware iOS 26\ios26.config.json')
)
$ErrorActionPreference = 'Stop'

# --- config load/save -------------------------------------------------------
$default = [ordered]@{
    Work      = ''
    GpuDriver = ''          # path to AppleParavirtGPUMetalIOGPUFamily.bundle, or '' for none
    GpuMode   = ''          # 'gpu' | 'gpuless' | '' (not chosen yet)
    Wallpaper = 'ios26'     # 'ios26' | 'collections'
    DiskMode  = 'persist'   # 'throwaway' | 'persist' | 'keep'
    Net       = $true
    Smp       = 4
}
function Load-Config {
    $cfg = [ordered]@{}
    foreach ($k in $default.Keys) { $cfg[$k] = $default[$k] }
    if (Test-Path $Config) {
        try {
            $saved = Get-Content $Config -Raw | ConvertFrom-Json
            foreach ($k in @($default.Keys)) {
                if ($null -ne $saved.$k) { $cfg[$k] = $saved.$k }
            }
        } catch {
            Write-Host "config unreadable ($($_.Exception.Message)); starting fresh" -ForegroundColor Yellow
        }
    }
    $cfg
}
function Save-Config($cfg) {
    New-Item -ItemType Directory -Force (Split-Path $Config) | Out-Null
    ($cfg | ConvertTo-Json) | Set-Content -Encoding UTF8 $Config
}

# --- folder picker (a .bundle is a folder; the work folder is one too) ------
function Pick-Folder([string]$description, [string]$start) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = $description
        $dlg.ShowNewFolderButton = $false
        if ($start -and (Test-Path $start)) { $dlg.SelectedPath = $start }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    } catch {
        # no GUI (headless/remote): fall back to typing the path
        Write-Host "$description"
        $typed = Read-Host 'Path (blank to cancel)'
        if ($typed) { return $typed }
    }
    return $null
}

function Ask-YesNo([string]$q, [bool]$default) {
    $suffix = if ($default) { '[Y/n]' } else { '[y/N]' }
    $a = Read-Host "$q $suffix"
    if (-not $a) { return $default }
    return $a -match '^[yYeE]'          # y or e(vet)
}

# --- setup: fill anything the config is missing -----------------------------
function Ensure-Setup($cfg) {
    # work folder
    if ($Work) { $cfg.Work = (Resolve-Path $Work).Path }
    if (-not $cfg.Work -or -not (Test-Path $cfg.Work)) {
        Write-Host ''
        Write-Host 'Where is the iOS 26 work folder? (fw\, dtree-smp4, root.qcow2, root.tc, qemu\ ...)'
        $picked = Pick-Folder 'Select the iOS 26 work folder' $cfg.Work
        if (-not $picked) { throw 'no work folder chosen (set -Work or $env:ASOFT26_WORK)' }
        $cfg.Work = $picked
    }
    # GPU driver / GPU mode
    if (-not $cfg.GpuMode) {
        Write-Host ''
        Write-Host 'The guest GPU driver (AppleParavirtGPUMetalIOGPUFamily.bundle) makes iOS draw on your'
        Write-Host "PC's GPU. You extract it yourself (README.md). It is baked into the disk when the disk"
        Write-Host 'is built; this only records where it is.'
        if (Ask-YesNo 'Do you have the guest GPU driver bundle?' $true) {
            $picked = Pick-Folder 'Select AppleParavirtGPUMetalIOGPUFamily.bundle' (Split-Path $cfg.GpuDriver)
            if ($picked) {
                $cfg.GpuDriver = $picked
                $cfg.GpuMode = 'gpu'
                if ((Split-Path $picked -Leaf) -notlike '*.bundle') {
                    Write-Host "note: '$([IO.Path]::GetFileName($picked))' is not a *.bundle folder; keeping it anyway" -ForegroundColor Yellow
                }
            } else {
                $cfg.GpuMode = 'gpuless'
            }
        } else {
            $cfg.GpuMode = 'gpuless'
        }
        if ($cfg.GpuMode -eq 'gpuless') {
            Write-Host ''
            Write-Host 'Running GPU-less: iOS draws on the CPU and the host only shows the frames. It reaches' -ForegroundColor Yellow
            Write-Host 'the home screen but everything is slower. Add the GPU driver later and rebuild the disk' -ForegroundColor Yellow
            Write-Host 'to turn it on (README.md, step 5.2).' -ForegroundColor Yellow
        }
    }
    Save-Config $cfg
}

# --- the menu ---------------------------------------------------------------
function Show-Menu($cfg) {
    while ($true) {
        Write-Host ''
        Write-Host '  ASoftware iOS 26' -ForegroundColor Cyan
        Write-Host ('  Work      : {0}' -f $cfg.Work)
        Write-Host ('  GPU       : {0}{1}' -f $cfg.GpuMode, $(if ($cfg.GpuDriver) { " ($($cfg.GpuDriver))" } else { '' }))
        Write-Host ('  Wallpaper : {0}' -f $cfg.Wallpaper)
        Write-Host ('  Disk      : {0}' -f $cfg.DiskMode)
        Write-Host ('  Network   : {0}  (.ipa installs need it)' -f $(if ($cfg.Net) { 'on' } else { 'off' }))
        Write-Host ('  vCPUs     : {0}' -f $cfg.Smp)
        Write-Host ''
        Write-Host '  [S] Start      [W] Wallpaper   [D] Disk mode   [N] Network'
        Write-Host '  [G] GPU driver [C] vCPUs       [R] Reset saved state (persist)   [Q] Quit'
        switch ((Read-Host 'Choose').ToUpper()) {
            'S' { return $true }
            '' { return $true }
            'W' { $cfg.Wallpaper = if ($cfg.Wallpaper -eq 'ios26') { 'collections' } else { 'ios26' } }
            'D' {
                $cfg.DiskMode = switch ($cfg.DiskMode) { 'persist' { 'throwaway' } 'throwaway' { 'keep' } default { 'persist' } }
            }
            'N' { $cfg.Net = -not $cfg.Net }
            'C' { $cfg.Smp = if ($cfg.Smp -eq 4) { 8 } else { 4 } }
            'G' {
                $picked = Pick-Folder 'Select AppleParavirtGPUMetalIOGPUFamily.bundle' (Split-Path $cfg.GpuDriver)
                if ($picked) { $cfg.GpuDriver = $picked; $cfg.GpuMode = 'gpu' }
                else { if (Ask-YesNo 'No driver: run GPU-less (slower)?' $false) { $cfg.GpuDriver = ''; $cfg.GpuMode = 'gpuless' } }
            }
            'R' { $cfg.DiskMode = 'persist'; $script:ResetState = $true; Write-Host 'The persist overlay will be reset on the next start.' }
            'Q' { return $false }
            default { }
        }
        Save-Config $cfg
    }
}

# --- build the Start-iOS26.ps1 arguments and run it -------------------------
function Start-Emulator($cfg) {
    Save-Config $cfg
    $ps1 = Join-Path $PSScriptRoot 'Start-iOS26.ps1'
    if (-not (Test-Path $ps1)) { throw "Start-iOS26.ps1 not found next to this menu" }
    $a = @('-Work', $cfg.Work, '-Wallpaper', $cfg.Wallpaper, '-Smp', $cfg.Smp)
    switch ($cfg.DiskMode) {
        'persist'   { $a += '-Persist'; if ($script:ResetState) { $a += '-Reset' } }
        'keep'      { $a += '-Keep' }
        'throwaway' { }      # the default throwaway overlay
    }
    if ($cfg.Net) { $a += '-Net' }
    # GpuMode is a property of the disk (was the guest driver baked in?), not a launch flag: the
    # launcher runs pvg=reims either way, and host GL scaling (gl=on, the default) helps in both.
    Write-Host ''
    Write-Host ("Start-iOS26.ps1 {0}" -f ($a -join ' ')) -ForegroundColor DarkGray
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ps1 @a
}

# --- main -------------------------------------------------------------------
$script:ResetState = $false
$cfg = Load-Config
Ensure-Setup $cfg
if ($SetupOnly) { Write-Host "Setup saved to $Config"; return }
$go = if ($NoMenu) { $true } else { Show-Menu $cfg }
if ($go) { Start-Emulator $cfg } else { Write-Host 'Not started.' }

# ASoftware iOS installer: everything to run iOS 16 on this PC, in one folder, with no
# admin rights, WSL or Mac:
#   1. the app (launcher, tools, kernel, helper VM) and our QEMU build
#   2. Python (python.org's embeddable package) for the launcher's tools
#   3. the iPhone X iOS 16.7.16 IPSW, from Apple (6.2 GB; -Ipsw uses one you have), and its
#      device tree (tools/ipsw-devicetree.py) for the launcher's ADT
#   4. the iOS disk, built from the IPSW by the helper VM (Build-iOSDisk.ps1)
#   5. iOS's first start, which sets up its app database once (20-30 min)
#   6. a desktop shortcut
# Each step is skipped when its result is there already, so running it again resumes.
#   powershell -ExecutionPolicy Bypass -File installer\Install-ASoftware.ps1 [-Dir D:\ASoftware] [-Ipsw X.ipsw]
param(
    [string]$Dir = "$env:LOCALAPPDATA\ASoftware iOS",
    [string]$Ipsw = '',
    # our QEMU build with its DLLs: the release package's qemu\bin, else qemu/build-windows.sh's
    # dist or the qemu-win workflow artifact
    [string]$QemuDist = $(if (Test-Path "$PSScriptRoot\..\qemu\bin\qemu-system-aarch64.exe") { "$PSScriptRoot\..\qemu\bin" }
                          elseif ($env:ASOFT_WORK) { "$env:ASOFT_WORK\qemu\v11.1.2-asoft" } else { '' }),
    [int]$Cpus = 4,
    # keep the downloaded IPSW once the iOS disk is built (6.2 GB; it can be downloaded again)
    [switch]$KeepIpsw,
    [switch]$NoShortcut
)
$ErrorActionPreference = 'Stop'
# A native tool's stderr lines are notes, not failures: Windows PowerShell 5.1 turns them into
# errors when the script's output is redirected, which 'Stop' would end the script on. Its exit
# code ($LASTEXITCODE) says how it went.
function Invoke-Tool {
    $ErrorActionPreference = 'Continue'
    $rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
    & $args[0] @rest
}
$ProgressPreference = 'Continue'
$src = Resolve-Path "$PSScriptRoot\.."
$work = "$Dir\work"

# The IPSW our kernel and tweaks are made for, as Apple serves it
$ipswUrl = 'https://updates.cdn-apple.com/2025FallFCS/fullrestores/122-77006/1158E502-D76D-4226-AA06-ED5E30CD1111/iPhone10,3,iPhone10,6_16.7.16_20H392_Restore.ipsw'
$ipswSha256 = 'ECE1194F7E233E9109C5790A8D23A4564A10A254E15EC5B09978A343265568FB'
$ipswSize = 6171035648
$pythonUrl = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip'

# Disk space in GB as Windows shows them, measured for 20H392: the IPSW, the iOS disk as built
# and after iOS's first start, the room the helper unpacks the IPSW into, the rest, and a saved
# state (the quick boot's, or one Save state makes) in the user disk
$space = @{ Ipsw = 5.75; Disk = 11.7; DiskReady = 12.2; Scratch = 7.0; App = 0.3; State = 3.0 }

function Step([string]$text) { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }

# A QEMU QMP command over TCP (the first start's power-down)
function Send-Qmp([int]$port, [string]$command) {
    $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $port)
    try {
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true
        [void]$reader.ReadLine()                                  # greeting
        $writer.WriteLine('{"execute":"qmp_capabilities"}'); [void]$reader.ReadLine()
        $writer.WriteLine("{`"execute`":`"$command`"}"); [void]$reader.ReadLine()
    } finally { $client.Close() }
}

Step "Installing to $Dir"
New-Item -ItemType Directory -Force $Dir, "$work\root", "$work\ipsw", "$work\ipa" | Out-Null
$drive = $Dir.Substring(0, 2)
$free = (Get-PSDrive $Dir.Substring(0, 1)).Free / 1GB
# What is still to come here: no IPSW download with -Ipsw or once the disk and the device tree
# are there, nothing to build once the disk is
$deviceTree = "$work\firmware\d22ap.adt"
$needIpsw = -not (Test-Path "$work\root\ios16-base.qcow2") -or -not (Test-Path $deviceTree)
$needed = $space.App
$parts = @('app {0:N1}' -f $space.App)
if ($needIpsw -and -not $Ipsw) { $needed += $space.Ipsw; $parts += 'iOS image {0:N1}' -f $space.Ipsw }
if (-not (Test-Path "$work\root\ios16-base.qcow2")) {
    $needed += $space.DiskReady + $space.Scratch
    $parts += ('iOS disk {0:N1}' -f $space.DiskReady), ('room to build it {0:N1}' -f $space.Scratch)
}
$installed = $space.DiskReady + $space.App + $(if ($KeepIpsw -and -not $Ipsw) { $space.Ipsw } else { 0 })
Write-Host ('Disk space on {0} ({1:N1} GB free):' -f $drive, $free)
Write-Host ('  needed while installing: about {0:N1} GB ({1})' -f $needed, ($parts -join ' + '))
Write-Host ('  once installed:          about {0:N0} GB, plus what iOS stores as you use it' -f $installed)
Write-Host ('                           and {0:N0} GB per saved state (quick boot keeps one while iOS is closed)' -f $space.State)
if ($free -lt $needed + 1) {
    throw ('{0:N1} GB free on {1}, about {2:N0} GB needed: free some space or use -Dir on another drive' -f $free, $drive, ($needed + 1))
}

Step '1/6 App files'
if ($src.Path -ne (Resolve-Path $Dir).Path) {
    foreach ($item in 'Start-iOS.cmd', 'LICENSE', 'README.md') { Copy-Item "$src\$item" $Dir -Force }
    foreach ($folder in 'scripts', 'tools', 'assets') {
        robocopy "$src\$folder" "$Dir\$folder" /MIR /XD __pycache__ /NFL /NDL /NJH /NJS /NP | Out-Null
    }
    New-Item -ItemType Directory -Force "$Dir\installer\helper\out", "$Dir\xnu" | Out-Null
    Copy-Item "$src\installer\*.ps1" "$Dir\installer\" -Force
    Copy-Item "$src\installer\helper\out\Image.gz", "$src\installer\helper\out\initrd.gz" "$Dir\installer\helper\out\" -Force
    # the newest kernel build
    $kernel = Get-ChildItem "$src\xnu\out-*\kernel.development.sweet" | Sort-Object { $_.Directory.Name } | Select-Object -Last 1
    if (-not $kernel) { throw "no kernel in $src\xnu\out-*" }
    robocopy $kernel.Directory.FullName "$Dir\xnu\$($kernel.Directory.Name)" kernel.development.sweet /NFL /NDL /NJH /NJS /NP | Out-Null
}
$qemuDir = "$work\qemu\v11.1.2-asoft"
if (-not (Test-Path "$qemuDir\qemu-system-aarch64.exe")) {
    if (-not $QemuDist -or -not (Test-Path "$QemuDist\qemu-system-aarch64.exe")) { throw 'give -QemuDist: the folder of our QEMU build' }
    robocopy $QemuDist $qemuDir /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
}
$qemu = "$qemuDir\qemu-system-aarch64.exe"
Write-Host (& $qemu --version | Select-Object -First 1)

Step '2/6 Python'
if (-not (Test-Path "$Dir\python\python.exe")) {
    $zip = "$env:TEMP\asoft-python.zip"
    Invoke-Tool curl.exe -fL --retry 3 -o $zip $pythonUrl
    if ($LASTEXITCODE) { throw "could not download $pythonUrl" }
    Expand-Archive $zip "$Dir\python" -Force
    Remove-Item $zip
}
& "$Dir\python\python.exe" --version

Step '3/6 iOS 16.7.16 (iPhone X) from Apple'
if ($needIpsw) {
    if (-not $Ipsw) {
        $Ipsw = "$work\ipsw\iPhone10,3_16.7.16_20H392_Restore.ipsw"
        if (-not (Test-Path $Ipsw) -or (Get-Item $Ipsw).Length -ne $ipswSize) {
            Write-Host "Downloading 6.2 GB from Apple; if it stops, run the installer again to resume."
            Invoke-Tool curl.exe -fL --retry 5 -C - -o $Ipsw $ipswUrl
            if ($LASTEXITCODE) { throw "the download stopped (curl $LASTEXITCODE); run the installer again to resume" }
        }
    }
    Write-Host 'Checking the IPSW...'
    if ((Get-FileHash $Ipsw -Algorithm SHA256).Hash -ne $ipswSha256) {
        throw "$Ipsw is not Apple's iOS 16.7.16 IPSW for the iPhone X (SHA-256 differs)"
    }
}
# The iPhone X's device tree: the launcher's ADT takes its /product from it (screen, artwork,
# model names), without which SpringBoard cannot draw
if (-not (Test-Path $deviceTree)) {
    Invoke-Tool "$Dir\python\python.exe" "$Dir\tools\ipsw-devicetree.py" $Ipsw $deviceTree
    if ($LASTEXITCODE) { throw "could not take the device tree from $Ipsw" }
}

Step '4/6 The iOS disk'
$base = "$work\root\ios16-base.qcow2"
$building = "$work\root\ios16-base.building.qcow2"
if (-not (Test-Path $base)) {
    Remove-Item "$building*" -ErrorAction SilentlyContinue
    & "$Dir\installer\Build-iOSDisk.ps1" -Ipsw $Ipsw -Out $building -Qemu $qemu -Helper "$Dir\installer\helper\out"
    Move-Item $building $base
}

Step '5/6 First start of iOS (once, 20-30 min)'
$ready = "$work\root\ios16-base.ready"
if (-not (Test-Path $ready)) {
    $qmpPort = 4447
    $started = Get-Date
    $runs = "$work\runs"
    $before = @(Get-ChildItem $runs -Directory -ErrorAction SilentlyContinue | ForEach-Object Name)
    # headless, writing into the new disk itself: what iOS sets up now is part of it
    $boot = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile',
        '-ExecutionPolicy', 'Bypass', '-File', "`"$Dir\scripts\run-windows.ps1`"", '-Work', "`"$work`"",
        '-Disk', "`"$base`"", '-Keep', '-Display', 'none', '-IpaDir', "''", '-QmpPort', $qmpPort, '-Cpus', $Cpus
    # iOS turns the display off once while it boots and on again when SpringBoard is up,
    # which on the first start waits until the app database is built
    $up = $false
    while (-not $boot.HasExited) {
        Start-Sleep -Seconds 10
        $run = Get-ChildItem $runs -Directory -ErrorAction SilentlyContinue |
            Where-Object { $before -notcontains $_.Name } | Sort-Object Name | Select-Object -Last 1
        $serial = if ($run) { "$($run.FullName)\run\serial.txt" } else { '' }
        $minutes = [int]((Get-Date) - $started).TotalMinutes
        Write-Progress -Activity 'First start of iOS' -Status "setting up iOS ($minutes min)" -PercentComplete ([Math]::Min(95, $minutes * 3))
        if ($serial -and (Test-Path $serial)) {
            $power = Select-String -Path $serial -Pattern 'SWEET FB: display (on|off)' | ForEach-Object { $_.Matches[0].Groups[1].Value }
            if (($power -join ' ') -match 'off on') { $up = $true; break }
        }
        if ($minutes -gt 90) { break }
    }
    Write-Progress -Activity 'First start of iOS' -Completed
    if ($up) {
        Start-Sleep -Seconds 60                                       # let it settle, then power down
        Send-Qmp $qmpPort 'system_powerdown'
        if (-not $boot.WaitForExit(120000)) { Stop-Process -Id $boot.Id -Force }
        New-Item -ItemType File $ready | Out-Null
        Write-Host "iOS is set up ($([int]((Get-Date) - $started).TotalMinutes) min)"
    } else {
        if (-not $boot.HasExited) { Send-Qmp $qmpPort 'quit' }
        throw "iOS did not finish its first start; the kernel log is under $runs"
    }
}
# The downloaded IPSW is not needed any more (Apple keeps serving it)
$downloaded = "$work\ipsw\iPhone10,3_16.7.16_20H392_Restore.ipsw"
if (-not $KeepIpsw -and (Test-Path $downloaded) -and (Test-Path $ready)) {
    Remove-Item $downloaded
    Write-Host ('Removed the downloaded IPSW ({0:N1} GB); -KeepIpsw keeps it' -f $space.Ipsw)
}

Step '6/6 Shortcut'
if (-not $NoShortcut) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\ASoftware iOS.lnk")
    $link.TargetPath = "$Dir\Start-iOS.cmd"
    $link.WorkingDirectory = $Dir
    $link.IconLocation = "$Dir\assets\logo.ico,0"
    $link.Description = 'ASoftware iOS: iOS 16 in a window'
    $link.Save()
    Write-Host 'Desktop shortcut: ASoftware iOS'
}
Write-Host ''
Write-Host 'ASoftware iOS is installed. Start it from the desktop shortcut or Start-iOS.cmd.' -ForegroundColor Green

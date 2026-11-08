# ASoftware iOS installer: everything to run iOS 16 on this PC, in one folder, with no
# admin rights, WSL or Mac:
#   1. the app (launcher, tools, kernel, helper VM, ios26\) and our QEMU build
#   2. Python (python.org's embeddable package) for the launcher's tools
#   3. the iPhone X iOS 16.7.16 IPSW, from Apple (6.2 GB; -Ipsw uses one you have), and its
#      device tree (tools/ipsw-devicetree.py) for the launcher's ADT
#   4. the iOS disk, built from the IPSW by the helper VM (Build-iOSDisk.ps1)
#   5. iOS's first start, which sets up its app database once (20-30 min)
#   6. a desktop shortcut
# Each step is skipped when its result is there already, so running it again resumes.
# Setup-ASoftware.ps1 (Install-ASoftware.cmd) runs this for iOS 16, and its step 1 alone
# (-AppOnly) before iOS 26, which shares the work folder and its QEMU.
#   powershell -ExecutionPolicy Bypass -File installer\Install-ASoftware.ps1 [-Dir D:\ASoftware] [-Ipsw X.ipsw]
#     -List     the steps and which are done      -Check   what this PC has; changes nothing
#     -DryRun   what each step would do; does nothing
param(
    [string]$Dir = "$env:LOCALAPPDATA\ASoftware iOS",
    [string]$Ipsw = '',
    # our QEMU build with its DLLs (the one iOS 26 runs on too): the release package's qemu\bin,
    # else a folder of one (ios26/scripts/win-build.sh's dist); with neither, the package
    # $QemuRelease names is downloaded
    [string]$QemuDist = $(if (Test-Path "$PSScriptRoot\..\qemu\bin\qemu-system-aarch64.exe") { "$PSScriptRoot\..\qemu\bin" }
                          elseif ($env:ASOFT_WORK -and (Test-Path "$env:ASOFT_WORK\qemu\qemu-system-aarch64.exe")) { "$env:ASOFT_WORK\qemu" }
                          else { '' }),
    [int]$Cpus = 4,
    # keep the downloaded IPSW once the iOS disk is built (6.2 GB; it can be downloaded again)
    [switch]$KeepIpsw,
    [switch]$NoShortcut,
    [switch]$List,
    [switch]$Check,
    [switch]$DryRun,
    # only step 1: the app and our QEMU
    [switch]$AppOnly,
    # keep the downloaded QEMU package in work\downloads, where ios26\Install-iOS26.ps1 takes it
    # from instead of downloading it again (an iOS 26 install in the same work folder)
    [switch]$KeepQemuZip
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
$Dir = [IO.Path]::GetFullPath($Dir).TrimEnd('\')
$work = "$Dir\work"

# The IPSW our kernel and tweaks are made for, as Apple serves it
$ipswUrl = 'https://updates.cdn-apple.com/2025FallFCS/fullrestores/122-77006/1158E502-D76D-4226-AA06-ED5E30CD1111/iPhone10,3,iPhone10,6_16.7.16_20H392_Restore.ipsw'
$ipswSha256 = 'ECE1194F7E233E9109C5790A8D23A4564A10A254E15EC5B09978A343265568FB'
$ipswSize = 6171035648
$pythonUrl = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip'
# Our QEMU as a release package, the one ios26/Install-iOS26.ps1 downloads: qemu-sptm's asoft
# branch (-M virt for iOS 16, -M vresearch for iOS 26) built by ios26/scripts/win-build.sh
$QemuRelease = @{ Version = '2026.11.03'; Url = 'https://github.com/alpersamur3/qemu-sptm/releases/download/asoft-7364c4e/asoft-qemu-2026.11.03.zip'; Sha256 = 'C0D48F95ABEB467D8AFDE898BF2987123C60F19D62CFC8400C446F0569E4D5C2' }

# Disk space in GB as Windows shows them, measured for 20H392: the IPSW, the iOS disk as built
# and after iOS's first start, the room the helper unpacks the IPSW into, the rest, and a saved
# state (the quick boot's, or one Save state makes) in the user disk. Our QEMU is 0.5 of the app's
$space = @{ Ipsw = 5.75; Disk = 11.7; DiskReady = 12.2; Scratch = 7.0; App = 0.7; State = 3.0 }

$deviceTree = "$work\firmware\d22ap.adt"
$base = "$work\root\ios16-base.qcow2"
$ready = "$work\root\ios16-base.ready"
$downloaded = "$work\ipsw\iPhone10,3_16.7.16_20H392_Restore.ipsw"
$qemuDir = "$work\qemu"
$qemuZip = "$work\downloads\asoft-qemu-$($QemuRelease.Version).zip"
$shortcut = "$([Environment]::GetFolderPath('Desktop'))\ASoftware iOS.lnk"
$Steps = @(
    @{ N = 1; Id = 'app'; Title = 'App files' }
    @{ N = 2; Id = 'python'; Title = 'Python' }
    @{ N = 3; Id = 'ipsw'; Title = 'iOS 16.7.16 (iPhone X) from Apple' }
    @{ N = 4; Id = 'disk'; Title = 'The iOS disk' }
    @{ N = 5; Id = 'firststart'; Title = 'First start of iOS (once, 20-30 min)' }
    @{ N = 6; Id = 'shortcut'; Title = 'Shortcut' }
)
function Step-Done([string]$id) {
    switch ($id) {
        'app' { (Test-Path "$Dir\scripts\run-windows.ps1") -and (Test-Path "$qemuDir\qemu-system-aarch64.exe") }
        'python' { Test-Path "$Dir\python\python.exe" }
        'ipsw' { (Test-Path $deviceTree) -and ((Test-Path $base) -or ($Ipsw -and (Test-Path $Ipsw)) -or ((Test-Path $downloaded) -and (Get-Item $downloaded).Length -eq $ipswSize)) }
        'disk' { Test-Path $base }
        'firststart' { Test-Path $ready }
        'shortcut' { $NoShortcut -or (Test-Path $shortcut) }
    }
}

# "== N/6 title" on the screen, and a line in work\install16.log that Setup-ASoftware.ps1 reads
# (which step runs, since when)
function Step([string]$text) {
    Write-Host ''
    Write-Host "== $text" -ForegroundColor Cyan
    if (-not $DryRun -and (Test-Path $work)) {
        Add-Content "$work\install16.log" ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $text) -Encoding ASCII
    }
}
function Show([string]$text) { Write-Host "  > $text" -ForegroundColor DarkGray }

if ($List) {
    Write-Host "iOS 16 install folder: $Dir"
    foreach ($s in $Steps) {
        $state = if (Step-Done $s.Id) { 'done' } else { '-' }
        if ($s.Id -eq 'ipsw' -and $state -eq '-' -and (Test-Path $downloaded)) {
            $state = 'partial ({0:N1} of {1:N1} GB)' -f ((Get-Item $downloaded).Length / 1GB), ($ipswSize / 1GB)
        }
        Write-Host ('  {0} {1,-11} {2,-24} {3}' -f $s.N, $s.Id, $state, $s.Title)
    }
    exit 0
}

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

$drive = $Dir.Substring(0, 2)
$free = (Get-PSDrive $Dir.Substring(0, 1)).Free / 1GB
if ($Check) {
    Step "Check (reads only): $Dir"
    $os = [Environment]::OSVersion.Version
    $ram = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    Write-Host ("  Windows {0}, {1}; {2} logical processors, {3} GB RAM" -f $os, $(if ([Environment]::Is64BitOperatingSystem) { '64-bit' } else { '32-bit' }), [Environment]::ProcessorCount, $ram)
    if (-not [Environment]::Is64BitOperatingSystem -or $os.Build -lt 18362) { Write-Host '  needs Windows 10 1903 (build 18362) or later, 64-bit' -ForegroundColor Yellow }
    if ([Environment]::ProcessorCount -lt 4 -or $ram -lt 16) { Write-Host '  README.md asks for 4 or more cores and 16 GB of RAM (iOS gets 7 GB)' -ForegroundColor Yellow }
    foreach ($t in 'curl.exe', 'tar.exe', 'robocopy.exe') {
        if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { Write-Host "  missing: $t (Windows 10 1803 and later have it)" -ForegroundColor Yellow }
    }
    Write-Host ('  {0:N1} GB free on {1}' -f $free, $drive)
    $qemu = "$qemuDir\qemu-system-aarch64.exe"
    Write-Host "  QEMU: $(if (Test-Path $qemu) { (& $qemu --version | Select-Object -First 1) } else { "not yet ($qemuDir)" })"
    Write-Host "  Python: $(if (Test-Path "$Dir\python\python.exe") { "$Dir\python" } else { 'not yet' })"
    $k = @(Get-ChildItem "$Dir\xnu\out-*\kernel.development.sweet" -ErrorAction SilentlyContinue)
    Write-Host "  kernel: $(if ($k) { $k[-1].FullName } else { 'not yet (step 1 copies it)' })"
    Write-Host "  helper VM: $(if (Test-Path "$Dir\installer\helper\out\Image.gz") { "$Dir\installer\helper\out" } else { 'not yet (step 1 copies it)' })"
    Write-Host "  iOS disk: $(if (Test-Path $ready) { 'ready' } elseif (Test-Path $base) { 'built, first start not done' } else { 'not yet' })"
    exit 0
}

Step "Installing to $Dir$(if ($DryRun) { ' (dry run: nothing is done)' })"
if (-not $DryRun) { New-Item -ItemType Directory -Force $Dir, "$work\root", "$work\ipsw", "$work\ipa" | Out-Null }
# What is still to come here: no IPSW download with -Ipsw or once the disk and the device tree
# are there, nothing to build once the disk is
$needIpsw = -not (Test-Path $base) -or -not (Test-Path $deviceTree)
$needed = $space.App
$parts = @('app {0:N1}' -f $space.App)
if (-not $AppOnly) {
    if ($needIpsw -and -not $Ipsw) { $needed += $space.Ipsw; $parts += 'iOS image {0:N1}' -f $space.Ipsw }
    if (-not (Test-Path $base)) {
        $needed += $space.DiskReady + $space.Scratch
        $parts += ('iOS disk {0:N1}' -f $space.DiskReady), ('room to build it {0:N1}' -f $space.Scratch)
    }
}
$installed = $space.DiskReady + $space.App + $(if ($KeepIpsw -and -not $Ipsw) { $space.Ipsw } else { 0 })
Write-Host ('Disk space on {0} ({1:N1} GB free):' -f $drive, $free)
Write-Host ('  needed while installing: about {0:N1} GB ({1})' -f $needed, ($parts -join ' + '))
if (-not $AppOnly) {
    Write-Host ('  once installed:          about {0:N0} GB, plus what iOS stores as you use it' -f $installed)
    Write-Host ('                           and {0:N0} GB per saved state (quick boot keeps one while iOS is closed)' -f $space.State)
}
if ($free -lt $needed + 1) {
    $why = '{0:N1} GB free on {1}, about {2:N0} GB needed: free some space or use -Dir on another drive' -f $free, $drive, ($needed + 1)
    if (-not $DryRun) { throw $why }
    Write-Host "  (a real run stops here) $why" -ForegroundColor Yellow
}

Step '1/6 App files'
if ($src.Path -ne $Dir) {
    Show "copy Start-iOS.cmd, Start-watchOS.cmd, Install-ASoftware.cmd, LICENSE, README.md, scripts, tools, assets, ios26, watchos, installer, the helper VM and the newest kernel -> $Dir"
    if (-not $DryRun) {
        foreach ($item in 'Start-iOS.cmd', 'Start-watchOS.cmd', 'Install-ASoftware.cmd', 'LICENSE', 'README.md') {
            if (Test-Path "$src\$item") { Copy-Item "$src\$item" $Dir -Force }
        }
        # ios26, watchos: iOS 26's and watchOS's installers and launchers, run from here (Setup-ASoftware.ps1)
        foreach ($folder in 'scripts', 'tools', 'assets', 'ios26', 'watchos') {
            if (Test-Path "$src\$folder") { robocopy "$src\$folder" "$Dir\$folder" /MIR /XD __pycache__ /NFL /NDL /NJH /NJS /NP | Out-Null }
        }
        New-Item -ItemType Directory -Force "$Dir\installer\helper\out", "$Dir\xnu" | Out-Null
        Copy-Item "$src\installer\*.ps1" "$Dir\installer\" -Force
        Copy-Item "$src\installer\helper\out\Image.gz", "$src\installer\helper\out\initrd.gz" "$Dir\installer\helper\out\" -Force
        # the newest kernel build
        $kernel = Get-ChildItem "$src\xnu\out-*\kernel.development.sweet" | Sort-Object { $_.Directory.Name } | Select-Object -Last 1
        if (-not $kernel) { throw "no kernel in $src\xnu\out-*" }
        robocopy $kernel.Directory.FullName "$Dir\xnu\$($kernel.Directory.Name)" kernel.development.sweet /NFL /NDL /NJH /NJS /NP | Out-Null
    }
}
# work\qemu, as Install-iOS26.ps1 has it (an older install's QEMU 11.1.2 in work\qemu\v11.1.2-asoft
# stays where it is; the launcher takes this one first)
if (-not (Test-Path "$qemuDir\qemu-system-aarch64.exe")) {
    if ($QemuDist) {
        if (-not (Test-Path "$QemuDist\qemu-system-aarch64.exe")) { throw "$QemuDist has no qemu-system-aarch64.exe" }
        Show "robocopy $QemuDist $qemuDir"
        if (-not $DryRun) { robocopy $QemuDist $qemuDir /E /XD backup-* v11.1.2-asoft /NFL /NDL /NJH /NJS /NP | Out-Null }
    } else {
        # into work\downloads under the name Install-iOS26.ps1 looks for, so iOS 26 in the same work
        # folder unpacks it instead of downloading it again (-KeepQemuZip keeps it for that)
        Show "download $($QemuRelease.Url) -> $qemuZip, check its SHA-256, unpack it into $qemuDir"
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force (Split-Path $qemuZip) | Out-Null
            if (-not (Test-Path $qemuZip) -or (Get-FileHash $qemuZip -Algorithm SHA256).Hash -ne $QemuRelease.Sha256) {
                Write-Host "Downloading our QEMU ($($QemuRelease.Url))"
                Invoke-Tool curl.exe -fL --retry 3 -o $qemuZip $QemuRelease.Url
                if ($LASTEXITCODE) { throw "could not download $($QemuRelease.Url)" }
                if ((Get-FileHash $qemuZip -Algorithm SHA256).Hash -ne $QemuRelease.Sha256) { Remove-Item $qemuZip; throw "$($QemuRelease.Url) is not our QEMU package (SHA-256 differs)" }
            }
            Expand-Archive $qemuZip $qemuDir -Force
            # Install-iOS26.ps1's qemu step leaves the same package where it is
            Set-Content "$qemuDir\package.sha256" $QemuRelease.Sha256 -Encoding ASCII
            if (-not $KeepQemuZip) { Remove-Item $qemuZip }
        }
    }
}
$qemu = "$qemuDir\qemu-system-aarch64.exe"
if (-not $DryRun) { Write-Host (& $qemu --version | Select-Object -First 1) }
if ($AppOnly) { exit 0 }

Step '2/6 Python'
if (-not (Test-Path "$Dir\python\python.exe")) {
    Show "download $pythonUrl, unpack it into $Dir\python"
    if (-not $DryRun) {
        $zip = "$env:TEMP\asoft-python.zip"
        Invoke-Tool curl.exe -fL --retry 3 -o $zip $pythonUrl
        if ($LASTEXITCODE) { throw "could not download $pythonUrl" }
        Expand-Archive $zip "$Dir\python" -Force
        Remove-Item $zip
    }
}
if (-not $DryRun) { & "$Dir\python\python.exe" --version }

Step '3/6 iOS 16.7.16 (iPhone X) from Apple'
if ($needIpsw) {
    if (-not $Ipsw) {
        $Ipsw = $downloaded
        if (-not (Test-Path $Ipsw) -or (Get-Item $Ipsw).Length -ne $ipswSize) {
            Show "download $([Math]::Round($ipswSize / 1GB, 1)) GB: $ipswUrl -> $Ipsw (resumable)"
            if (-not $DryRun) {
                Write-Host "Downloading 6.2 GB from Apple; if it stops, run the installer again to resume."
                Invoke-Tool curl.exe -fL --retry 5 -C - -o $Ipsw $ipswUrl
                if ($LASTEXITCODE) { throw "the download stopped (curl $LASTEXITCODE); run the installer again to resume" }
            }
        }
    }
    Show "check its SHA-256 ($ipswSha256)"
    if (-not $DryRun) {
        Write-Host 'Checking the IPSW...'
        if ((Get-FileHash $Ipsw -Algorithm SHA256).Hash -ne $ipswSha256) {
            throw "$Ipsw is not Apple's iOS 16.7.16 IPSW for the iPhone X (SHA-256 differs)"
        }
    }
}
# The iPhone X's device tree: the launcher's ADT takes its /product from it (screen, artwork,
# model names), without which SpringBoard cannot draw
if (-not (Test-Path $deviceTree)) {
    Show "python tools\ipsw-devicetree.py $Ipsw $deviceTree"
    if (-not $DryRun) {
        Invoke-Tool "$Dir\python\python.exe" "$Dir\tools\ipsw-devicetree.py" $Ipsw $deviceTree
        if ($LASTEXITCODE) { throw "could not take the device tree from $Ipsw" }
    }
}

Step '4/6 The iOS disk'
$building = "$work\root\ios16-base.building.qcow2"
if (-not (Test-Path $base)) {
    Show "installer\Build-iOSDisk.ps1 -Ipsw $Ipsw -Out $building, then rename it to $base (the helper VM in QEMU, about 22 min)"
    if (-not $DryRun) {
        Remove-Item "$building*" -ErrorAction SilentlyContinue
        & "$Dir\installer\Build-iOSDisk.ps1" -Ipsw $Ipsw -Out $building -Qemu $qemu -Helper "$Dir\installer\helper\out"
        Move-Item $building $base
    }
}

Step '5/6 First start of iOS (once, 20-30 min)'
if (-not (Test-Path $ready) -and $DryRun) {
    Show "scripts\run-windows.ps1 -Work $work -Disk $base -Keep -Display none (headless, QMP 4447), until SpringBoard is up; then power it down"
} elseif (-not (Test-Path $ready)) {
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
if (-not $KeepIpsw -and (Test-Path $downloaded) -and (Test-Path $ready)) {
    Show "del $downloaded (-KeepIpsw keeps it)"
    if (-not $DryRun) {
        Remove-Item $downloaded
        Write-Host ('Removed the downloaded IPSW ({0:N1} GB); -KeepIpsw keeps it' -f $space.Ipsw)
    }
}

Step '6/6 Shortcut'
if (-not $NoShortcut) {
    Show "desktop shortcut $shortcut -> $Dir\Start-iOS.cmd"
    if (-not $DryRun) {
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($shortcut)
        $link.TargetPath = "$Dir\Start-iOS.cmd"
        $link.WorkingDirectory = $Dir
        $link.IconLocation = "$Dir\assets\logo.ico,0"
        $link.Description = 'ASoftware iOS: iOS 16 in a window'
        $link.Save()
        Write-Host 'Desktop shortcut: ASoftware iOS'
    }
}
Write-Host ''
if ($DryRun) { Write-Host 'Dry run: nothing was done.' -ForegroundColor Cyan; exit 0 }
Write-Host 'ASoftware iOS is installed. Start it from the desktop shortcut or Start-iOS.cmd.' -ForegroundColor Green

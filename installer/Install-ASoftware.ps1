# ASoftware iOS installer: everything to run iOS 16 on this PC, in one folder, with no
# admin rights, WSL or Mac:
#   1. the app (launcher, tools, kernel, helper VM) and our QEMU build
#   2. Python (python.org's embeddable package) for the launcher's tools
#   3. the iPhone X iOS 16.7.16 IPSW, from Apple (6.2 GB; -Ipsw uses one you have)
#   4. the iOS disk, built from the IPSW by the helper VM (Build-iOSDisk.ps1)
#   5. iOS's first start, which sets up its app database once (20-30 min)
#   6. a desktop shortcut
# Each step is skipped when its result is there already, so running it again resumes.
#   powershell -ExecutionPolicy Bypass -File installer\Install-ASoftware.ps1 [-Dir D:\ASoftware] [-Ipsw X.ipsw]
param(
    [string]$Dir = "$env:LOCALAPPDATA\ASoftware iOS",
    [string]$Ipsw = '',
    # our QEMU build with its DLLs (qemu/build-windows.sh's dist, or the qemu-win workflow artifact)
    [string]$QemuDist = $(if ($env:ASOFT_WORK) { "$env:ASOFT_WORK\qemu\v11.1.2-asoft" } else { '' }),
    [int]$Cpus = 4,
    [switch]$NoShortcut
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
$src = Resolve-Path "$PSScriptRoot\.."
$work = "$Dir\work"

# The IPSW our kernel and tweaks are made for, as Apple serves it
$ipswUrl = 'https://updates.cdn-apple.com/2025FallFCS/fullrestores/122-77006/1158E502-D76D-4226-AA06-ED5E30CD1111/iPhone10,3,iPhone10,6_16.7.16_20H392_Restore.ipsw'
$ipswSha256 = 'ECE1194F7E233E9109C5790A8D23A4564A10A254E15EC5B09978A343265568FB'
$ipswSize = 6171035648
$pythonUrl = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip'

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
$free = (Get-PSDrive ($Dir.Substring(0, 1))).Free
if ($free -lt 25GB -and -not (Test-Path "$work\root\ios16-base.qcow2")) {
    throw ("{0:N0} GB free on {1}: the IPSW, the iOS disk and room to build it need about 25 GB" -f ($free / 1GB), $Dir.Substring(0, 2))
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
    curl.exe -fL --retry 3 -o $zip $pythonUrl
    if ($LASTEXITCODE) { throw "could not download $pythonUrl" }
    Expand-Archive $zip "$Dir\python" -Force
    Remove-Item $zip
}
& "$Dir\python\python.exe" --version

Step '3/6 iOS 16.7.16 (iPhone X) from Apple'
if (-not $Ipsw) {
    $Ipsw = "$work\ipsw\iPhone10,3_16.7.16_20H392_Restore.ipsw"
    if (-not (Test-Path $Ipsw) -or (Get-Item $Ipsw).Length -ne $ipswSize) {
        Write-Host "Downloading 6.2 GB from Apple; if it stops, run the installer again to resume."
        curl.exe -fL --retry 5 -C - -o $Ipsw $ipswUrl
        if ($LASTEXITCODE) { throw "the download stopped (curl $LASTEXITCODE); run the installer again to resume" }
    }
}
if (-not (Test-Path "$work\root\ios16-base.qcow2")) {
    Write-Host 'Checking the IPSW...'
    if ((Get-FileHash $Ipsw -Algorithm SHA256).Hash -ne $ipswSha256) {
        throw "$Ipsw is not Apple's iOS 16.7.16 IPSW for the iPhone X (SHA-256 differs)"
    }
}

Step '4/6 The iOS disk'
$base = "$work\root\ios16-base.qcow2"
$building = "$work\root\ios16-base.building.qcow2"
if (-not (Test-Path $base)) {
    Remove-Item "$building*" -ErrorAction SilentlyContinue
    & "$Dir\installer\Build-iOSDisk.ps1" -Ipsw $Ipsw -Out $building -Qemu $qemu -Helper "$Dir\installer\helper\out" -Cpus $Cpus
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

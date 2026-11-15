# Build the Windows release package: what Install-ASoftware.ps1 installs from, in one zip.
#   powershell -ExecutionPolicy Bypass -File installer\Make-Release.ps1 -Version 0.1.0 [-QemuDist DIR]
# The repository's tracked files (git archive: no research\ or other local files; ios26\ for the iOS 26
# installer Setup-ASoftware.ps1 runs), the helper VM
# (installer/helper/build-*.sh), the newest kernel build (xnu\out-*) and our QEMU build, the one
# iOS 26 runs on too (ios26/scripts/win-build.sh's dist), and ASoftware.exe, the launcher
# (launcher/Build-Launcher.ps1: needs the .NET SDK here). Nothing of Apple's: the installer
# downloads iOS from Apple.
param(
    [Parameter(Mandatory = $true)] [string]$Version,
    [string]$QemuDist = 'C:\asoft-build\ios26\dist-win',
    [string]$Out = "$PSScriptRoot\..\release",
    # a package whose QEMU lacks visionOS's options, made on purpose (its visionOS installs need -VisionQemu)
    [switch]$NoVision,
    # a package whose QEMU has no TV window (usb-consumer tv-remote, qemu-sptm asoft-tv), made on purpose: tvOS then
    # starts in the plain window (Install-tvOS.ps1 asks for the TV window but does not need it)
    [switch]$NoTv,
    # a package without tvOS, made on purpose: no tvos\, no Start-tvOS.cmd, no tvOS entry in
    # asoft-setup.json, no tvOS paragraph in README.md or line in SOURCES.md, and no tv-remote probe of the QEMU (that
    # probe exists only for tvOS). The launcher and Setup-ASoftware.ps1 then see no tvos\Install-tvOS.ps1 and hide tvOS
    [switch]$NoTvOS
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..").Path
$name = "ASoftware-iOS-$Version"
$stage = Join-Path $Out $name

if (-not (Test-Path "$QemuDist\qemu-system-aarch64.exe")) { throw "no QEMU build in $QemuDist" }
# visionOS runs on the same QEMU: a build with usb-touchscreen's walk-hold-key and -cpu x-tlbi-filter, which
# Install-visionOS.ps1's qemu step checks; a package without them makes a visionOS install ask for -VisionQemu,
# so it is made only with -NoVision (checked before anything is built)
# A QEMU's output to a probe, stdout and stderr, as Setup-ASoftware.ps1's Qemu-Probe (Windows PowerShell 5.1
# turns a native tool's stderr into errors; a probe that does not end is stopped by its PID)
function Qemu-Probe([string]$exe, [string[]]$argv) {
    $psi = New-Object Diagnostics.ProcessStartInfo $exe
    $psi.Arguments = $argv -join ' '
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $err = $p.StandardError.ReadToEndAsync(); $o = $p.StandardOutput.ReadToEndAsync()
    if (-not $p.WaitForExit(20000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; return '' }
    $o.Result + "`n" + $err.Result
}
$lacks = @()
if ((Qemu-Probe "$QemuDist\qemu-system-aarch64.exe" @('-device', 'usb-touchscreen,help')) -cnotmatch '\bwalk-hold-key=') { $lacks += 'usb-touchscreen walk-hold-key' }
# (a machine-less start whose last, unknown CPU option ends it at once: a QEMU without x-tlbi-filter names that one instead)
$cpu = Qemu-Probe "$QemuDist\qemu-system-aarch64.exe" @('-M', 'none', '-cpu', 'max,x-tlbi-filter=on,x-asoft-probe=on', '-display', 'none', '-S', '-nodefaults')
if ($cpu -cnotmatch 'x-asoft-probe' -or $cpu -cmatch "x-tlbi-filter' not found") { $lacks += '-cpu x-tlbi-filter' }
if ($lacks) {
    $why = "$QemuDist's QEMU has no $($lacks -join ' and ') (visionOS's options): visionOS installs from this package would need -VisionQemu"
    if (-not $NoVision) { throw "$why. Give a build that has them with -QemuDist (qemu-sptm asoft-release, win-build.sh's dist), or -NoVision to make such a package on purpose" }
    Write-Warning "$why (-NoVision)"
}
# tvOS's window (a drawn TV with its Siri Remote): usb-consumer's tv-remote option, from the asoft-tv commits of
# qemu-sptm (usb-consumer tv-remote, gtk TV window); the one QEMU runs every guest, so it is the package's QEMU
if (-not $NoTvOS -and (Qemu-Probe "$QemuDist\qemu-system-aarch64.exe" @('-device', 'usb-consumer,help')) -cnotmatch '\btv-remote=') {
    $whyTv = "$QemuDist's QEMU has no usb-consumer tv-remote (the TV window of qemu-sptm asoft-tv): tvOS would start in the plain window"
    if (-not $NoTv) { throw "$whyTv. Give a build that has it with -QemuDist (D:\asoft-vision\dist-tv), or -NoTv to make such a package on purpose" }
    Write-Warning "$whyTv (-NoTv)"
}

if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null
if (git -C $repo status --porcelain) { throw 'commit first: the package takes the committed files' }

# Windows's own tar (bsdtar: it also writes the zip below), by its full path: started from Git Bash, "tar" is
# MSYS's GNU tar, which reads C:\... as a host named C, unpacks nothing and makes no zip
$tar = Join-Path $env:SystemRoot 'System32\tar.exe'
if (-not (Test-Path $tar)) { throw "no $tar (Windows 10 1803 or later has it)" }

$pack = @('Start-iOS.cmd', 'Start-watchOS.cmd', 'Start-visionOS.cmd', 'Start-tvOS.cmd', 'Install-ASoftware.cmd', 'Send-ToPhone.cmd', 'LICENSE', 'README.md', 'scripts', 'tools', 'assets', 'installer', 'ios26', 'watchos', 'visionos', 'tvos')
# (-NoTvOS: what exists only for tvOS stays in the repository and out of the package)
if ($NoTvOS) { $pack = @($pack | Where-Object { $_ -cne 'Start-tvOS.cmd' -and $_ -cne 'tvos' }) }
git -C $repo archive --format=tar -o "$Out\src.tar" HEAD @pack
if ($LASTEXITCODE) { throw "git archive failed ($LASTEXITCODE)" }
& $tar -x -f "$Out\src.tar" -C $stage
if ($LASTEXITCODE) { throw "tar could not unpack the repository's files into $stage ($LASTEXITCODE)" }
Remove-Item "$Out\src.tar"
if (-not (Test-Path "$stage\Install-ASoftware.cmd")) { throw "the repository's files did not reach $stage" }
if ($NoTvOS) {
    # asoft-setup.json without its os.tvos entry (the last one of os: the comma before it goes too), README.md without the
    # paragraph between its tvos markers; the launcher and Setup-ASoftware.ps1 hide tvOS by tvos\Install-tvOS.ps1's absence
    $utf8 = New-Object Text.UTF8Encoding $false
    $jsonFile = "$stage\installer\asoft-setup.json"
    $json = [IO.File]::ReadAllText($jsonFile)
    $json2 = [regex]::Replace($json, '(?s),\r?\n    "tvos": \{.*?\r?\n    \}(?=\r?\n  \}\r?\n\})', '')
    if ($json2 -ceq $json) { throw 'asoft-setup.json: no os.tvos entry (last under os) to leave out' }
    try { $null = $json2 | ConvertFrom-Json } catch { throw "asoft-setup.json is not valid without its tvOS entry: $_" }
    [IO.File]::WriteAllText($jsonFile, $json2, $utf8)
    $readmeFile = "$stage\README.md"
    $readme = [IO.File]::ReadAllText($readmeFile)
    $readme2 = [regex]::Replace($readme, '(?s)<!-- tvos:begin[^\r\n]*-->\r?\n.*?<!-- tvos:end -->\r?\n(\r?\n)?', '')
    if ($readme2 -ceq $readme) { throw 'README.md: no tvos:begin/tvos:end markers to leave out' }
    [IO.File]::WriteAllText($readmeFile, $readme2, $utf8)
    if ((Test-Path "$stage\tvos") -or (Test-Path "$stage\Start-tvOS.cmd")) { throw '-NoTvOS: tvos\ or Start-tvOS.cmd reached the package' }
}
# ASoftware.exe, the launcher (install, start, settings), stamped with this version (its update check
# compares it with the releases), in the package's root: Install-ASoftware.ps1 copies it into -Dir
& (Join-Path $repo 'launcher\Build-Launcher.ps1') -Version $Version -Out $stage
if (-not (Test-Path "$stage\ASoftware.exe")) { throw 'the launcher did not build (launcher\Build-Launcher.ps1)' }

$helper = "$repo\installer\helper\out"
New-Item -ItemType Directory -Force "$stage\installer\helper\out" | Out-Null
Copy-Item "$helper\Image.gz", "$helper\initrd.gz" "$stage\installer\helper\out\"
$kernel = Get-ChildItem "$repo\xnu\out-*\kernel.development.sweet" | Sort-Object { $_.Directory.Name } | Select-Object -Last 1
New-Item -ItemType Directory -Force "$stage\xnu\$($kernel.Directory.Name)" | Out-Null
Copy-Item $kernel.FullName "$stage\xnu\$($kernel.Directory.Name)\"
robocopy $QemuDist "$stage\qemu\bin" /MIR /XD backup-* /NFL /NDL /NJH /NJS /NP | Out-Null
# (BUILD.txt's first line is the build's stamp, the commits it was built from; the lines under it are notes)
$qemuBuild = if (Test-Path "$QemuDist\BUILD.txt") { "$(Get-Content "$QemuDist\BUILD.txt" -TotalCount 1)".Trim() } else { '' }
if (-not $qemuBuild) { $qemuBuild = 'see its --version' }

@"
# Where the binaries in this package come from

- ``qemu\bin``: QEMU 11.1 (GPL v2) of https://github.com/alpersamur3/qemu-sptm, branch asoft-release
  ($qemuBuild), with reims-vgpu (https://github.com/alpersamur3/reims-vgpu, branch asoft/release-win) and
  metal2vulkan (https://github.com/alpersamur3/metal2vulkan, branch asoft/release-win) in it, built by
  ios26/scripts/win-build.sh; the DLLs next to it are MSYS2's UCRT64 packages (GTK, GLib, ANGLE,
  libslirp and others, under their own licenses; sources at https://packages.msys2.org).
- ``tvos\``: the tvOS 27.2 installer (a research preview) and its scripts. It carries no Apple binaries: the installer
  downloads Apple's OTA update itself, builds liblzraven (0BSD; fetched from GitHub at a pinned commit by
  tvos\steps\lzraven.sh) in WSL and makes the root on the user's PC.
- ``xnu\$($kernel.Directory.Name)``: Apple's XNU (APSL 2.0) with xnu/patches, built by
  .github/workflows/xnu.yml.
- ``ASoftware.exe``: the launcher, ``launcher\`` of this repository (MIT), C# on .NET Framework 4.8 (WPF),
  built by launcher/Build-Launcher.ps1 with the .NET SDK; it runs the scripts beside it.
- ``installer\helper\out``: Linux 6.12.114 (GPL v2, installer/helper/kernel.config) and an
  initramfs of Ubuntu 24.04 arm64 packages (sources at https://launchpad.net/ubuntu), apfs-fuse
  (GPL v2, https://github.com/sgan81/apfs-fuse) and our scripts and asoftinstalld (MIT).
"@ | ForEach-Object { if ($NoTvOS) { [regex]::Replace($_, '(?ms)^- `tvos\\`:.*?(?=^- `)', '') } else { $_ } } | Set-Content -Encoding UTF8 "$stage\SOURCES.md"

$zip = Join-Path $Out "$name-win64.zip"
if (Test-Path $zip) { Remove-Item $zip }
& $tar -a -c -f $zip -C $Out $name
if ($LASTEXITCODE -or -not (Test-Path $zip)) { throw "tar could not write $zip ($LASTEXITCODE)" }
Copy-Item "$repo\installer\Get-ASoftware.ps1" $Out -Force
$lines = foreach ($f in $zip, "$Out\Get-ASoftware.ps1") {
    '{0}  {1}' -f (Get-FileHash $f -Algorithm SHA256).Hash.ToLower(), (Split-Path $f -Leaf)
}
$lines | Set-Content -Encoding ASCII "$Out\SHA256SUMS.txt"
Get-Item $zip, "$Out\Get-ASoftware.ps1", "$Out\SHA256SUMS.txt" | Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } }

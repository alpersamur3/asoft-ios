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
    [string]$Out = "$PSScriptRoot\..\release"
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..").Path
$name = "ASoftware-iOS-$Version"
$stage = Join-Path $Out $name
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null
if (git -C $repo status --porcelain) { throw 'commit first: the package takes the committed files' }

git -C $repo archive --format=tar -o "$Out\src.tar" HEAD Start-iOS.cmd Start-watchOS.cmd Start-visionOS.cmd Install-ASoftware.cmd Send-ToPhone.cmd LICENSE README.md scripts tools assets installer ios26 watchos visionos
tar -x -f "$Out\src.tar" -C $stage
Remove-Item "$Out\src.tar"
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
if (-not (Test-Path "$QemuDist\qemu-system-aarch64.exe")) { throw "no QEMU build in $QemuDist" }
# (visionOS runs on the same QEMU: a build with usb-touchscreen's walk-hold-key and -cpu x-tlbi-filter, which
# Install-visionOS.ps1's qemu step checks; a package without them makes a visionOS install ask for -VisionQemu)
$ErrorActionPreference = 'Continue'     # (Windows PowerShell 5.1 turns a native tool's stderr into errors)
$probe = @(& "$QemuDist\qemu-system-aarch64.exe" -device 'usb-touchscreen,help' 2>&1 | ForEach-Object { "$_" })
$ErrorActionPreference = 'Stop'
if (-not ($probe | Where-Object { $_ -cmatch '\bwalk-hold-key=' })) { Write-Warning "$QemuDist's QEMU has no usb-touchscreen walk-hold-key: visionOS installs from this package need -VisionQemu" }
robocopy $QemuDist "$stage\qemu\bin" /MIR /XD backup-* /NFL /NDL /NJH /NJS /NP | Out-Null
$qemuBuild = if (Test-Path "$QemuDist\BUILD.txt") { (Get-Content "$QemuDist\BUILD.txt") -join '; ' } else { 'see its --version' }

@"
# Where the binaries in this package come from

- ``qemu\bin``: QEMU 11.1 (GPL v2) of https://github.com/alpersamur3/qemu-sptm, branch asoft-release
  ($qemuBuild), with reims-vgpu (https://github.com/alpersamur3/reims-vgpu, branch asoft/release-win) and
  metal2vulkan (https://github.com/alpersamur3/metal2vulkan, branch asoft/release-win) in it, built by
  ios26/scripts/win-build.sh; the DLLs next to it are MSYS2's UCRT64 packages (GTK, GLib, ANGLE,
  libslirp and others, under their own licenses; sources at https://packages.msys2.org).
- ``xnu\$($kernel.Directory.Name)``: Apple's XNU (APSL 2.0) with xnu/patches, built by
  .github/workflows/xnu.yml.
- ``ASoftware.exe``: the launcher, ``launcher\`` of this repository (MIT), C# on .NET Framework 4.8 (WPF),
  built by launcher/Build-Launcher.ps1 with the .NET SDK; it runs the scripts beside it.
- ``installer\helper\out``: Linux 6.12.114 (GPL v2, installer/helper/kernel.config) and an
  initramfs of Ubuntu 24.04 arm64 packages (sources at https://launchpad.net/ubuntu), apfs-fuse
  (GPL v2, https://github.com/sgan81/apfs-fuse) and our scripts and asoftinstalld (MIT).
"@ | Set-Content -Encoding UTF8 "$stage\SOURCES.md"

$zip = Join-Path $Out "$name-win64.zip"
if (Test-Path $zip) { Remove-Item $zip }
tar -a -c -f $zip -C $Out $name
Copy-Item "$repo\installer\Get-ASoftware.ps1" $Out -Force
$lines = foreach ($f in $zip, "$Out\Get-ASoftware.ps1") {
    '{0}  {1}' -f (Get-FileHash $f -Algorithm SHA256).Hash.ToLower(), (Split-Path $f -Leaf)
}
$lines | Set-Content -Encoding ASCII "$Out\SHA256SUMS.txt"
Get-Item $zip, "$Out\Get-ASoftware.ps1", "$Out\SHA256SUMS.txt" | Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } }

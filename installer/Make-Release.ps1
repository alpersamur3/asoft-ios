# Build the Windows release package: what Install-ASoftware.ps1 installs from, in one zip.
#   powershell -ExecutionPolicy Bypass -File installer\Make-Release.ps1 -Version 0.1.0 [-QemuDist DIR]
# The repository's tracked files (git archive: no research\ or other local files), the helper VM
# (installer/helper/build-*.sh), the newest kernel build (xnu\out-*) and our QEMU build
# (qemu/build-windows.sh). Nothing of Apple's: the installer downloads iOS from Apple.
param(
    [Parameter(Mandatory = $true)] [string]$Version,
    [string]$QemuDist = 'C:\asoft-build\dist',
    [string]$Out = "$PSScriptRoot\..\release"
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..").Path
$name = "ASoftware-iOS-$Version"
$stage = Join-Path $Out $name
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null
if (git -C $repo status --porcelain) { throw 'commit first: the package takes the committed files' }

git -C $repo archive --format=tar -o "$Out\src.tar" HEAD Start-iOS.cmd Install-ASoftware.cmd LICENSE README.md scripts tools assets installer
tar -x -f "$Out\src.tar" -C $stage
Remove-Item "$Out\src.tar"

$helper = "$repo\installer\helper\out"
New-Item -ItemType Directory -Force "$stage\installer\helper\out" | Out-Null
Copy-Item "$helper\Image.gz", "$helper\initrd.gz" "$stage\installer\helper\out\"
$kernel = Get-ChildItem "$repo\xnu\out-*\kernel.development.sweet" | Sort-Object { $_.Directory.Name } | Select-Object -Last 1
New-Item -ItemType Directory -Force "$stage\xnu\$($kernel.Directory.Name)" | Out-Null
Copy-Item $kernel.FullName "$stage\xnu\$($kernel.Directory.Name)\"
if (-not (Test-Path "$QemuDist\qemu-system-aarch64.exe")) { throw "no QEMU build in $QemuDist" }
robocopy $QemuDist "$stage\qemu\bin" /MIR /NFL /NDL /NJH /NJS /NP | Out-Null

@"
# Where the binaries in this package come from

- ``qemu\bin``: QEMU 11.1.2 (GPL v2) with the patches in qemu/patches of
  https://github.com/alpersamur3/asoft-ios at $(git -C $repo rev-parse --short HEAD), built by
  qemu/build-windows.sh; the DLLs next to it are MSYS2's UCRT64 packages (GTK, GLib, SDL2,
  libslirp and others, under their own licenses; sources at https://packages.msys2.org).
- ``xnu\$($kernel.Directory.Name)``: Apple's XNU (APSL 2.0) with xnu/patches, built by
  .github/workflows/xnu.yml.
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

# Package our QEMU build (win-build.sh's dist, iOS 26 and iOS 16) as the release zip Install-iOS26.ps1
# and installer\Install-ASoftware.ps1 take, and print the line for their $QemuRelease.
#
#   powershell -File ios26\installer\Make-QemuPackage.ps1 -Dist C:\asoft26-src\dist -Version 2026.11.01 [-Out D:\] [-Url https://...]
#
# The zip holds the dist's files at its top level, without the backup-* folders win-build.sh keeps.
# Upload it (a qemu-sptm release, asoft-<commit>), then put the printed values into both installers.
param(
    [Parameter(Mandatory)][string]$Dist,
    [Parameter(Mandatory)][string]$Version,
    [string]$Out = '.',
    [string]$Url = ''
)
$ErrorActionPreference = 'Stop'
if ($Version -cnotmatch '^[0-9A-Za-z._-]+$') { throw '-Version: letters, digits, dot, dash and underscore only' }
$root = (Resolve-Path $Dist).Path.TrimEnd('\')
if (-not (Test-Path (Join-Path $root 'qemu-system-aarch64.exe'))) { throw "$root has no qemu-system-aarch64.exe (win-build.sh's dist)" }
foreach ($f in 'qemu-system-aarch64w.exe', 'qemu-img.exe', 'BUILD.txt') {
    if (-not (Test-Path (Join-Path $root $f))) { Write-Host "note: the dist has no $f" -ForegroundColor Yellow }
}
New-Item -ItemType Directory -Force $Out | Out-Null
$zip = Join-Path (Resolve-Path $Out).Path "asoft-qemu-$Version.zip"
if (Test-Path $zip) { throw "$zip is there already" }

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$files = @(Get-ChildItem $root -Recurse -File | Where-Object { $_.FullName.Substring($root.Length + 1) -cnotmatch '^backup-[^\\]*\\' })
$z = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $f.FullName, $rel, [IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $z.Dispose()
}
$sha = (Get-FileHash $zip -Algorithm SHA256).Hash
$size = (Get-Item $zip).Length
Write-Host ("{0}: {1} files, {2:N1} MB" -f $zip, $files.Count, ($size / 1MB))
$u = if ($Url) { $Url } else { "https://<where you publish it>/asoft-qemu-$Version.zip" }
Write-Host 'For Install-iOS26.ps1 and Install-ASoftware.ps1:'
Write-Host ("`$QemuRelease = @{{ Version = '{0}'; Url = '{1}'; Sha256 = '{2}' }}" -f $Version, $u, $sha)

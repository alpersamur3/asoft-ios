# ASoftware iOS, one command: download the newest release and run its installer.
#   powershell -ExecutionPolicy Bypass -c "irm https://github.com/alpersamur3/asoft-ios/releases/latest/download/Get-ASoftware.ps1 | iex"
# Run as a file, its arguments go to the installer: Setup-ASoftware.ps1, which asks for iOS 16, iOS 26
# or both (e.g. -Version both -Dir D:\ASoftware); a package without it, Install-ASoftware.ps1 (iOS 16).
$ErrorActionPreference = 'Stop'
$repo = 'alpersamur3/asoft-ios'
$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing
$package = $release.assets | Where-Object { $_.name -like 'ASoftware-iOS-*-win64.zip' } | Select-Object -First 1
$sums = $release.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1
if (-not $package -or -not $sums) { throw "release $($release.tag_name) has no Windows package" }

Write-Host "ASoftware iOS $($release.tag_name): downloading $($package.name) ($([int]($package.size / 1MB)) MB)"
$tmp = Join-Path $env:TEMP "asoftware-$($release.tag_name)"
New-Item -ItemType Directory -Force $tmp | Out-Null
$zip = Join-Path $tmp $package.name
# curl.exe (in Windows 10 1803 and later) is much faster than Invoke-WebRequest in PowerShell 5.1
& curl.exe -fsSL --retry 3 -o $zip $package.browser_download_url
if ($LASTEXITCODE) { throw "could not download $($package.browser_download_url)" }
$expected = ((Invoke-RestMethod $sums.browser_download_url -UseBasicParsing) -split "`n" |
    Where-Object { $_ -match [regex]::Escape($package.name) }) -replace '\s.*$', ''
if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $expected.Trim().ToUpper()) { throw "$($package.name): SHA-256 differs" }

$app = Join-Path $tmp 'app'
if (Test-Path $app) { Remove-Item -Recurse -Force $app }
Expand-Archive $zip $app
Get-ChildItem $app -Recurse -File | Unblock-File       # downloaded files: no "from the internet" prompts
$installer = Get-ChildItem $app -Recurse -Filter Setup-ASoftware.ps1 | Select-Object -First 1
if (-not $installer) { $installer = Get-ChildItem $app -Recurse -Filter Install-ASoftware.ps1 | Select-Object -First 1 }
& powershell -NoProfile -ExecutionPolicy Bypass -File $installer.FullName @args
# 3010: WSL was installed and Windows must restart; the install goes on when this runs again
if ($LASTEXITCODE -eq 3010) { Write-Host 'Restart Windows, then run this again: the install goes on where it stopped.'; return }
if ($LASTEXITCODE) { throw "the installer stopped; run this again to resume" }
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue    # all of it is installed now

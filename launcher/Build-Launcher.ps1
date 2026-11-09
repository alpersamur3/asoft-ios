# Builds ASoftware.exe (the Windows launcher: launcher\*.cs, WPF on .NET Framework 4.8) into launcher\out.
#   powershell -ExecutionPolicy Bypass -File launcher\Build-Launcher.ps1 [-Version 0.3.0] [-Out DIR]
# Needs the .NET SDK (9 or later; dotnet.exe) and the .NET Framework 4.8 targeting pack (Visual Studio's, or
# the Developer Pack); the exe itself needs nothing but Windows 10 or 11. -Version stamps it (the update
# check compares it with the GitHub releases); without it, it is 0.0.0-dev, a development build.
param(
    [string]$Version = '',
    [string]$Out = "$PSScriptRoot\out"
)
$ErrorActionPreference = 'Stop'
$dotnet = (Get-Command dotnet.exe -ErrorAction SilentlyContinue).Source
if (-not $dotnet) { throw 'no dotnet.exe: install the .NET SDK (https://dotnet.microsoft.com/download)' }
$proj = Join-Path $PSScriptRoot 'ASoftware.csproj'
$obj = Join-Path $PSScriptRoot 'obj'
$bin = Join-Path $PSScriptRoot 'bin'
$props = @('-c', 'Release', '-nologo', '-v', 'minimal', "-p:OutDir=$bin\Release\")
if ($Version) {
    $num = ($Version -replace '^v', '') -replace '[^0-9.].*$', ''
    $props += "-p:Version=$num", "-p:InformationalVersion=$($Version -replace '^v', '')"
} else {
    $props += '-p:Version=0.0.0', '-p:InformationalVersion=0.0.0-dev'
}
# (a clean build: an incremental one keeps the old version stamp)
if (Test-Path $obj) { Remove-Item $obj -Recurse -Force }
$ErrorActionPreference = 'Continue'
& $dotnet build $proj @props
$code = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($code) { throw "dotnet build failed ($code)" }
New-Item -ItemType Directory -Force $Out | Out-Null
# one file: the exe (the .exe.config the SDK writes is not needed: the runtime is the one in Windows)
$to = Join-Path $Out 'ASoftware.exe'
# (one that runs can be renamed, not written over: it goes on from the old name, and the next build drops that)
Remove-Item "$to.old" -Force -ErrorAction SilentlyContinue
if (Test-Path $to) { Move-Item $to "$to.old" -Force -ErrorAction SilentlyContinue }
Copy-Item "$bin\Release\ASoftware.exe" $to -Force
$f = Get-Item (Join-Path $Out 'ASoftware.exe')
'{0} {1:N0} KB, version {2}' -f $f.FullName, ($f.Length / 1KB), $f.VersionInfo.ProductVersion

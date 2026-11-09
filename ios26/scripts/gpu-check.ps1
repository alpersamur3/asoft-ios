# Does this PC's GPU driver take iOS 26's GPU path? gpu-check.cs says what it tries.
#   powershell -ExecutionPolicy Bypass -File ios26\scripts\gpu-check.ps1
# Lines of gpu|used or other|name|kind|vendor|Vulkan|driver|alignment|ok or why, then result|ok,
# result|fail or result|none|why. Exit 0, 1 or 3 as result says (anything else: the check itself failed).
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition (Get-Content -Raw (Join-Path $PSScriptRoot 'gpu-check.cs'))
exit [GpuCheck]::Run()

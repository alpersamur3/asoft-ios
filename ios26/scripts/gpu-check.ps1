# Does this PC's GPU driver take iOS 26's GPU path? gpu-check.cs says what it tries.
#   powershell -ExecutionPolicy Bypass -File ios26\scripts\gpu-check.ps1 [-Lang tr]
# Lines of gpu|used or other|name|kind|vendor|Vulkan|driver|alignment|ok or why, then (only when the driver of the
# GPU the guest will use is old) warn|code|vendor|detail|sentence, then result|ok, result|fail or result|none|why.
# -Lang picks the language of the sentence. Exit 0, 1 or 3 as result says (anything else: the check itself failed).
param([ValidateSet('en', 'tr')][string]$Lang = 'en')
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition (Get-Content -Raw (Join-Path $PSScriptRoot 'gpu-check.cs'))
[GpuCheck]::Turkish = ($Lang -ceq 'tr')
exit [GpuCheck]::Run()

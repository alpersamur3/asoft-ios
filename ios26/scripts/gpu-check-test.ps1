# Tests of gpu-check.cs's old-driver rule (Warn / WarnText) with made-up inputs: no GPU, no Vulkan, no VM.
#   powershell -ExecutionPolicy Bypass -File ios26\scripts\gpu-check-test.ps1
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition (Get-Content -Raw (Join-Path $PSScriptRoot 'gpu-check.cs'))
$now = [DateTime]'2026-11-13'
$v12 = (1 -shl 22) -bor (2 -shl 12)       # Vulkan 1.2.0
$v13 = (1 -shl 22) -bor (3 -shl 12) -bor 280
$v11 = (1 -shl 22) -bor (1 -shl 12) -bor 90
$pass = 0; $fail = 0
function Check([string]$name, $got, $want) {
    $g = if ($got) { $got -join '/' } else { 'none' }
    if ($g -ceq $want) { $script:pass++ } else { $script:fail++; Write-Host "FAIL $name : got $g, want $want" -ForegroundColor Red }
}
function W($vendor, $api, $ext, $kind, $date) { [GpuCheck]::Warn([uint32]$vendor, [uint32]$api, $ext, $kind, $date, $now) }
$d = { param($s) [Nullable[DateTime]][DateTime]$s }
$null1 = [Nullable[DateTime]]$null

Check 'old NVIDIA (2021-03, Vulkan 1.3)'    (W 0x10DE $v13 $true 'discrete' (& $d '2021-03-10')) 'date/NVIDIA/2021-03'
Check 'current NVIDIA (2026-09)'            (W 0x10DE $v13 $true 'discrete' (& $d '2026-09-02')) 'none'
Check 'old Intel, Vulkan 1.1'               (W 0x8086 $v11 $true 'integrated' (& $d '2026-01-05')) 'api/Intel/1.1'
Check 'old Intel, 1.3 but 2022-05'          (W 0x8086 $v13 $true 'integrated' (& $d '2022-05-20')) 'date/Intel/2022-05'
Check 'missing date, new enough Vulkan'     (W 0x10DE $v13 $true 'discrete' $null1) 'none'
Check 'missing date, Vulkan 1.1'            (W 0x1002 $v11 $true 'discrete' $null1) 'api/AMD/1.1'
Check 'missing extension'                   (W 0x1002 $v13 $false 'discrete' (& $d '2026-10-01')) 'ext/AMD/VK_EXT_external_memory_host'
Check 'software renderer, old date'         (W 0x10005 $v13 $true 'cpu' (& $d '2019-01-01')) 'none'
Check 'software renderer, Vulkan 1.1'       (W 0x10005 $v11 $false 'cpu' $null1) 'none'
Check 'virtual device'                      (W 0x1AF4 $v11 $true 'virtual' (& $d '2019-01-01')) 'none'
Check 'exactly 730 days'                    (W 0x10DE $v12 $true 'discrete' $now.AddDays(-730)) 'none'
Check '731 days'                            (W 0x10DE $v12 $true 'discrete' $now.AddDays(-731)) 'date/NVIDIA/2024-11'
Check 'date in the future'                  (W 0x10DE $v13 $true 'discrete' $now.AddDays(40)) 'none'
Check 'unknown vendor, old'                 (W 0x1234 $v13 $true 'discrete' (& $d '2020-01-01')) 'date//2020-01'
Check 'api beats date'                      (W 0x10DE $v11 $true 'discrete' (& $d '2019-01-01')) 'api/NVIDIA/1.1'

function T([string[]]$w, [bool]$tr) { [GpuCheck]::WarnText($w, $tr) }
function Has([string]$name, [string]$text, [string]$part) {
    if ($text.Contains($part)) { $script:pass++ } else { $script:fail++; Write-Host "FAIL $name : '$text' lacks '$part'" -ForegroundColor Red }
}
$en = T @('date', 'NVIDIA', '2021-03') $false
Has 'EN date text'  $en 'Your NVIDIA GPU driver is from 2021-03'
Has 'EN says what'  $en 'may fail to start or draw wrong'
Has 'EN NVIDIA url' $en 'https://www.nvidia.com/Download/index.aspx'
Has 'EN AMD url'    (T @('api', 'AMD', '1.1') $false) 'amd.com/en/support'
Has 'EN Intel url'  (T @('ext', 'Intel', 'VK_EXT_external_memory_host') $false) 'intel.com/content/www/us/en/download-center'
Has 'EN unknown'    (T @('date', '', '2020-01') $false) 'from your GPU maker''s or PC maker''s site'
$tr = T @('date', 'NVIDIA', '2021-03') $true
Has 'TR date text'  $tr 'NVIDIA GPU s'
Has 'TR dotless i'  $tr 'yanl'
Has 'TR url'        $tr 'nvidia.com/Download/index.aspx adresinden'
Has 'TR unknown'    (T @('api', '', '1.1') $true) 'PC '
foreach ($x in @($en, $tr, (T @('api', 'Intel', '1.1') $false))) {
    if ($x.Contains('|') -or $x.Contains("`n")) { $fail++; Write-Host "FAIL sentence has a pipe or newline: $x" -ForegroundColor Red } else { $pass++ }
}
Write-Host "EN: $en"
Write-Host "TR: $tr"
Write-Host "gpu-check warn tests: $pass ok, $fail failed"
exit ([int]($fail -gt 0))

# Tests of wait-policy.ps1's decision (Step-Wait, Get-SpeedFactor, Get-WaitCeiling) on made-up poll sequences:
# no VM, no guest. A poll is (minute, done, signature); the wait polls every 0.5 min as Wait-Migration does.
#   powershell -ExecutionPolicy Bypass -File ios26\scripts\wait-policy-test.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'wait-policy.ps1')
$pass = 0; $fail = 0
function Check([string]$name, $got, $want) {
    if ("$got" -ceq "$want") { $script:pass++ } else { $script:fail++; Write-Host "FAIL $name : got $got, want $want" -ForegroundColor Red }
}
# Runs a sequence: $sigAt = scriptblock minute -> signature (what the guest shows then), $doneAt = minute it is done
# (or $null). Returns "verdict@minute".
function Run-Sequence([scriptblock]$sigAt, $doneAt, [double]$stall, [double]$ceiling) {
    $t = New-WaitTracker
    for ($m = 0.0; $m -le 1000; $m += 0.5) {
        $done = ($null -ne $doneAt -and $m -ge $doneAt)
        $v = Step-Wait $t $m $done (& $sigAt $m) $stall $ceiling
        if ($v -cne 'wait') { return "$v@$m" }
    }
    'never ended'
}
$stall = 30
# the wallpaper step on our PC: 33 min, signature changing all the time (frames, CPU minutes)
$alive = { param($m) "f$([int]($m * 3))|c$([int]$m)" }
Check 'healthy 33-minute run' (Run-Sequence $alive 33 $stall 300) 'done@33'
# a slow PC: done at 140 min, the boot working throughout (3x the estimate would be 99, the ceiling 300)
Check 'slow run, done at 140' (Run-Sequence $alive 140 $stall (Get-WaitCeiling 300 99)) 'done@140'
# the old limit (90) must not end it
Check 'slow run passes minute 90' (Run-Sequence $alive 95 $stall 300) 'done@95'
# silent from minute 50: signature frozen
$silent50 = { param($m) if ($m -lt 50) { "f$([int]($m * 3))|c$([int]$m)" } else { 'f150|c49' } }
Check 'silent from minute 50 (last change at 50)' (Run-Sequence $silent50 $null $stall 300) 'stalled@80'
# a boot that works for ever never done: ceiling
Check 'alive but never done' (Run-Sequence $alive $null $stall 300) 'ceiling@300'
# a slow boot that is silent for 29 minutes, then goes on: not given up
$gap = { param($m) if ($m -lt 40) { "c$([int]$m)" } elseif ($m -lt 69) { 'c39' } else { "c$([int]$m)" } }
Check 'silent 29 min then moves on' (Run-Sequence $gap 100 $stall 300) 'done@100'
# done on the same poll as the ceiling or the stall wins
Check 'done at the ceiling' (Run-Sequence $alive 300 $stall 300) 'done@300'
$frozen = { param($m) 'same' }
Check 'frozen from the start' (Run-Sequence $frozen $null $stall 300) 'stalled@30'
Check 'frozen from the start, done at 29' (Run-Sequence $frozen 29 $stall 300) 'done@29'
# the ceiling is checked before the stall when both are due
Check 'ceiling vs stall' (Run-Sequence $frozen $null 500 20) 'ceiling@20'

Check 'factor: none measured' (Get-SpeedFactor 0 106) '1'
Check 'factor: faster PC is 1' (Get-SpeedFactor 53 106) '1'
Check 'factor: 3x' (Get-SpeedFactor 318 106) '3'
Check 'factor: capped at 12' (Get-SpeedFactor 5000 106) '12'
Check 'factor: no reference' (Get-SpeedFactor 300 0) '1'
Check 'ceiling floor' (Get-WaitCeiling 300 33) '300'
Check 'ceiling 3x estimate' (Get-WaitCeiling 300 150) '450'

# the best-effort wait (the data ark): found wins, gives up at the limit
Check 'best effort: found at 3' (Step-BestEffort 3 $true 15) 'found'
Check 'best effort: waiting at 14.5' (Step-BestEffort 14.5 $false 15) 'wait'
Check 'best effort: gives up at 15' (Step-BestEffort 15 $false 15) 'giveup'
Check 'best effort: found at the limit' (Step-BestEffort 15 $true 15) 'found'

# the guest signature with no files and no process: stable
$g = @{ Dir = (Join-Path $env:TEMP 'wait-policy-test-nodir'); Proc = $null }
Check 'signature of nothing' (Get-GuestSignature $g) 'f0|l0|c0|'
$tmp = Join-Path $env:TEMP ('wait-policy-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp | Out-Null
try {
    Set-Content (Join-Path $tmp 'stderr.log') "x`nframe 3 shown`nframe 12 shown`nframe 7 shown" -Encoding ASCII
    $s1 = Get-GuestSignature @{ Dir = $tmp; Proc = $null }
    Check 'signature has the highest frame' ($s1 -cmatch '^f12\|l\d+\|c0\|$') 'True'
    Add-Content (Join-Path $tmp 'stderr.log') 'frame 13 shown' -Encoding ASCII
    Check 'signature changes with a new frame' ((Get-GuestSignature @{ Dir = $tmp; Proc = $null }) -cne $s1) 'True'
} finally { Remove-Item $tmp -Recurse -Force }

Write-Host "$pass passed, $fail failed"
exit ([int]($fail -gt 0))

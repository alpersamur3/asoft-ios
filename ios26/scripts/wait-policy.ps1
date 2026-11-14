# When a boot the installers wait on is slow, not stuck: the decision of Install-iOS26.ps1's long boots
# (the wallpaper step's DataMigration, the first boot, the wait for the UI) and Install-visionOS.ps1's first boot.
# Dot-sourced; no VM, no I/O here (wait-policy-test.ps1 runs it on made-up poll sequences).
#
# A wait polls something that says "done". While it is not done, each poll also gives a signature of what the
# guest is doing (frames shown, QEMU's CPU minutes, what the poll printed). It waits while the signature changes
# and gives up when it has not changed for $stall minutes, or after $ceiling minutes in all.

function New-WaitTracker { @{ Sig = $null; LastChange = 0.0 } }

# One poll at minute $min: 'done', 'wait', 'stalled' (nothing changed for $stall minutes) or 'ceiling'.
# A poll that finds it done wins over the limits.
function Step-Wait($t, [double]$min, [bool]$done, [string]$sig, [double]$stall, [double]$ceiling) {
    if ($done) { return 'done' }
    if ($t.Sig -cne $sig) { $t.Sig = $sig; $t.LastChange = $min }
    if ($min -ge $ceiling) { return 'ceiling' }
    if (($min - $t.LastChange) -ge $stall) { return 'stalled' }
    'wait'
}

# How much slower this PC is than ours: an earlier boot of the same install (seconds) over the reference's.
# Never below 1 (a faster PC waits as long as ours), never above 12 (a wrong measurement must not
# stretch every limit), 1 when there is none.
function Get-SpeedFactor([double]$measuredSec, [double]$refSec) {
    if ($measuredSec -le 0 -or $refSec -le 0) { return 1.0 }
    [Math]::Min(12.0, [Math]::Max(1.0, $measuredSec / $refSec))
}

# The hard ceiling in minutes: a fixed floor, or 3 times the estimate when the PC is slow
function Get-WaitCeiling([double]$floorMin, [double]$estimateMin) { [Math]::Max($floorMin, 3 * $estimateMin) }

# What the guest is doing, as one string that changes when it does: the highest "frame N shown" and the size of
# QEMU's stderr.log (the UI drawing), QEMU's CPU time in whole minutes (a guest that works), and $extra (what the
# poll itself printed). $g is Install-*.ps1's guest (.Dir the run folder, .Proc QEMU's process).
function Get-GuestSignature($g, [string]$extra = '') {
    $frame = 0; $len = 0
    $log = Join-Path $g.Dir 'stderr.log'
    if (Test-Path -LiteralPath $log) {
        $len = (Get-Item -LiteralPath $log).Length
        $t = Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue
        if ($t) { foreach ($m in [regex]::Matches($t, 'frame (\d+) shown')) { $frame = [Math]::Max($frame, [int64]$m.Groups[1].Value) } }
    }
    $cpu = 0
    if ($g.Proc) { try { $g.Proc.Refresh(); $cpu = [int][Math]::Floor($g.Proc.TotalProcessorTime.TotalMinutes) } catch { } }
    "f$frame|l$len|c$cpu|$extra"
}

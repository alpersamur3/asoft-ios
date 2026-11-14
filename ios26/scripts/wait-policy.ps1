# When a boot the installers wait on is slow, not stuck: the decision of Install-iOS26.ps1's long boots
# (the wallpaper step's DataMigration, the first boot, the wait for the UI) and Install-visionOS.ps1's first boot.
# Dot-sourced; no VM, no I/O here (wait-policy-test.ps1 runs it on made-up poll sequences).
#
# A wait polls something that says "done". While it is not done, each poll also gives a signature of what the
# guest is doing (frames shown, QEMU's CPU minutes, what the poll printed). It waits while the signature changes
# and gives up when it has not changed for $stall minutes, or after $ceiling minutes in all.

function New-WaitTracker { @{ Sig = $null; LastChange = 0.0; LogPath = $null; LogOff = 0L; LogCarry = '' } }

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

# A wait that is only a courtesy (the data ark after the first boot's required files): 'found', 'wait', or
# 'giveup' once $limit minutes have passed since it began. Found wins over the limit.
function Step-BestEffort([double]$minSinceStart, [bool]$found, [double]$limit) {
    if ($found) { return 'found' }
    if ($minSinceStart -ge $limit) { return 'giveup' }
    'wait'
}

# --- A lost GPU: the boot goes on but nothing is drawn any more, so the wait can never end ----------------------

# The first line of $log that shows the host GPU's Vulkan device was lost, else $null. Ordinal and case-sensitive
# (Turkish Windows too).
function Find-GpuLoss([string]$log) {
    if (-not $log) { return $null }
    $marks = @('the Vulkan device was lost', 'metal2vulkan: the device was lost', 'command buffer failed: DeviceLost', 'frame failed on the GPU: GPU error')
    foreach ($line in $log.Split("`n")) {
        foreach ($mark in $marks) {
            if ($line.IndexOf($mark, [StringComparison]::Ordinal) -ge 0) { return $line.Trim() }
        }
    }
    $null
}

# The text appended to the file $path since the last call with this tracker $t (the offset is kept in it), only
# whole lines: a line that ends the read without its newline is kept and comes first in the next call. A file that
# shrank (or another path) starts again at 0. One call reads $maxBytes at most; the rest comes in the next calls.
function Read-LogAppended($t, [string]$path, [int]$maxBytes = 4194304) {
    if ($t.LogPath -cne $path) { $t.LogPath = $path; $t.LogOff = 0L; $t.LogCarry = '' }
    $fs = $null
    try {
        $fs = New-Object System.IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $len = $fs.Length
        if ($len -lt $t.LogOff) { $t.LogOff = 0L; $t.LogCarry = '' }
        if ($len -eq $t.LogOff) { return '' }
        $n = [int][Math]::Min([int64]$maxBytes, $len - $t.LogOff)
        $buf = New-Object byte[] $n
        $null = $fs.Seek($t.LogOff, [IO.SeekOrigin]::Begin)
        $got = 0
        while ($got -lt $n) { $r = $fs.Read($buf, $got, $n - $got); if ($r -le 0) { break }; $got += $r }
        $t.LogOff += $got
        $all = $t.LogCarry + [Text.Encoding]::UTF8.GetString($buf, 0, $got)
        $cut = $all.LastIndexOf("`n")
        if ($cut -lt 0) { $t.LogCarry = if ($all.Length -gt 65536) { '' } else { $all }; return '' }
        $t.LogCarry = $all.Substring($cut + 1)
        $all.Substring(0, $cut + 1)
    } catch { '' }
    finally { if ($fs) { $fs.Dispose() } }
}

# One round of a wait: the first lost-GPU line among what QEMU's stderr.log in the guest's run folder gained since
# the last round, else $null. $g is Install-*.ps1's guest (.Dir the run folder).
function Test-GpuLost($t, $g) {
    Find-GpuLoss (Read-LogAppended $t (Join-Path $g.Dir 'stderr.log'))
}

# What the installer says when the GPU was lost: $line is the log line, $gpu the GPU's name when known.
function New-GpuLossMessage([string]$line, [string]$gpu = '') {
    $m = "The graphics driver lost the Vulkan device during this boot, so iOS cannot draw any more and this step cannot finish."
    if ($gpu) { $m += " GPU: $gpu." }
    $m += " What to do: update the graphics driver from the GPU maker's site, close other programs that use the GPU, then run the installer again to redo this step."
    $m + " Log line: $line"
}

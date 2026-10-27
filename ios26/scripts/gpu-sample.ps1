# Per-process GPU use of one PID from Windows' GPU performance counters (CIM, locale-free):
# engine utilisation per adapter LUID and engine type (the busiest engine, as Task Manager shows it), and dedicated/shared GPU memory.
#   gpu-sample.ps1 -ProcId (Get-Process qemu-system-aarch64w).Id -Out gpu.csv -Seconds 60
# Rows: t (Unix time), kind (engine/mem/cpu), adapter LUID, engine type or memory kind, value.
# Task Manager's GPU columns read the same counters.
param([int]$ProcId, [string]$Out, [int]$Seconds = 30)
$f = "Name LIKE 'pid[_]$ProcId[_]%'"
$t0 = Get-Date
$p = Get-Process -Id $ProcId
$cpu0 = $p.TotalProcessorTime; $w0 = Get-Date
't,kind,luid,key,value' | Set-Content $Out -Encoding ascii
while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
    $t = [math]::Round([DateTimeOffset]::Now.ToUnixTimeMilliseconds() / 1000, 1)
    $rows = @()
    $eng = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -Filter $f
    $eng | ForEach-Object {
        if ($_.Name -match 'luid_0x[0-9A-Fa-f]+_(0x[0-9A-Fa-f]+)_phys_\d+_eng_\d+_engtype_(.+)$') {
            [pscustomobject]@{ L = $Matches[1]; E = $Matches[2]; U = [int]$_.UtilizationPercentage }
        }
    } | Group-Object L, E | ForEach-Object {
        $rows += "$t,engine,$($_.Group[0].L),$($_.Group[0].E),$(($_.Group | Measure-Object U -Maximum).Maximum)"
    }
    Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory -Filter $f | ForEach-Object {
        if ($_.Name -match 'luid_0x[0-9A-Fa-f]+_(0x[0-9A-Fa-f]+)_phys') {
            $rows += "$t,mem,$($Matches[1]),dedicated_mb,$([math]::Round($_.DedicatedUsage / 1MB))"
            $rows += "$t,mem,$($Matches[1]),shared_mb,$([math]::Round($_.SharedUsage / 1MB))"
        }
    }
    $p.Refresh(); $now = Get-Date
    $rows += "$t,cpu,-,cores_busy,$([math]::Round(($p.TotalProcessorTime - $cpu0).TotalSeconds / ($now - $w0).TotalSeconds, 2))"
    $cpu0 = $p.TotalProcessorTime; $w0 = $now
    $rows | Add-Content $Out -Encoding ascii
    Start-Sleep -Milliseconds 700
}

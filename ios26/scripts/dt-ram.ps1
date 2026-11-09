# A device tree with another guest RAM size, for -M vresearch (iOS 26, watchOS): QEMU takes the RAM size
# from the tree. /chosen dram-size and the size in /memory reg become SIZE, and /product/util moves to
# right after the new end of DRAM (vresearch_dt_fixup's layout), as the Android app's Guest.tree does.
#   dt-ram.ps1 -In dtree-smp4 -Out dtree-smp4-6144m -MiB 6144      (prints the tree's RAM before and after)
#   dt-ram.ps1 -In dtree-smp4 -Read                               (prints its RAM in MiB)
# A tree without that layout (no such properties, or util not right after DRAM) is refused.
param(
    [Parameter(Mandatory = $true)][string]$In,
    [string]$Out = '',
    [int]$MiB = 0,
    [switch]$Read
)
$ErrorActionPreference = 'Stop'
$b = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $In).Path)
$script:at = @{}
function Walk([int]$o, [string]$path) {
    $np = [BitConverter]::ToInt32($b, $o); $nc = [BitConverter]::ToInt32($b, $o + 4)
    $o += 8
    $name = '?'; $props = @{}
    for ($i = 0; $i -lt $np; $i++) {
        $z = 0; while ($z -lt 32 -and $b[$o + $z] -ne 0) { $z++ }
        $pn = [Text.Encoding]::ASCII.GetString($b, $o, $z)
        $ln = [BitConverter]::ToInt32($b, $o + 32) -band 0x7fffffff
        $props[$pn] = $o + 36
        if ($pn -ceq 'name') {
            $k = 0; while ($k -lt $ln -and $b[$o + 36 + $k] -ne 0) { $k++ }
            $name = [Text.Encoding]::ASCII.GetString($b, $o + 36, $k)
        }
        $o += 36 + (($ln + 3) -band -4)
    }
    $here = if ($path) { "$path/$name" } else { $name }
    if ($name -ceq 'chosen' -and $props.ContainsKey('dram-size')) { $script:at.size = $props['dram-size'] }
    elseif ($name -ceq 'memory' -and $props.ContainsKey('reg')) { $script:at.mem = $props['reg'] }
    elseif ($here.EndsWith('/product/util', [StringComparison]::Ordinal) -and $props.ContainsKey('reg')) { $script:at.util = $props['reg'] }
    for ($i = 0; $i -lt $nc; $i++) { $o = Walk $o $here }
    $o
}
$end = Walk 0 ''
if ($end -ne $b.Length -or -not $at.ContainsKey('size') -or -not $at.ContainsKey('mem') -or -not $at.ContainsKey('util')) {
    throw "$In`: no /chosen dram-size, /memory reg or /product/util reg"
}
$size = [BitConverter]::ToInt64($b, $at.size)
$base = [BitConverter]::ToInt64($b, $at.mem)
$util = [BitConverter]::ToInt64($b, $at.util)
if ([BitConverter]::ToInt64($b, $at.mem + 8) -ne $size -or $util -ne $base + $size) {
    throw ("$In`: /memory reg or /product/util is not where it should be (dram 0x{0:x} + 0x{1:x}, util 0x{2:x})" -f $base, $size, $util)
}
if ($Read) { [int]($size -shr 20); exit 0 }
if ($MiB -lt 1024 -or -not $Out) { throw 'give -Out and -MiB (1024 or more), or -Read' }
$new = [long]$MiB * 1MB
# (parenthesised: the comma binds tighter than +)
foreach ($p in @(@($at.size, $new), @(($at.mem + 8), $new), @($at.util, ($base + $new)))) {
    [Array]::Copy([BitConverter]::GetBytes([long]$p[1]), 0, $b, [int]$p[0], 8)
}
$tmp = "$Out.tmp"
[IO.File]::WriteAllBytes($tmp, $b)
Move-Item -LiteralPath $tmp -Destination $Out -Force
'dram base 0x{0:x}: {1} MiB -> {2} MiB; util -> 0x{3:x}' -f $base, ($size -shr 20), $MiB, ($base + $new)

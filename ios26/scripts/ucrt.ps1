# Run a bash script inside MSYS2 UCRT64 from PowerShell (never from Git Bash).
#   powershell -File ucrt.ps1 SCRIPT.sh [args...]
param([Parameter(Mandatory)][string]$Script, [Parameter(ValueFromRemainingArguments)][string[]]$Rest)
$env:MSYSTEM = 'UCRT64'; $env:CHERE_INVOKING = '1'; $env:LANG = 'C'; $env:LC_ALL = 'C'
$s = $Script.Replace([char]92, [char]47)
$a = ($Rest | ForEach-Object { "'" + ($_ -replace "'", "'\''") + "'" }) -join ' '
& C:\msys64\usr\bin\bash.exe -lc "bash '$s' $a" 2>&1 | Where-Object { $_ -notmatch 'cp: cannot stat' }
exit $LASTEXITCODE

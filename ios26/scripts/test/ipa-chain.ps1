# Runs the real text of Install-Ipa.ps1's extract / noget / sign / zip blocks on a made-up .ipa (mkipa.py makes one), then
# the generated place.sh in WSL (as root) on a fake disk root under /tmp. No disk image, no VM, no nbd. Prints what ran;
# look for RC=0 (placed), or the refusal. -Again: a second install on the root the last run left; -NoSystemApp: no
# app of that name on the fake disk (else an unmarked com.apple.fake app of the same name is there: refused).
#   python -I mkipa.py x.ipa ; powershell -File ipa-chain.ps1 -Ipa x.ipa -Tmp <empty work folder>
param([string]$Ipa, [string]$Tmp, [string]$FakeRoot = '/tmp/r26-e2e', [switch]$NoSystemApp, [switch]$Again, [string]$SystemApp = 'Fake.app')
$ErrorActionPreference = 'Stop'
$here = Split-Path (Split-Path $PSScriptRoot)   # ios26
$script = Join-Path $here 'Install-Ipa.ps1'
$text = Get-Content -Raw $script
function Slice([string]$from, [string]$to) { $i = $text.IndexOf($from); if ($i -lt 0) { throw "no $from" }; $j = $text.IndexOf($to, $i); if ($j -lt 0) { throw "no $to" }; $text.Substring($i, $j - $i) }
$ast = [Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$null)
foreach ($n in 'Sh-Quote', 'Get-PlaceScript', 'To-Wsl', 'Pack-Payload') { . ([scriptblock]::Create($ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -ceq $n }, $true)[0].Extent.Text)) }
$script:placeFail = ''
$scriptsDir = "$here\scripts"
$python = (Get-Command python.exe).Source
function Py { param([string]$script) & $python '-I' $script @args }
function Fail($m) { throw "FAIL: $m" }
$cdhashPy = "$scriptsDir\cdhash.py"; $mktcPy = "$scriptsDir\mktc.py"; $nogetPy = "$scriptsDir\noget.py"
$ipaHashesPy = "$scriptsDir\ipa-hashes.py"; $placePy = "$scriptsDir\ipa-place.py"
if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp }
New-Item -ItemType Directory -Force $Tmp | Out-Null
$tmp = $Tmp
$Ipa = (Resolve-Path $Ipa).Path
$Linux = 'wsl'

. ([scriptblock]::Create((Slice '    Write-Host "Extracting' '    # A developer-signed .app has get-task-allow')))
. ([scriptblock]::Create((Slice '    # A developer-signed .app has get-task-allow' '    # apps trust cache = base tc')))
Write-Host "--- hashes file:"; Get-Content $hashFile
. ([scriptblock]::Create((Slice '    # The signed app as a .ipa' '    # place the app into /Applications')))
Write-Host "--- signed.ipa $((Get-Item $signedIpa).Length) bytes (pad $pad), extract folder gone: $(-not (Test-Path $ex))"
$names = & $python -I -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); print(len(z.namelist()), z.namelist()[:6])" $signedIpa
Write-Host "--- zip entries: $names"

$inner = Join-Path $tmp 'place.sh'
(Get-PlaceScript (To-Wsl $placePy) (To-Wsl $signedIpa) ([IO.Path]::GetFileName($Ipa))) | Set-Content -Encoding ASCII -NoNewline $inner
Write-Host '--- place.sh:'; Get-Content $inner

# a fake disk root
$prep = @"
set -eu
R=$FakeRoot
rm -rf `$R; mkdir -p `$R/Applications `$R/private/var/mobile/Containers/Data/InternalDaemon/ab
touch `$R/private/var/mobile/Containers/Data/InternalDaemon/ab/com.apple.LaunchServices-1.csstore
"@
if ($Again) { $prep = "set -eu`nR=$FakeRoot`n" }
elseif (-not $NoSystemApp) {
    $prep += "`n" + @"
mkdir -p `$R/Applications/$SystemApp; echo old > `$R/Applications/$SystemApp/old-file
python3 -c "import plistlib; open('`$R/Applications/$SystemApp/Info.plist','wb').write(plistlib.dumps({'CFBundleIdentifier':'com.apple.fake'}))"
"@
}
$prep += "`nset +e`nexport R; bash $(To-Wsl $inner)`necho RC=`$?`n"
$sh = Join-Path $tmp 'run-e2e.sh'
($prep -replace "`r`n", "`n") | Set-Content -Encoding ASCII -NoNewline $sh
$env:MSYS_NO_PATHCONV = '1'
$ErrorActionPreference = 'Continue'
& wsl -u root -e bash (To-Wsl $sh) 2>&1 | ForEach-Object { "$_" }

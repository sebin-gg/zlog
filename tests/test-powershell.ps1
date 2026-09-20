<# tests/test-powershell.ps1 — fixture tests for scripts/zlog.ps1.
   Run: powershell -ExecutionPolicy Bypass -File tests/test-powershell.ps1 [-Script path] #>
param([string]$Script = (Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'scripts/zlog.ps1'))
$ErrorActionPreference = 'Stop'
$base = Join-Path ([IO.Path]::GetTempPath()) ('zlogtest_' + [Guid]::NewGuid().ToString('N'))
$env:ZLOG_TEST_ROOT = Join-Path $base '.claude'
New-Item -ItemType Directory -Path (Join-Path $env:ZLOG_TEST_ROOT 'node_modules') -Force | Out-Null
$fail = 0
function Check($n, $c) { if (& $c) { Write-Output "PASS: $n" } else { Write-Output "FAIL: $n"; $script:fail++ } }
function BigFile($p, $kb, $seed) {
  $rnd = New-Object Random($seed); $b = New-Object byte[] ($kb * 1024)
  for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = [byte](65 + $rnd.Next(26)) }
  [IO.File]::WriteAllBytes($p, $b)
}
$r = $env:ZLOG_TEST_ROOT
BigFile (Join-Path $r 'ok.log') 20 11
BigFile (Join-Path $r 'locked.log') 20 12
BigFile (Join-Path $r 'node_modules\junk.log') 20 13
BigFile (Join-Path $r 'keep.jsonl') 20 14
New-Item -ItemType File -Path (Join-Path $r 'oldempty.log') -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $r 'newempty.log') -Force | Out-Null
$old = (Get-Date).AddMinutes(-5)
foreach ($f in @('ok.log','locked.log','node_modules\junk.log','keep.jsonl','oldempty.log')) { (Get-Item (Join-Path $r $f)).LastWriteTime = $old }
$lk = [IO.File]::Open((Join-Path $r 'locked.log'), 'Open', 'ReadWrite', 'None')

Write-Output '--- preview (must change nothing) ---'
& $Script preview | Tee-Object -Variable prev | Out-Null
Check 'preview lists candidate' { $prev -match 'ok\.log' }
Check 'preview changes nothing' { Test-Path (Join-Path $r 'ok.log') }

Write-Output '--- clean ---'
& $Script clean | Tee-Object -Variable cleanOut | Out-Null
$lk.Close()
Check 'compressible archived' { (-not (Test-Path (Join-Path $r 'ok.log'))) -and @(Get-Item (Join-Path $r 'ok.log.tar.gz')).Count -gt 0 }
Check 'locked skipped' { (Test-Path (Join-Path $r 'locked.log')) -and -not (Test-Path (Join-Path $r 'locked.log.tar.gz')) }
Check 'junk kept' { Test-Path (Join-Path $r 'node_modules\junk.log') }
Check 'jsonl kept' { Test-Path (Join-Path $r 'keep.jsonl') }
Check 'old empty purged' { -not (Test-Path (Join-Path $r 'oldempty.log')) }
Check 'fresh empty kept' { Test-Path (Join-Path $r 'newempty.log') }
Check 'report line present' { $cleanOut -match '^\[zlog\] mode=clean' }

Write-Output '--- restore ---'
& $Script restore (Join-Path $r 'ok.log.tar.gz') | Out-Null
Check 'restored, archive kept' { (Test-Path (Join-Path $r 'ok.log')) -and (Test-Path (Join-Path $r 'ok.log.tar.gz')) }

Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item Env:\ZLOG_TEST_ROOT -ErrorAction SilentlyContinue
if ($fail -eq 0) { Write-Output 'POWERSHELL TESTS ALL PASS' } else { Write-Output 'POWERSHELL TESTS FAILED'; exit 1 }

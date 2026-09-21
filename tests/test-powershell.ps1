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
New-Item -ItemType File -Path (Join-Path $r 'transcript_empty.log') -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $r 'history.log') -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $r 'conversation.out') -Force | Out-Null
$old = (Get-Date).AddMinutes(-5)
foreach ($f in @('ok.log','locked.log','node_modules\junk.log','keep.jsonl','oldempty.log','transcript_empty.log','history.log','conversation.out')) { (Get-Item (Join-Path $r $f)).LastWriteTime = $old }
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
Check 'empty transcript protected' { Test-Path (Join-Path $r 'transcript_empty.log') }
Check 'empty history protected' { Test-Path (Join-Path $r 'history.log') }
Check 'empty conversation protected' { Test-Path (Join-Path $r 'conversation.out') }
Check 'report line present' { $cleanOut -match '^\[zlog\] mode=clean' }

Write-Output '--- restore ---'
& $Script restore (Join-Path $r 'ok.log.tar.gz') | Out-Null
Check 'restored, archive kept' { (Test-Path (Join-Path $r 'ok.log')) -and (Test-Path (Join-Path $r 'ok.log.tar.gz')) }

Write-Output '--- collision (existing dest -> UNSAFE-SKIP, source preserved) ---'
BigFile (Join-Path $r 'collide.log') 20 21
(Get-Item (Join-Path $r 'collide.log')).LastWriteTime = (Get-Date).AddMinutes(-5)
'pre-existing-dest' | Out-File -FilePath (Join-Path $r 'collide.log.tar.gz') -Encoding ascii -Force
$destBefore = (Get-Item (Join-Path $r 'collide.log.tar.gz')).Length
$clean2 = @(& $Script clean)
$clean2 | ForEach-Object { Write-Output $_ }
Check 'collision source preserved' { Test-Path (Join-Path $r 'collide.log') }
Check 'collision dest untouched' { (Get-Item (Join-Path $r 'collide.log.tar.gz')).Length -eq $destBefore }
Check 'collision reported' { $clean2 -match 'UNSAFE-SKIP' }
Remove-Item (Join-Path $r 'collide.log') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $r 'collide.log.tar.gz') -Force -ErrorAction SilentlyContinue

Write-Output '--- tar traversal / mismatch restore refused ---'
$stage = Join-Path $r 'travstage'
New-Item -ItemType Directory -Path (Join-Path $stage 'sub') -Force | Out-Null
'evil' | Out-File -FilePath (Join-Path $stage 'evil.log') -Encoding ascii -Force
& tar -czf (Join-Path $r 'trav.log.tar.gz') -C (Join-Path $stage 'sub') '../evil.log' 2>$null
BigFile (Join-Path $r 'wrongname.log') 1 30
& tar -czf (Join-Path $r 'mismatch.log.tar.gz') -C $r 'wrongname.log' 2>$null
Remove-Item (Join-Path $r 'wrongname.log') -Force -ErrorAction SilentlyContinue
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
& $Script restore (Join-Path $r 'trav.log.tar.gz') | Out-Null
$travRc = $LASTEXITCODE
Check 'traversal refused' { $travRc -ne 0 }
Check 'traversal no output' { -not (Test-Path (Join-Path $r 'trav.log')) }
& $Script restore (Join-Path $r 'mismatch.log.tar.gz') | Out-Null
$misRc = $LASTEXITCODE
Check 'mismatch refused' { $misRc -ne 0 }
Check 'mismatch no output' { -not (Test-Path (Join-Path $r 'mismatch.log')) }
Remove-Item (Join-Path $r 'trav.log.tar.gz') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $r 'mismatch.log.tar.gz') -Force -ErrorAction SilentlyContinue

Write-Output '--- corrupt archive restore ---'
$rnd = New-Object Random(99); $cb = New-Object byte[] 100
for ($i = 0; $i -lt $cb.Length; $i++) { $cb[$i] = [byte]$rnd.Next(256) }
[IO.File]::WriteAllBytes((Join-Path $r 'corrupt.log.tar.gz'), $cb)
& $Script restore (Join-Path $r 'corrupt.log.tar.gz') | Out-Null
$corRc = $LASTEXITCODE
Check 'corrupt refused' { $corRc -ne 0 }
Check 'corrupt no output' { -not (Test-Path (Join-Path $r 'corrupt.log')) }
Remove-Item (Join-Path $r 'corrupt.log.tar.gz') -Force -ErrorAction SilentlyContinue

Write-Output '--- space filename ---'
BigFile (Join-Path $r 'space name.log') 20 22
(Get-Item (Join-Path $r 'space name.log')).LastWriteTime = (Get-Date).AddMinutes(-5)
& $Script clean | Out-Null
Check 'space archived' { (-not (Test-Path (Join-Path $r 'space name.log'))) -and (Test-Path (Join-Path $r 'space name.log.tar.gz')) }

Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item Env:\ZLOG_TEST_ROOT -ErrorAction SilentlyContinue
if ($fail -eq 0) { Write-Output 'POWERSHELL TESTS ALL PASS' } else { Write-Output 'POWERSHELL TESTS FAILED'; exit 1 }

<# tests/test-powershell.ps1 — fixture tests for scripts/zlog.ps1.
   Run: powershell -ExecutionPolicy Bypass -File tests/test-powershell.ps1 [-Script path] #>
param([string]$Script = (Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'scripts/zlog.ps1'))
$ErrorActionPreference = 'Stop'
$base = Join-Path ([IO.Path]::GetTempPath()) ('zlogtest_' + [Guid]::NewGuid().ToString('N'))
$env:ZLOG_TEST_ROOT = Join-Path $base '.claude'
New-Item -ItemType Directory -Path (Join-Path $env:ZLOG_TEST_ROOT 'node_modules') -Force | Out-Null
$fail = 0
function Check($n, $c) {
  # Wrap in try/catch: without it a single assertion that throws (e.g. reading
  # a file a previous failure deleted) aborts the whole suite, hiding every
  # later regression behind the first one.
  $ok = $false
  try { $ok = [bool](& $c) } catch { $ok = $false }
  if ($ok) { Write-Output "PASS: $n" } else { Write-Output "FAIL: $n"; $script:fail++ }
}
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

Write-Output '--- corrupt stream restore leaves no partial output ---'
$rnd2 = New-Object Random(100); $cb2 = New-Object byte[] 100
for ($i = 0; $i -lt $cb2.Length; $i++) { $cb2[$i] = [byte]$rnd2.Next(256) }
[IO.File]::WriteAllBytes((Join-Path $r 'corrupt2.log.gz'), $cb2)
& $Script restore (Join-Path $r 'corrupt2.log.gz') | Out-Null
$cor2Rc = $LASTEXITCODE
Check 'corrupt gz refused' { $cor2Rc -ne 0 }
Check 'corrupt gz no output' { -not (Test-Path (Join-Path $r 'corrupt2.log')) }
Check 'corrupt gz no tmp leftovers' { @(Get-ChildItem $r -Filter '*.tmp.restore*').Count -eq 0 }
Check 'corrupt gz archive kept' { Test-Path (Join-Path $r 'corrupt2.log.gz') }
Remove-Item (Join-Path $r 'corrupt2.log.gz') -Force -ErrorAction SilentlyContinue

Write-Output '--- space filename ---'
BigFile (Join-Path $r 'space name.log') 20 22
(Get-Item (Join-Path $r 'space name.log')).LastWriteTime = (Get-Date).AddMinutes(-5)
& $Script clean | Out-Null
Check 'space archived' { (-not (Test-Path (Join-Path $r 'space name.log'))) -and (Test-Path (Join-Path $r 'space name.log.tar.gz')) }

Write-Output '--- empty archive restore (0-byte original is legitimate) ---'
# The old guard required the decompressed temp to be non-empty, so restoring an
# empty .log reported FAILED and deleted its own output. Corrupt archives must
# still be refused with nothing written.
[IO.File]::WriteAllBytes((Join-Path $r 'empty.log'), (New-Object byte[] 0))
& tar -czf (Join-Path $r 'empty.log.tar.gz') -C $r 'empty.log' 2>$null
Remove-Item (Join-Path $r 'empty.log') -Force -ErrorAction SilentlyContinue
& $Script restore (Join-Path $r 'empty.log.tar.gz') | Out-Null
$empRc = $LASTEXITCODE
Check 'empty restore succeeds' { $empRc -eq 0 }
Check 'empty restore produced the file' { Test-Path (Join-Path $r 'empty.log') }
Check 'empty restore is 0 bytes' { (Test-Path -LiteralPath (Join-Path $r 'empty.log')) -and ((Get-Item -LiteralPath (Join-Path $r 'empty.log')).Length -eq 0) }
Remove-Item (Join-Path $r 'empty.log') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $r 'empty.log.tar.gz') -Force -ErrorAction SilentlyContinue

Write-Output '--- destination names with glob metacharacters ---'
# Plain Test-Path / Remove-Item treat [ ] as a wildcard character class, so a
# destination named `srv[1].log` bypassed the "destination exists" guard and the
# failure-path cleanup entirely. -LiteralPath is what makes the guard real.
[IO.File]::WriteAllText((Join-Path $r 'srv[1].log'), 'PRECIOUS PRE-EXISTING CONTENT')
[IO.File]::WriteAllText((Join-Path $r 'gsrc.log'), 'restored')
& tar -czf (Join-Path $r 'srv[1].log.tar.gz') -C $r 'gsrc.log' 2>$null
Remove-Item -LiteralPath (Join-Path $r 'gsrc.log') -Force -ErrorAction SilentlyContinue
$globOut = @(& $Script restore (Join-Path $r 'srv[1].log.tar.gz'))
$globOut | ForEach-Object { Write-Output $_ }
$globRc = $LASTEXITCODE
Check 'glob-name dest refused' { $globRc -ne 0 }
Check 'glob-name guard actually fired' { $globOut -match 'UNSAFE-SKIP \(destination exists\)' }
Check 'glob-name content untouched' { (Test-Path -LiteralPath (Join-Path $r 'srv[1].log')) -and ([IO.File]::ReadAllText((Join-Path $r 'srv[1].log')) -eq 'PRECIOUS PRE-EXISTING CONTENT') }
Remove-Item -LiteralPath (Join-Path $r 'srv[1].log') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $r 'srv[1].log.tar.gz') -Force -ErrorAction SilentlyContinue

Write-Output '--- restore never deletes a pre-existing file it did not write ---'
# The failure path used to run `Remove-Item $out` unconditionally, so a restore
# that failed for any other reason could delete a pre-existing file. The
# `$wrote` flag means the cleanup can only ever remove this run's own output.
[IO.File]::WriteAllBytes((Join-Path $r 'svc.log.zst'), (New-Object byte[] 64))
[IO.File]::WriteAllText((Join-Path $r 'svc.log'), 'NOT OURS')
& $Script restore (Join-Path $r 'svc.log.zst') | Out-Null
$svcRc = $LASTEXITCODE
Check 'failed restore refused' { $svcRc -ne 0 }
Check 'failed restore left the pre-existing file' { Test-Path (Join-Path $r 'svc.log') }
Remove-Item (Join-Path $r 'svc.log') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $r 'svc.log.zst') -Force -ErrorAction SilentlyContinue

Write-Output '--- purge quarantines the name before deleting ---'
# The rename is the load-bearing part: after it, a writer opening by path cannot
# reach the file, so the check-then-remove window no longer exists. Assert the
# observable invariants here; the race-specific regression lives in
# test-posix.sh, where it can be made deterministic by stalling the rename.
$PQP = Join-Path $base 'purgeq'
New-Item -ItemType Directory -Path $PQP -Force | Out-Null
[IO.File]::WriteAllBytes((Join-Path $PQP 'stillempty.log'), (New-Object byte[] 0))
[IO.File]::WriteAllText((Join-Path $PQP 'hasbytes.log'), 'LIVE SESSION DATA')
$oldPq = (Get-Date).AddMinutes(-5)
(Get-Item -LiteralPath (Join-Path $PQP 'stillempty.log')).LastWriteTime = $oldPq
(Get-Item -LiteralPath (Join-Path $PQP 'hasbytes.log')).LastWriteTime = $oldPq
$oldP = $env:ZLOG_TEST_ROOT
$env:ZLOG_TEST_ROOT = $PQP
& $Script clean | Out-Null
$env:ZLOG_TEST_ROOT = $oldP
Check 'quarantine purges a still-empty file' { -not (Test-Path -LiteralPath (Join-Path $PQP 'stillempty.log')) }
Check 'quarantine leaves the non-empty file' { Test-Path -LiteralPath (Join-Path $PQP 'hasbytes.log') }
Check 'its bytes are intact' { [IO.File]::ReadAllText((Join-Path $PQP 'hasbytes.log')) -eq 'LIVE SESSION DATA' }
Check 'quarantine leaves no .purge debris' { @(Get-ChildItem -LiteralPath $PQP -Filter '*.purge' -Recurse -ErrorAction SilentlyContinue).Count -eq 0 }
Remove-Item -LiteralPath $PQP -Recurse -Force -ErrorAction SilentlyContinue

Write-Output '--- clean exits non-zero when files fail ---'
# DoClean used to end on the report line, so a run where every file errored
# still exited 0 and any caller gating on the exit status read it as success.
#
# Run in a CHILD process: `& $Script` does not put the script's exit status in
# $LASTEXITCODE, which still holds whatever the last *native* command returned.
# That made this assertion pass against the unfixed script for the wrong reason.
#
# Injected by shadowing the compressor with a stub that always fails. That is
# Unix-only: on Windows PowerShell refuses to run a text file named `tar.exe`
# as a native command ("StandardErrorEncoding is only supported when standard
# error is redirected"), and in-process function shadowing cannot reach a child
# process. So the exit-status contract is asserted here on Unix, and on Windows
# it is covered indirectly by the `restore` exit-status checks above.
if ($PSVersionTable.Platform -ne 'Unix') {
  Write-Output 'SKIP: clean exit-status (compressor stub cannot shadow tar.exe on Windows)'
} else {
  $deadBin = Join-Path $base 'deadbin'
  New-Item -ItemType Directory -Path $deadBin -Force | Out-Null
  [IO.File]::WriteAllText((Join-Path $deadBin 'tar'), "#!/bin/sh`nexit 1`n")
  & /bin/chmod '+x' (Join-Path $deadBin 'tar') 2>$null
  $oldPath = $env:PATH
  $env:PATH = $deadBin + [IO.Path]::PathSeparator + $oldPath
  BigFile (Join-Path $r 'deadc.log') 20 31
  (Get-Item -LiteralPath (Join-Path $r 'deadc.log')).LastWriteTime = (Get-Date).AddMinutes(-5)
  $selfExe = (Get-Process -Id $PID).Path
  $deadOut = @(& $selfExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Script clean 2>&1)
  $deadOut | ForEach-Object { Write-Output $_ }
  $deadRc = $LASTEXITCODE
  Check 'failing clean reports failed>0' { $deadOut -match 'failed=[1-9]' }
  Check 'failing clean exits non-zero' { $deadRc -ne 0 }
  Check 'failing clean preserved the source' { Test-Path -LiteralPath (Join-Path $r 'deadc.log') }
  $env:PATH = $oldPath
  Remove-Item -LiteralPath (Join-Path $r 'deadc.log') -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $deadBin -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output '--- deep alias (same roots as standard, explicit) ---'
BigFile (Join-Path $r 'deepfix.log') 20 23
(Get-Item (Join-Path $r 'deepfix.log')).LastWriteTime = (Get-Date).AddMinutes(-5)
$dp = @(& $Script deep-preview)
$dp | ForEach-Object { Write-Output $_ }
Check 'deep-preview lists candidate' { $dp -match 'deepfix\.log' }
Check 'deep-preview says alias' { $dp -match 'same roots as preview' }
$beforeDeep = @(Get-ChildItem $r -Recurse | ForEach-Object { $_.FullName }) -join "`n"
& $Script deep-preview | Out-Null
$afterDeep = @(Get-ChildItem $r -Recurse | ForEach-Object { $_.FullName }) -join "`n"
Check 'deep-preview changes nothing' { $afterDeep -eq $beforeDeep }
$d = @(& $Script deep)
$d | ForEach-Object { Write-Output $_ }
Check 'deep says alias' { $d -match 'same operation as clean' }
Check 'deep archived' { (-not (Test-Path (Join-Path $r 'deepfix.log'))) -and (Test-Path (Join-Path $r 'deepfix.log.tar.gz')) }
Check 'deep report line present' { $d -match '^\[zlog\] mode=clean' }

Write-Output '--- race (same-size mutation mid-compression -> preserved) ---'
$realTarCmd = Get-Command tar.exe -ErrorAction SilentlyContinue
if (-not $realTarCmd) { Write-Output 'SKIP: race test (no tar.exe)' }
else {
  $realTarBin = $realTarCmd.Source
  $probePs1 = Join-Path $r 'shadowprobe.ps1'
  '@(& tar.exe --version)' | Out-File -FilePath $probePs1 -Encoding ascii -Force
  function tar.exe {
    $global:zlogShadowHit = $true
    # tar is invoked as: tar -czf <tmp> -C <dir> <name> — the *.log arg
    # is a bare name resolved against the preceding -C directory.
    for ($i = 0; $i -lt $args.Count; $i++) {
      $cand = $null
      if ($args[$i] -eq '-C' -and ($i + 2 -lt $args.Count) -and ($args[$i + 2] -like '*.log')) {
        $cand = Join-Path $args[$i + 1] $args[$i + 2]
      } elseif ($args[$i] -like '*.log' -and (Test-Path $args[$i] -PathType Leaf)) {
        $cand = $args[$i]
      }
      if ($cand -and (Test-Path $cand -PathType Leaf)) {
        try {
          $it = Get-Item $cand
          $wt = $it.LastWriteTime; $ct = $it.CreationTime
          $b = [IO.File]::ReadAllBytes($cand)
          if ($b.Length -gt 6000) { $b[5000] = [byte](($b[5000] + 1) % 256) }
          [IO.File]::WriteAllBytes($cand, $b)
          $it2 = Get-Item $cand
          $it2.LastWriteTime = $wt; $it2.CreationTime = $ct
        } catch {}
      }
    }
    & $realTarBin @args
  }
  & $probePs1 2>$null | Out-Null
  if (-not $global:zlogShadowHit) { Write-Output 'SKIP: race test (function shadowing unavailable)' }
  else {
    BigFile (Join-Path $r 'race.log') 20 24
    (Get-Item (Join-Path $r 'race.log')).LastWriteTime = (Get-Date).AddMinutes(-5)
    $raceOut = @(& $Script clean)
    $raceOut | ForEach-Object { Write-Output $_ }
    Check 'race source preserved' { Test-Path (Join-Path $r 'race.log') }
    Check 'race no archive' { -not (Test-Path (Join-Path $r 'race.log.tar.gz')) }
    Check 'race reported' { $raceOut -match 'source changed' }
    Remove-Item (Join-Path $r 'race.log') -Force -ErrorAction SilentlyContinue
  }
  Remove-Item function:tar.exe -ErrorAction SilentlyContinue
  Remove-Variable zlogShadowHit -Scope Global -ErrorAction SilentlyContinue
  Remove-Item $probePs1 -Force -ErrorAction SilentlyContinue
}

Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item Env:\ZLOG_TEST_ROOT -ErrorAction SilentlyContinue
# Exit explicitly on BOTH paths. Without `exit 0`, pwsh falls back to
# $LASTEXITCODE, which the corrupt-archive fixtures have already set to 1 from
# their deliberately-failing `gzip -d -c` calls — so a fully passing run
# reported exit 1 and failed CI while printing "POWERSHELL TESTS ALL PASS".
if ($fail -eq 0) { Write-Output 'POWERSHELL TESTS ALL PASS'; exit 0 }
Write-Output 'POWERSHELL TESTS FAILED'; exit 1

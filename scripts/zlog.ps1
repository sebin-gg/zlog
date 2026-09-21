<# zlog.ps1 — Windows implementation helper for the zlog Agent Skill.
   NOT a standalone product CLI. The skill invokes it; humans may run it
   by hand for testing. All destructive behavior lives here (testable).
   Usage: zlog.ps1 preview|clean|deep-preview|deep [-OlderThanDays N]|restore [files...]
   Works on stock Windows PowerShell 5.1 and PowerShell 7+. #>
param([string]$Mode = '', [string[]]$Files = @(), [int]$OlderThanDays = 0)

$ErrorActionPreference = 'Stop'
$zlogPaths = "$env:USERPROFILE\.gemini","$env:APPDATA\Cursor","$env:USERPROFILE\.config\Cursor","$env:USERPROFILE\.cursor","$env:USERPROFILE\.ollama","$env:LOCALAPPDATA\Ollama","$env:USERPROFILE\.claude","$env:USERPROFILE\.config\claude-code","$env:USERPROFILE\.windsurf","$env:APPDATA\Windsurf","$env:USERPROFILE\.config\Windsurf","$env:USERPROFILE\.codex","$env:USERPROFILE\.cache\lm-studio","$env:USERPROFILE\.lmstudio"
$junk = '\node_modules\','\Caches\','\Cache\','\Code Cache\','\blob_storage\','\GPUCache\','\DawnGraphiteCache\','\DawnWebGPUCache\','\.git\'
if ($env:ZLOG_TEST_ROOT) { $zlogPaths = @($env:ZLOG_TEST_ROOT) }
if ($PSVersionTable.Platform -eq 'Unix') { $tarBin = 'tar' } else { $tarBin = 'tar.exe' }

function zlogFmt($b) { if ($b -ge 1073741824) { "{0:N1}G" -f ($b/1073741824) } elseif ($b -ge 1048576) { "{0:N1}M" -f ($b/1048576) } elseif ($b -ge 1024) { "{0:N1}K" -f ($b/1024) } else { "${b}B" } }
# 5.1-safe lock probe (inline try/catch is a statement and illegal inside Where-Object on 5.1)
function zlogFree($p) { try { $s = [System.IO.File]::Open($p, 'Open', 'ReadWrite', 'None'); $s.Close(); $true } catch { $false } }

function zlogCutoffMinutes() { if ($OlderThanDays -gt 0) { return ($OlderThanDays * 1440 + 1) } return 1 }

function zlogIsProtected($name) {
  # Class B: never touch, whatever the extension filter says
  $low = $name.ToLower()
  foreach ($pat in @('*.jsonl','transcript*','conversation*','history*','*.sqlite*','*.db','*.wal','*.shm','SKILL.md','README*','LICENSE*','*.gz','*.zst','*.xz','*.tmp.*')) {
    if ($low -like $pat) { return $true }
  }
  return $false
}

function zlogIsJunk($fullPath) {
  $pn = $fullPath -replace '/', '\'
  foreach ($j in $junk) { if ($pn -like "*$j*") { return $true } }
  return $false
}

# Shared candidate engine: preview AND clean use this, so they never disagree.
function zlogCandidates($minKB, $includeEmpty) {
  $cut = (Get-Date).AddMinutes(-(zlogCutoffMinutes))
  Get-ChildItem -Path $zlogPaths -Recurse -Include *.log,*.out,*.trace -Exclude *.gz,*.zst,*.xz,*.jsonl,SKILL.md,README*,LICENSE* -ErrorAction SilentlyContinue | Where-Object {
    $p = $_.FullName
    -not (zlogIsJunk $p) -and -not (zlogIsProtected $_.Name) -and
    $(if ($includeEmpty) { $_.Length -eq 0 } else { $_.Length -gt ($minKB * 1KB) }) -and
    $_.LastWriteTime -lt $cut
  }
}

function zlogReport($mode, $roots, $cands, $comp, $raw, $saved, $purged, $skipped, $failed, $notbene, $locked) {
  $compBytes = $raw - $saved
  Write-Output "[zlog] mode=$mode roots=$roots candidates=$cands compressed=$comp purged=$purged skipped=$skipped failed=$failed not_beneficial=$notbene locked=$locked"
  Write-Output "[zlog] raw=$(zlogFmt $raw) compressed=$(zlogFmt $compBytes) saved=$(zlogFmt $saved)"
}

function DoPreview() {
  $cands = 0; $raw = 0; $roots = 0
  foreach ($r in $zlogPaths) { if (Test-Path $r) { $roots++ } }
  zlogCandidates 10 $false | ForEach-Object {
    $cands++; $raw += $_.Length
    Write-Output ("[DRY-RUN] Would compress: " + $_.FullName + " (" + (zlogFmt $_.Length) + ")")
  }
  Write-Output ""
  Write-Output "[DRY-RUN] Total: $cands files, $(zlogFmt $raw) raw (compressed size varies by log content; run clean for measured savings)"
}

function DoClean() {
  $cands = 0; $comp = 0; $raw = 0; $saved = 0; $purged = 0; $skipped = 0; $failed = 0; $notbene = 0; $locked = 0
  $roots = 0
  foreach ($r in $zlogPaths) { if (Test-Path $r) { $roots++ } }
  # purge empties through the same predicate + lock check
  zlogCandidates 0 $true | ForEach-Object {
    if (-not (zlogFree $_.FullName)) { $locked++; return }
    try { Remove-Item $_.FullName -Force -ErrorAction Stop; $purged++ } catch { $failed++ }
  }
  zlogCandidates 10 $false | ForEach-Object {
    $cands++
    $preLen = $_.Length
    $preTime = $_.LastWriteTimeUtc
    if (-not (zlogFree $_.FullName)) { $locked++; $skipped++; return }
    $tmp = "$($_.FullName).$PID.tmp.tar.gz"
    $out = "$($_.FullName).tar.gz"
    & $tarBin -czf "$tmp" -C "$($_.DirectoryName)" "$($_.Name)" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) {
      if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
      Write-Output "[zlog] FAILED (compressor error): $($_.FullName) (original preserved)"; $failed++; return
    }
    $tmpLen = (Get-Item $tmp).Length
    if ($tmpLen -le 0 -or $tmpLen -ge $preLen) {
      Remove-Item $tmp -Force -ErrorAction SilentlyContinue
      $notbene++; $skipped++; return
    }
    if (Test-Path $out) {
      Remove-Item $tmp -Force -ErrorAction SilentlyContinue
      Write-Output "[zlog] UNSAFE-SKIP (destination exists): $out (source preserved)"; $skipped++; return
    }
    $cur = Get-Item $_.FullName -ErrorAction SilentlyContinue
    if (-not $cur -or $cur.Length -ne $preLen -or $cur.LastWriteTimeUtc -ne $preTime) {
      Remove-Item $tmp -Force -ErrorAction SilentlyContinue
      Write-Output "[zlog] FAILED (source changed during compression): $($_.FullName) (original preserved)"; $failed++; return
    }
    try { [System.IO.File]::Move($tmp, $out) }
    catch {
      if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
      Write-Output "[zlog] UNSAFE-SKIP (destination exists): $out (source preserved)"; $skipped++; return
    }
    $cur2 = Get-Item $_.FullName -ErrorAction SilentlyContinue
    if (-not $cur2 -or $cur2.Length -ne $preLen -or $cur2.LastWriteTimeUtc -ne $preTime) {
      Remove-Item $out -Force -ErrorAction SilentlyContinue
      Write-Output "[zlog] FAILED (source changed during compression): $($_.FullName) (original preserved)"; $failed++; return
    }
    $new = (Get-Item $out).Length
    $raw += $preLen; $saved += ($preLen - $new); $comp++
    Remove-Item $_.FullName -Force
  }
  zlogReport 'clean' $roots $cands $comp $raw $saved $purged $skipped $failed $notbene $locked
}

function DoDeepPreview() {
  Write-Output '[zlog] deep-preview is read-only; known agent locations only (no unknown-agent discovery)'
  DoPreview
}

function DoDeep() {
  Write-Output '[zlog] deep = clean over known roots (same engine, same predicate)'
  DoClean
}

function DoRestore($paths) {
  if ($paths.Count -eq 0) { Write-Output '[zlog] restore: no files given'; exit 2 }
  $ok = 0; $fail = 0
  foreach ($a in $paths) {
    if ($a -like '*.tar.gz') { $out = $a.Substring(0, $a.Length - 7); $kind = 'tar' }
    elseif ($a -like '*.gz') { $out = $a.Substring(0, $a.Length - 3); $kind = 'gz' }
    elseif ($a -like '*.zst') { $out = $a.Substring(0, $a.Length - 4); $kind = 'zst' }
    elseif ($a -like '*.xz') { $out = $a.Substring(0, $a.Length - 3); $kind = 'xz' }
    else { Write-Output "[zlog] UNSAFE-SKIP (unknown format): $a"; $fail++; continue }
    if (Test-Path $out) { Write-Output "[zlog] UNSAFE-SKIP (destination exists): $out"; $fail++; continue }
    $rc = 1
    if ($kind -eq 'tar') {
      $entries = @(& $tarBin -tzf $a 2>$null)
      $base = Split-Path $out -Leaf
      if (($LASTEXITCODE -eq 0) -and ($entries.Count -eq 1) -and ($entries[0] -eq $base)) {
        $tmpd = "$out.$PID.restore.dir"
        $tmpf = Join-Path $tmpd $base
        New-Item -ItemType Directory -Path $tmpd -Force | Out-Null
        & $tarBin -xzf $a -C $tmpd 2>$null
        if (($LASTEXITCODE -eq 0) -and (Test-Path $tmpf -PathType Leaf)) {
          try { [System.IO.File]::Move($tmpf, $out); $rc = 0 } catch { $rc = 1 }
        }
        Remove-Item $tmpd -Recurse -Force -ErrorAction SilentlyContinue
        if ($rc -ne 0) { Write-Output "[zlog] UNSAFE-SKIP (member mismatch or multi-entry): $a"; $fail++; continue }
      }
      else { Write-Output "[zlog] UNSAFE-SKIP (member mismatch or multi-entry): $a"; $fail++; continue }
    }
    elseif ($kind -eq 'gz' -and (Get-Command gzip -ErrorAction SilentlyContinue)) { gzip -d -c $a > $out 2>$null; $rc = $LASTEXITCODE }
    elseif ($kind -eq 'zst' -and (Get-Command zstd -ErrorAction SilentlyContinue)) { zstd -d -q $a -o $out 2>$null; $rc = $LASTEXITCODE }
    elseif ($kind -eq 'xz' -and (Get-Command xz -ErrorAction SilentlyContinue)) { xz -d -c $a > $out 2>$null; $rc = $LASTEXITCODE }
    if (($rc -eq 0) -and (Test-Path $out) -and ((Get-Item $out).Length -gt 0)) { Write-Output "[zlog] RESTORED: $out (archive preserved)"; $ok++ }
    else { if (Test-Path $out) { Remove-Item $out -Force -ErrorAction SilentlyContinue }; Write-Output "[zlog] FAILED: $a (nothing written; tool missing or archive invalid)"; $fail++ }
  }
  Write-Output "[zlog] restore: ok=$ok failed=$fail"
  if ($fail -gt 0) { exit 1 }
}

switch ($Mode) {
  'preview' { DoPreview }
  'clean' { DoClean }
  'deep-preview' { DoDeepPreview }
  'deep' { DoDeep }
  'restore' { DoRestore $Files }
  default { Write-Output 'Usage: zlog.ps1 preview|clean|deep-preview|deep|restore [-OlderThanDays N] [files...]'; exit 2 }
}

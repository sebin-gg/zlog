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

# Source identity for TOCTOU checks: length + timestamps + full-content
# SHA-256. Content hashing means a same-size in-place rewrite with
# restored timestamps still cannot pass unnoticed. Returns $null when
# unreadable (caller preserves the source).
function zlogIdent($p) {
  try {
    $it = Get-Item -LiteralPath $p -ErrorAction Stop
    $pre = "$($it.Length)|$($it.LastWriteTimeUtc.Ticks)|$($it.CreationTimeUtc.Ticks)"
    $fs = [System.IO.File]::Open($p, 'Open', 'Read', 'ReadWrite')
    try {
      $h = [System.Security.Cryptography.SHA256]::Create()
      try { $hash = [BitConverter]::ToString($h.ComputeHash($fs)).Replace('-', '') }
      finally { $h.Dispose() }
    } finally { $fs.Close() }
    return "$pre|$hash"
  } catch { return $null }
}

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
  # Quarantine-then-verify. A path-based check followed by Remove-Item can never
  # be atomic, and two back-to-back zlogIdent reads close nothing: no work runs
  # between them. Renaming first removes the name, so a writer that opens by
  # path cannot reach the file, and on Windows an open handle blocks the move
  # outright. Only then test emptiness, and put the file back if it gained
  # content. No content hash is needed here: for a file that was empty, any
  # write makes it non-empty, and zlogIdent SHA-256s entire files.
  $script:zlogQuarantine = @{}
  try {
    zlogCandidates 0 $true | ForEach-Object {
      if (-not (zlogFree $_.FullName)) { $locked++; return }
      $src = $_.FullName
      $q = "$src.$PID.purge"
      $script:zlogQuarantine[$q] = $src
      # Key the decision on the ARTIFACT, not on whether the call threw.
      # -PathType Leaf, not bare Test-Path: a directory at the quarantine path
      # would satisfy a bare test and be mistaken for a successful rename.
      try { [System.IO.File]::Move($src, $q) } catch { }
      if (-not (Test-Path -LiteralPath $q -PathType Leaf)) {
        $script:zlogQuarantine.Remove($q); $failed++; return
      }
      $qLen = -1
      try { $qLen = (Get-Item -LiteralPath $q -ErrorAction Stop).Length } catch { $qLen = -1 }
      if ($qLen -eq 0) {
        try { Remove-Item -LiteralPath $q -Force -ErrorAction Stop; $purged++ } catch { $failed++ }
      }
      else {
        # gained content since the scan: put it back untouched
        try { [System.IO.File]::Move($q, $src) } catch { }
        $skipped++
      }
      $script:zlogQuarantine.Remove($q)
    }
  }
  finally {
    # Restore, never delete. A quarantined file is not ours to clean up — it may
    # hold live data — so an abort has to put it back.
    foreach ($q in @($script:zlogQuarantine.Keys)) {
      $s = $script:zlogQuarantine[$q]
      if ((Test-Path -LiteralPath $q) -and -not (Test-Path -LiteralPath $s)) {
        try { [System.IO.File]::Move($q, $s) } catch { }
      }
    }
    $script:zlogQuarantine.Clear()
  }
  zlogCandidates 10 $false | ForEach-Object {
    $cands++
    $preLen = $_.Length
    $preId = zlogIdent $_.FullName
    if (-not $preId) { Write-Output "[zlog] FAILED (source unreadable): $($_.FullName) (original preserved)"; $failed++; return }
    if (-not (zlogFree $_.FullName)) { $locked++; $skipped++; return }
    $tmp = "$($_.FullName).$PID.tmp.tar.gz"
    $out = "$($_.FullName).tar.gz"
    & $tarBin -czf "$tmp" -C "$($_.DirectoryName)" "$($_.Name)" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmp)) {
      if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
      Write-Output "[zlog] FAILED (compressor error): $($_.FullName) (original preserved)"; $failed++; return
    }
    $tmpLen = (Get-Item -LiteralPath $tmp).Length
    if ($tmpLen -le 0 -or $tmpLen -ge $preLen) {
      Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
      $notbene++; $skipped++; return
    }
    if (Test-Path -LiteralPath $out) {
      Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
      Write-Output "[zlog] UNSAFE-SKIP (destination exists): $out (source preserved)"; $skipped++; return
    }
    $cur = zlogIdent $_.FullName
    if (-not $cur -or $cur -ne $preId) {
      Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
      Write-Output "[zlog] FAILED (source changed during compression): $($_.FullName) (original preserved)"; $failed++; return
    }
    try { [System.IO.File]::Move($tmp, $out) }
    catch {
      if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
      Write-Output "[zlog] UNSAFE-SKIP (destination exists): $out (source preserved)"; $skipped++; return
    }
    $cur2 = zlogIdent $_.FullName
    if (-not $cur2 -or $cur2 -ne $preId) {
      Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
      Write-Output "[zlog] FAILED (source changed during compression): $($_.FullName) (original preserved)"; $failed++; return
    }
    $new = (Get-Item -LiteralPath $out).Length
    $raw += $preLen; $saved += ($preLen - $new); $comp++
    Remove-Item -LiteralPath $_.FullName -Force
  }
  zlogReport 'clean' $roots $cands $comp $raw $saved $purged $skipped $failed $notbene $locked
  # Propagate failure. Without this the function ends on the report line, so a
  # run where every file errored still exits 0 and a caller gating on the exit
  # status reads total failure as success. (DoDeep delegates here and inherits
  # the same contract.)
  if ($failed -gt 0) { exit 1 }
}

function DoDeepPreview() {
  Write-Output '[zlog] deep-preview is read-only; known agent locations only (no unknown-agent discovery)'
  Write-Output '[zlog] Windows note: standard roots already recurse fully, so deep-preview covers the same roots as preview'
  DoPreview
}

function DoDeep() {
  Write-Output '[zlog] Windows note: standard roots already recurse fully, so deep is the same operation as clean (same engine, same predicate)'
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
    # `-LiteralPath` everywhere: plain `Test-Path`/`Remove-Item` treat `[` and
    # `]` as wildcard character classes, so a destination literally named
    # e.g. `srv[1].log` failed this guard AND the failure-path cleanup below —
    # the "destination exists" protection silently did nothing for those names.
    if (Test-Path -LiteralPath $out) { Write-Output "[zlog] UNSAFE-SKIP (destination exists): $out"; $fail++; continue }
    $rc = 1
    $wrote = $false
    if ($kind -eq 'tar') {
      $entries = @(& $tarBin -tzf $a 2>$null)
      $base = Split-Path $out -Leaf
      if (($LASTEXITCODE -eq 0) -and ($entries.Count -eq 1) -and ($entries[0] -eq $base)) {
        $tmpd = "$out.$PID.restore.dir"
        $tmpf = Join-Path $tmpd $base
        New-Item -ItemType Directory -Path $tmpd -Force | Out-Null
        & $tarBin -xzf $a -C $tmpd 2>$null
        if (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $tmpf -PathType Leaf)) {
          try { [System.IO.File]::Move($tmpf, $out); $rc = 0; $wrote = $true } catch { $rc = 1 }
        }
        Remove-Item -LiteralPath $tmpd -Recurse -Force -ErrorAction SilentlyContinue
        if ($rc -ne 0) { Write-Output "[zlog] UNSAFE-SKIP (member mismatch or multi-entry): $a"; $fail++; continue }
      }
      else { Write-Output "[zlog] UNSAFE-SKIP (member mismatch or multi-entry): $a"; $fail++; continue }
    }
    else {
      # Stream formats decode to a temp file first: a decompression
      # failure must never leave a partial file at the destination.
      $tmpOut = "$out.$PID.tmp.restore"
      Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
      $streamOk = $false
      if ($kind -eq 'gz' -and (Get-Command gzip -ErrorAction SilentlyContinue)) { gzip -d -c $a > $tmpOut 2>$null; $streamOk = ($LASTEXITCODE -eq 0) }
      elseif ($kind -eq 'zst' -and (Get-Command zstd -ErrorAction SilentlyContinue)) { zstd -d -q $a -o $tmpOut 2>$null; $streamOk = ($LASTEXITCODE -eq 0) }
      elseif ($kind -eq 'xz' -and (Get-Command xz -ErrorAction SilentlyContinue)) { xz -d -c $a > $tmpOut 2>$null; $streamOk = ($LASTEXITCODE -eq 0) }
      # Existence, not non-emptiness: a 0-byte original is a legitimate `.log`,
      # and the old `-gt 0` test rejected it (and then deleted its own output).
      # Corrupt archives are still refused because the decoders exit non-zero.
      if ($streamOk -and (Test-Path -LiteralPath $tmpOut -PathType Leaf)) {
        try { [System.IO.File]::Move($tmpOut, $out); $rc = 0; $wrote = $true } catch { $rc = 1 }
      }
      if (Test-Path -LiteralPath $tmpOut) { Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue }
    }
    # `$wrote` records that THIS run published the destination, so the cleanup
    # below can only ever remove our own artifact — never a pre-existing file
    # that happened to be sitting at the path when the restore failed.
    if (($rc -eq 0) -and $wrote -and (Test-Path -LiteralPath $out -PathType Leaf)) {
      Write-Output "[zlog] RESTORED: $out (archive preserved)"; $ok++
    }
    else {
      if ($wrote -and (Test-Path -LiteralPath $out)) { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
      Write-Output "[zlog] FAILED: $a (nothing written; tool missing or archive invalid)"; $fail++
    }
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

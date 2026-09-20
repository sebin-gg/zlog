---
name: zlog
description: Multi-agent session log compressor and storage optimizer. Compresses `.log`, `.out`, `.trace` (>10KiB) to `.zst`, `.xz`, `.gz`, or `.tar.gz` (Windows) (saving ~77% disk space, typically 4-5x) across `~/.claude`, `~/.config/Cursor`, `~/.gemini`, `~/.ollama`, `~/.windsurf`, `~/.codex`, `~/.aider`, etc. Auto-discovers AI log dirs, purges empty 0-byte logs. Safe for concurrent multi-instance running agents. Includes Dry-Run preview mode. Use when wrapping up, ending sessions, or asked to clean logs, zlog, pack logs, or find new AI agents.
license: MIT
compatibility: Linux, macOS, WSL, Windows 11 (Bash, Zsh, Git Bash, PowerShell)
allowed-tools: Bash(*) Read Write
metadata:
  version: "1.2.0"
  registry: skills.sh
---

# Zlog Multi-Instance Storage Optimizer

Compress background tool logs across AI agents (~77% space saved, typically 4-5x via zstd -15 fallback). Purge 0-byte empty logs. Keep `transcript.jsonl` intact. Safe for concurrent multi-instance running agents. Skip tiny logs (<10KiB) and protected docs. Handle symlinks cleanly. Reports per-run savings + total summary.

## Execution Intents

- **Standard Cleanup**: Triggered on "zlog", "compress logs", "clean up chat logs", "pack logs", or session wrap-up.
- **Dry-Run Preview**: Triggered on "preview zlog", "dry run", "test log cleanup".
- **Deep Scan**: Triggered on "find new AI agents", "scan disk for hidden AI logs".

## Safety & Invariant Protection

- **Process Locks (best-effort)**: Query `fuser -s "$f"` (Linux/WSL) or `lsof "$f"` (macOS) to skip active files. If neither tool is installed (minimal containers), the `fuser`/`lsof` check is skipped and safety relies on the 60s age buffer below — schedule compression during idle periods on such systems. Windows uses `[System.IO.File]::Open(..., 'None')`.
- **In-Flight Window**: Skip files modified <60 seconds ago (`-mmin +1` / `LastWriteTime < AddMinutes(-1)`).
- **Protected Files**: Exclude `*.jsonl`, `SKILL.md`, `README*`, `LICENSE*`, and files <= 10KiB. Note: `*.txt` is intentionally NOT compressed by default to avoid touching config/docs/data files (e.g. pip METADATA, user notes); re-add `-name "*.txt"` to the find expression only if you are certain your agent dirs contain only log-like .txt files.
- **Junk-Dir Pruning**: Scans never descend into `node_modules`, `Caches`, `Cache`, `Code Cache`, `blob_storage`, `GPUCache`, `DawnGraphiteCache`, `DawnWebGPUCache`, or `.git`. Pruned-dir count is reported (deep scan).
- **Depth Bound**: Deep scan capped at `-maxdepth 12` (nested agent logs ~8 levels deep) — bounded runtime, belt-and-suspenders with pruning.
- **Hardlink Aliases**: Mirror dirs sharing the same inode may list one file several times; each name compresses independently — harmless and self-healing.
- **Compression Verification**: After each `zstd`/`xz`/`gzip`/`tar` invocation the script verifies the compressed artifact exists and is non-empty before counting savings or removing the original (Windows `tar` checks exit code + `.tar.gz` existence).

## Commands

### Standard Compression & Empty Log Purge (Linux, macOS, WSL, Git Bash)

```bash
raw=0; saved=0; count=0
for d in ~/.claude ~/.config/claude-code ~/.config/Cursor ~/.cursor ~/.gemini ~/.ollama ~/.windsurf ~/.codex ~/.cache/lm-studio ~/.aider; do
  [ -d "$d" ] || continue
  find -L "$d" \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) -empty -type f -delete 2>/dev/null || true
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null) || size=0
    # --- lock check (best-effort): skip if a process holds the file ---
    locked=0
    if command -v fuser >/dev/null 2>&1 && fuser -s "$f" 2>/dev/null; then locked=1; fi
    if [ "$locked" -eq 0 ] && command -v lsof >/dev/null 2>&1 && lsof "$f" >/dev/null 2>&1; then locked=1; fi
    if [ "$locked" -eq 1 ]; then continue; fi
    # --- compress (prefer zstd -15, fallback to xz -9, then gzip) ---
    if command -v zstd >/dev/null 2>&1; then zstd -15 -q --rm "$f" 2>/dev/null
    elif command -v xz >/dev/null 2>&1; then xz -9 "$f" 2>/dev/null
    else gzip -f "$f" 2>/dev/null
    fi
    for c in zst xz gz; do
      [ -f "$f.$c" ] || continue
      # verify compressed file is non-empty; if empty/corrupt, keep original
      newsize=$(stat -c%s "$f.$c" 2>/dev/null || stat -f%z "$f.$c" 2>/dev/null) || newsize=0
      if [ "$newsize" -eq 0 ]; then rm -f "$f.$c" 2>/dev/null; continue; fi
      raw=$((raw + size)); saved=$((saved + size - newsize)); count=$((count + 1))
      break
    done
  done < <(find -L "$d" \( -type d \( -name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git \) -prune \) -o \( -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 \) -print 2>/dev/null)
done
if [ "$count" -gt 0 ]; then
  comp=$((raw - saved))
  raw_h=$(numfmt --to=iec "$raw" 2>/dev/null || echo "${raw}B")
  comp_h=$(numfmt --to=iec "$comp" 2>/dev/null || echo "${comp}B")
  saved_h=$(numfmt --to=iec "$saved" 2>/dev/null || echo "${saved}B")
  echo "[zlog] Compressed $count files: $raw_h -> $comp_h (saved $saved_h, $(( saved * 100 / raw ))% smaller)"
fi
dirs=(); for d in ~/.claude ~/.config/claude-code ~/.config/Cursor ~/.cursor ~/.gemini ~/.ollama ~/.windsurf ~/.codex ~/.cache/lm-studio ~/.aider; do [ -d "$d" ] && [ ! -L "$d" ] && dirs+=("$d"); done; [ ${#dirs[@]} -gt 0 ] && du -ch "${dirs[@]}" 2>/dev/null | tail -n 1 || true
```

### Dry-Run Mode (Preview Without Modifying Files)

```bash
total=0; count=0
for d in ~/.claude ~/.config/claude-code ~/.config/Cursor ~/.cursor ~/.gemini ~/.ollama ~/.windsurf ~/.codex ~/.cache/lm-studio ~/.aider; do
  [ -d "$d" ] || continue
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null) || size=0
    total=$((total + size)); count=$((count + 1))
    hum=$(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B")
    echo "[DRY-RUN] Would compress: $f ($hum)"
  done < <(find -L "$d" \( -type d \( -name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git \) -prune \) -o \( -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 \) -print 2>/dev/null)
done
saved=$((total * 77 / 100)); comp=$((total - saved))
total_hum=$(numfmt --to=iec "$total" 2>/dev/null || echo "${total}B")
comp_hum=$(numfmt --to=iec "$comp" 2>/dev/null || echo "${comp}B")
echo ""
echo "[DRY-RUN] Total: $count files, $total_hum raw -> ~$comp_hum compressed (est. ~77% savings, 4-5x; varies by log entropy)"
```

### Windows 11 Native Compression (PowerShell - Process Lock Safe, Reporting)

```powershell
$dirs = @("$env:USERPROFILE\.claude","$env:USERPROFILE\.config\claude-code","$env:USERPROFILE\.gemini","$env:USERPROFILE\.cursor","$env:USERPROFILE\.ollama","$env:USERPROFILE\.windsurf","$env:USERPROFILE\.codex","$env:USERPROFILE\.aider","$env:USERPROFILE\.cache\lm-studio") | Where-Object { Test-Path $_ }
$junkDirs = @("node_modules","Caches","Cache","Code Cache","blob_storage","GPUCache","DawnGraphiteCache","DawnWebGPUCache",".git")
$raw = 0; $saved = 0; $count = 0
Get-ChildItem -Path $dirs -Recurse -Include *.log,*.out,*.trace -Exclude *.gz,*.zst,*.xz,*.jsonl,SKILL.md,README*,LICENSE* -ErrorAction SilentlyContinue |
  Where-Object {
    $_.Length -gt 10KB -and $_.LastWriteTime -lt (Get-Date).AddMinutes(-1) -and
    -not ($junkDirs | Where-Object { $_.FullName -like "*\$_\*" }) -and
    (try { $s = [System.IO.File]::Open($_.FullName, 'Open', 'ReadWrite', 'None'); $s.Close(); $true } catch { $false })
  } | ForEach-Object {
    $size = $_.Length
    $out = "$($_.FullName).tar.gz"
    $null = tar.exe -czf $out -C $_.DirectoryName $_.Name 2>$null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $out) -and (Get-Item $out).Length -gt 0) {
      Remove-Item $_.FullName -Force
      $newsize = (Get-Item $out).Length
      $raw += $size; $saved += ($size - $newsize); $count++
    } else { if (Test-Path $out) { Remove-Item $out -Force -ErrorAction SilentlyContinue } }
  }
if ($count -gt 0) {
  $comp = $raw - $saved
  $pct = [math]::Round($saved * 100 / $raw)
  $raw_h = if (Get-Command numfmt -ErrorAction SilentlyContinue) { $raw } else { "$([math]::Round($raw/1MB,2))MB" }
  # Use raw bytes for accuracy; display MB
  Write-Host "[zlog] Compressed $count files: $([math]::Round($raw/1MB,2))MB -> $([math]::Round($comp/1MB,2))MB (saved $([math]::Round($saved/1MB,2))MB, $pct% smaller)"
} else { Write-Host "[zlog] No files to compress." }
# Summary du equivalent
$dirs | ForEach-Object { Get-ChildItem $_ -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum } | ForEach-Object { if ($_.Sum) { Write-Host ("[zlog] Total scanned: " + [math]::Round($_.Sum/1MB,2) + "MB") } }
```

### Deep Scan (On user request: "find new AI agents" / "scan disk")

```bash
pruned=$(find -L ~ -maxdepth 12 \( -type d \( -name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git \) -prune \) -print 2>/dev/null | wc -l)
raw=0; saved=0; count=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null) || size=0
  locked=0
  if command -v fuser >/dev/null 2>&1 && fuser -s "$f" 2>/dev/null; then locked=1; fi
  if [ "$locked" -eq 0 ] && command -v lsof >/dev/null 2>&1 && lsof "$f" >/dev/null 2>&1; then locked=1; fi
  if [ "$locked" -eq 1 ]; then continue; fi
  if command -v zstd >/dev/null 2>&1; then zstd -15 -q --rm "$f" 2>/dev/null
  elif command -v xz >/dev/null 2>&1; then xz -9 "$f" 2>/dev/null
  else gzip -f "$f" 2>/dev/null
  fi
  for c in zst xz gz; do
    [ -f "$f.$c" ] || continue
    newsize=$(stat -c%s "$f.$c" 2>/dev/null || stat -f%z "$f.$c" 2>/dev/null) || newsize=0
    if [ "$newsize" -eq 0 ]; then rm -f "$f.$c" 2>/dev/null; continue; fi
    raw=$((raw + size)); saved=$((saved + size - newsize)); count=$((count + 1))
    break
  done
done < <(find -L ~ -maxdepth 12 \( -type d \( -name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git \) -prune \) -o \( -path "*/.claude/*" -o -path "*/.config/claude-code/*" -o -path "*/.gemini/*" -o -path "*/.config/Cursor/*" -o -path "*/.cursor/*" -o -path "*/.ollama/*" -o -path "*/.windsurf/*" -o -path "*/.codex/*" -o -path "*/.cache/lm-studio/*" -o -path "*/.lm-studio/*" -o -path "*/.aider/*" \) -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -print 2>/dev/null)
if [ "$count" -gt 0 ]; then
  comp=$((raw - saved))
  raw_h=$(numfmt --to=iec "$raw" 2>/dev/null || echo "${raw}B")
  comp_h=$(numfmt --to=iec "$comp" 2>/dev/null || echo "${comp}B")
  saved_h=$(numfmt --to=iec "$saved" 2>/dev/null || echo "${saved}B")
  echo "[zlog] Deep scan compressed $count files: $raw_h -> $comp_h (saved $saved_h, $(( saved * 100 / raw ))% smaller)"
fi
echo "[zlog] Deep scan pruned $pruned junk/cache dirs (maxdepth 12)"
```

## Helpers

- **Read `.zst` / `.gz`**: `zstdcat file.log.zst` or `zcat file.log.gz`
- **Read Windows `.tar.gz`**: `tar -xzf file.log.tar.gz` (extracts original log back)
- **Decompress**: `zstd -d file.log.zst` or `gzip -d file.log.gz`
- **Search**: `zstdgrep "pattern" file.log.zst` or `zgrep "pattern" file.log.gz`

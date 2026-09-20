---
name: zlog
description: Multi-agent session log compressor and storage optimizer. Compresses `.log`, `.out`, `.trace` (>10KiB) to `.zst`, `.xz`, `.gz`, or `.tar.gz` (Windows) across `~/.claude`, `~/.config/Cursor`, `~/.gemini`, `~/.ollama`, `~/.windsurf`, `~/.codex`, `~/.aider`, etc. Auto-discovers AI log dirs, purges empty 0-byte logs. Safe for concurrent multi-instance running agents. Includes Dry-Run preview mode. Use when wrapping up, ending sessions, or asked to clean logs, zlog, pack logs, or find new AI agents.
license: MIT
compatibility: Linux, Windows 11 (Bash, Zsh, Git Bash, PowerShell)
allowed-tools: Bash(find:* stat:* fuser:* lsof:* zstd:* xz:* gzip:* tar:* du:* awk:* tail:* wc:*) Read Write
metadata:
  version: "1.6.0"
  registry: skills.sh
---

# Zlog Multi-Instance Storage Optimizer

Compress background tool logs across AI agents (zstd -15 with xz/gzip fallback). Purge 0-byte empty logs. Keep `transcript.jsonl` intact. Safe for concurrent multi-instance running agents. Skip tiny logs (<10KiB) and protected docs. Handle symlinks cleanly. Reports per-run savings + total summary.

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
prune=(-name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git)
for d in ~/.claude ~/.config/claude-code ~/.config/Cursor ~/.cursor ~/.gemini ~/.ollama ~/.windsurf ~/.codex ~/.cache/lm-studio ~/.lm-studio ~/.aider "$HOME/Library/Application Support/Cursor" "$HOME/Library/Application Support/Windsurf" ~/.config/Windsurf "$HOME/AppData/Local/Ollama"; do
  [ -d "$d" ] || continue
  find -L "$d" \( -type d \( "${prune[@]}" \) -prune \) -o \( -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) -empty -exec rm -f {} + \) 2>/dev/null || true
  while IFS= read -r -d '' f; do
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
  done < <(find -L "$d" \( -type d \( "${prune[@]}" \) -prune \) -o \( -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -print0 \) 2>/dev/null)
done
if [ "$count" -gt 0 ]; then
  comp=$((raw - saved))
  raw_h=$(echo "$raw" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  comp_h=$(echo "$comp" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  saved_h=$(echo "$saved" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  pct=0; [ "$raw" -gt 0 ] && pct=$(( saved * 100 / raw ))
  echo "[zlog] Compressed $count files: $raw_h -> $comp_h (saved $saved_h, $pct% smaller)"
fi
dirs=(); for d in ~/.claude ~/.config/claude-code ~/.config/Cursor ~/.cursor ~/.gemini ~/.ollama ~/.windsurf ~/.codex ~/.cache/lm-studio ~/.lm-studio ~/.aider "$HOME/Library/Application Support/Cursor" "$HOME/Library/Application Support/Windsurf" ~/.config/Windsurf "$HOME/AppData/Local/Ollama"; do [ -d "$d" ] && [ ! -L "$d" ] && dirs+=("$d"); done; [ ${#dirs[@]} -gt 0 ] && du -ch "${dirs[@]}" 2>/dev/null | tail -n 1 || true
```

### Dry-Run Mode (Preview Without Modifying Files)

```bash
total=0; count=0
prune=(-name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git)
for d in ~/.claude ~/.config/claude-code ~/.config/Cursor ~/.cursor ~/.gemini ~/.ollama ~/.windsurf ~/.codex ~/.cache/lm-studio ~/.lm-studio ~/.aider "$HOME/Library/Application Support/Cursor" "$HOME/Library/Application Support/Windsurf" ~/.config/Windsurf "$HOME/AppData/Local/Ollama"; do
  [ -d "$d" ] || continue
  while IFS= read -r -d '' f; do
    [ -z "$f" ] && continue
    size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null) || size=0
    total=$((total + size)); count=$((count + 1))
    hum=$(echo "$size" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
    echo "[DRY-RUN] Would compress: $f ($hum)"
  done < <(find -L "$d" \( -type d \( "${prune[@]}" \) -prune \) -o \( -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -print0 \) 2>/dev/null)
done
total_hum=$(echo "$total" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
echo ""
echo "[DRY-RUN] Total: $count files, $total_hum raw (compressed size varies by log content)"
```

### Windows 11 Compression (PowerShell — tested on Windows 11)

```powershell
$zlogPaths = "$env:USERPROFILE\.gemini","$env:APPDATA\Cursor","$env:USERPROFILE\.config\Cursor","$env:USERPROFILE\.cursor","$env:USERPROFILE\.ollama","$env:LOCALAPPDATA\Ollama","$env:USERPROFILE\.claude","$env:USERPROFILE\.config\claude-code","$env:USERPROFILE\.windsurf","$env:APPDATA\Windsurf","$env:USERPROFILE\.config\Windsurf","$env:USERPROFILE\.codex","$env:USERPROFILE\.cache\lm-studio","$env:USERPROFILE\.lm-studio"
$junk = '\node_modules\','\Caches\','\Cache\','\Code Cache\','\blob_storage\','\GPUCache\','\DawnGraphiteCache\','\DawnWebGPUCache\','\.git\'
function zlogFmt($b) { if ($b -ge 1073741824) { "{0:N1}G" -f ($b/1073741824) } elseif ($b -ge 1048576) { "{0:N1}M" -f ($b/1048576) } elseif ($b -ge 1024) { "{0:N1}K" -f ($b/1024) } else { "${b}B" } }
function zlogFree($p) { try { $s = [System.IO.File]::Open($p, 'Open', 'ReadWrite', 'None'); $s.Close(); $true } catch { $false } }
Get-ChildItem -Path $zlogPaths -Recurse -Include *.log,*.out,*.trace -Exclude *.gz,*.zst,*.xz,*.jsonl,SKILL.md,README*,LICENSE* -ErrorAction SilentlyContinue | Where-Object { $p = $_.FullName; $_.Length -eq 0 -and -not ($junk | Where-Object { $p -like "*$_*" }) } | Remove-Item -Force -ErrorAction SilentlyContinue
$count=0; $raw=0; $saved=0
Get-ChildItem -Path $zlogPaths -Recurse -Include *.log,*.out,*.trace -Exclude *.gz,*.zst,*.xz,*.jsonl,SKILL.md,README*,LICENSE* -ErrorAction SilentlyContinue | Where-Object { $p = $_.FullName; $_.Length -gt 10KB -and $_.LastWriteTime -lt (Get-Date).AddMinutes(-1) -and -not ($junk | Where-Object { $p -like "*$_*" }) -and (zlogFree $p) } | ForEach-Object { $size=$_.Length; $out="$($_.FullName).tar.gz"; tar.exe -czf "$out" -C "$($_.DirectoryName)" "$($_.Name)"; if ($LASTEXITCODE -eq 0 -and (Test-Path $out) -and ((Get-Item $out).Length -gt 0)) { $new=(Get-Item $out).Length; $raw+=$size; $saved+=($size-$new); $count++; Remove-Item $_.FullName } }
if ($count -gt 0) { $comp=$raw-$saved; $pct=0; if ($raw -gt 0) { $pct=[math]::Floor($saved*100/$raw) }; echo "[zlog] Compressed $count files: $(zlogFmt $raw) -> $(zlogFmt $comp) (saved $(zlogFmt $saved), $pct% smaller)" }
```

### Deep Scan (On user request: "find new AI agents" / "scan disk")

```bash
prune=(-name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git)
pruned=$(find -L ~ -maxdepth 12 -type d \( "${prune[@]}" \) -prune -print 2>/dev/null | wc -l)
raw=0; saved=0; count=0
while IFS= read -r -d '' f; do
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
    newsize=$(stat -c%s "$f.$c" 2>/dev/null || stat -f%z "$f.$c" 2>/dev/null) || newsize=0
    if [ "$newsize" -eq 0 ]; then rm -f "$f.$c" 2>/dev/null; continue; fi
    raw=$((raw + size)); saved=$((saved + size - newsize)); count=$((count + 1))
    break
  done
done < <(find -L ~ -maxdepth 12 \( -type d \( "${prune[@]}" \) -prune \) -o \( -path "*/.claude/*" -o -path "*/.config/claude-code/*" -o -path "*/.gemini/*" -o -path "*/.config/Cursor/*" -o -path "*/.cursor/*" -o -path "*/.ollama/*" -o -path "*/.windsurf/*" -o -path "*/.codex/*" -o -path "*/.cache/lm-studio/*" -o -path "*/.lm-studio/*" -o -path "*/.aider/*" -o -path "*/Library/Application Support/Cursor/*" -o -path "*/Library/Application Support/Windsurf/*" -o -path "*/.config/Windsurf/*" -o -path "*/AppData/*" \) -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -print0 2>/dev/null)
if [ "$count" -gt 0 ]; then
  comp=$((raw - saved))
  raw_h=$(echo "$raw" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  comp_h=$(echo "$comp" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  saved_h=$(echo "$saved" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  pct=0; [ "$raw" -gt 0 ] && pct=$(( saved * 100 / raw ))
  echo "[zlog] Deep scan: $count files, $raw_h -> $comp_h (saved $saved_h, $pct% smaller)"
else
  echo "[zlog] Deep scan: no compressible files found"
fi
echo "[zlog] Pruned $pruned junk/cache dirs (maxdepth 12)"
```

## Helpers

- **Read `.zst` / `.gz`**: `zstdcat file.log.zst` or `zcat file.log.gz`
- **Read Windows `.tar.gz`**: `tar -xzf file.log.tar.gz` (extracts original log back)
- **Decompress**: `zstd -d file.log.zst` or `gzip -d file.log.gz`
- **Search**: `zstdgrep "pattern" file.log.zst` or `zgrep "pattern" file.log.gz`

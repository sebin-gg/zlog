---
name: zlog
description: Compresses AI agent session logs (`.log`, `.out`, `.txt`, `.trace` over 10KiB) to `.zst`, `.xz`, `.gz`, or `.tar.gz` (PowerShell). Purges empty 0-byte logs, skips locked and in-flight files. Use when wrapping up, ending sessions, or asked to clean logs, zlog, pack logs, or find new AI agents.
license: MIT
compatibility: Linux (Bash, Zsh — tested). macOS, WSL, Windows 11 (Git Bash, PowerShell) snippets included but not runtime-tested.
allowed-tools: Bash(find:* stat:* fuser:* lsof:* zstd:* xz:* gzip:* tar:* du:* awk:* tail:*) Read Write
metadata:
  version: "1.5.0"
  registry: skills.sh
---

# Zlog Multi-Instance Storage Optimizer

Compress background tool logs across AI agents (zstd -15 with xz/gzip fallback). Purge 0-byte empty logs. Keep `transcript.jsonl` intact. Skip locked and in-flight files; live-agent safety not runtime-tested. Skip tiny logs (<10KiB) and text docs. Skips symlinked top dirs in final total. Reports per-run savings + total summary.

## Execution Intents

- **Standard Cleanup**: Triggered on "zlog", "compress logs", "clean up chat logs", "pack logs", or session wrap-up.
- **Dry-Run Preview**: Triggered on "preview zlog", "dry run", "test log cleanup".
- **Deep Scan**: Triggered on "find new AI agents", "scan disk for hidden AI logs".

## Safety & Invariant Protection

- **Process Locks**: Query `fuser -s "$f"` (Linux/WSL), `lsof "$f"` (macOS), or `[System.IO.File]::Open(..., 'None')` (Windows 11 PowerShell). Skip file if active process lock exists. Requires `fuser` or `lsof`; without either only the 60s age buffer protects in-flight files.
- **In-Flight Window**: Skip files modified <60 seconds ago (`-mmin +1`).
- **Protected Files**: Exclude `*.jsonl`, `SKILL.md`, `README*`, `LICENSE*`, and files <= 10KiB.
- **Junk-Dir Pruning**: Every scan shares one canonical prune list — `node_modules`, `Caches`, `Cache`, `Code Cache`, `blob_storage`, `GPUCache`, `DawnGraphiteCache`, `DawnWebGPUCache`, `.git` — defined once per snippet as `prune=(...)` and passed as `"${prune[@]}"` (POSIX; PowerShell applies the same segments as path filters). Pruned-dir count is reported.
- **Depth Bound**: Deep scan capped at `-maxdepth 12` (Antigravity nests ~8 levels deep) — bounded runtime, belt-and-suspenders with pruning.
- **Hardlink Aliases**: Mirror dirs sharing the same inode (e.g. Antigravity `antigravity-*` copies) may list one file several times; each name compresses independently.

## Commands

### Standard Compression & Empty Log Purge (POSIX shell — tested on Linux)

```bash
raw=0; saved=0; count=0
prune=(-name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git)
for d in ~/.gemini ~/.config/Cursor "$HOME/Library/Application Support/Cursor" ~/.cursor ~/.ollama "$HOME/AppData/Local/Ollama" ~/.claude ~/.config/claude-code ~/.windsurf ~/.config/Windsurf "$HOME/Library/Application Support/Windsurf" ~/.codex ~/.cache/lm-studio ~/.lm-studio; do
  [ -d "$d" ] || continue
  find -L "$d" \( -type d \( "${prune[@]}" \) -prune \) -o \( -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -empty -exec rm -f {} + \) 2>/dev/null || true
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
  done < <(find -L "$d" \( -type d \( "${prune[@]}" \) -prune \) -o \( -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -print0 \) 2>/dev/null)
done
if [ "$count" -gt 0 ]; then
  comp=$((raw - saved))
  raw_h=$(echo "$raw" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  comp_h=$(echo "$comp" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  saved_h=$(echo "$saved" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  pct=0; [ "$raw" -gt 0 ] && pct=$(( saved * 100 / raw ))
  echo "[zlog] Compressed $count files: $raw_h -> $comp_h (saved $saved_h, $pct% smaller)"
fi
dirs=(); for d in ~/.gemini ~/.config/Cursor "$HOME/Library/Application Support/Cursor" ~/.cursor ~/.ollama "$HOME/AppData/Local/Ollama" ~/.claude ~/.config/claude-code ~/.windsurf ~/.config/Windsurf "$HOME/Library/Application Support/Windsurf" ~/.codex ~/.cache/lm-studio ~/.lm-studio; do [ -d "$d" ] && [ ! -L "$d" ] && dirs+=("$d"); done; [ ${#dirs[@]} -gt 0 ] && du -ch "${dirs[@]}" 2>/dev/null | tail -n 1 || true
```

### Dry-Run Mode (Preview Without Modifying Files)

```bash
total=0; count=0
prune=(-name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git)
for d in ~/.gemini ~/.config/Cursor "$HOME/Library/Application Support/Cursor" ~/.cursor ~/.ollama "$HOME/AppData/Local/Ollama" ~/.claude ~/.config/claude-code ~/.windsurf ~/.config/Windsurf "$HOME/Library/Application Support/Windsurf" ~/.codex ~/.cache/lm-studio ~/.lm-studio; do
  [ -d "$d" ] || continue
  while IFS= read -r -d '' f; do
    [ -z "$f" ] && continue
    size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null) || size=0
    total=$((total + size)); count=$((count + 1))
    hum=$(echo "$size" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
    echo "[DRY-RUN] Would compress: $f ($hum)"
  done < <(find -L "$d" \( -type d \( "${prune[@]}" \) -prune \) -o \( -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -print0 \) 2>/dev/null)
done
saved=$((total * 77 / 100)); comp=$((total - saved))
total_hum=$(echo "$total" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
comp_hum=$(echo "$comp" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
echo ""
echo "[DRY-RUN] Total: $count files, $total_hum raw -> ~$comp_hum compressed (est. ~77% savings, 4-5x; varies by log entropy)"
```

### Windows 11 Compression (PowerShell — not runtime-tested)

```powershell
$zlogPaths = "$env:USERPROFILE\.gemini","$env:APPDATA\Cursor","$env:USERPROFILE\.config\Cursor","$env:USERPROFILE\.cursor","$env:USERPROFILE\.ollama","$env:LOCALAPPDATA\Ollama","$env:USERPROFILE\.claude","$env:USERPROFILE\.config\claude-code","$env:USERPROFILE\.windsurf","$env:APPDATA\Windsurf","$env:USERPROFILE\.config\Windsurf","$env:USERPROFILE\.codex","$env:USERPROFILE\.cache\lm-studio","$env:USERPROFILE\.lm-studio"
$junk = '\node_modules\','\Caches\','\Cache\','\Code Cache\','\blob_storage\','\GPUCache\','\DawnGraphiteCache\','\DawnWebGPUCache\','\.git\'
function zlogFmt($b) { if ($b -ge 1073741824) { "{0:N1}G" -f ($b/1073741824) } elseif ($b -ge 1048576) { "{0:N1}M" -f ($b/1048576) } elseif ($b -ge 1024) { "{0:N1}K" -f ($b/1024) } else { "${b}B" } }
Get-ChildItem -Path $zlogPaths -Recurse -Include *.log,*.out,*.txt,*.trace -Exclude *.gz,*.zst,*.xz,*.jsonl,SKILL.md,README*,LICENSE* -ErrorAction SilentlyContinue | Where-Object { $p = $_.FullName; $_.Length -eq 0 -and -not ($junk | Where-Object { $p -like "*$_*" }) } | Remove-Item -Force -ErrorAction SilentlyContinue
$count=0; $raw=0; $saved=0
Get-ChildItem -Path $zlogPaths -Recurse -Include *.log,*.out,*.txt,*.trace -Exclude *.gz,*.zst,*.xz,*.jsonl,SKILL.md,README*,LICENSE* -ErrorAction SilentlyContinue | Where-Object { $p = $_.FullName; $_.Length -gt 10KB -and $_.LastWriteTime -lt (Get-Date).AddMinutes(-1) -and -not ($junk | Where-Object { $p -like "*$_*" }) -and (try { $s = [System.IO.File]::Open($_.FullName, 'Open', 'ReadWrite', 'None'); $s.Close(); $true } catch { $false }) } | ForEach-Object { $size=$_.Length; tar.exe -czf "$($_.FullName).tar.gz" -C $_.DirectoryName $_.Name; if ($LASTEXITCODE -eq 0 -and (Test-Path "$($_.FullName).tar.gz")) { $new=(Get-Item "$($_.FullName).tar.gz").Length; $raw+=$size; $saved+=($size-$new); $count++; Remove-Item $_.FullName } }
if ($count -gt 0) { $comp=$raw-$saved; $pct=0; if ($raw -gt 0) { $pct=[math]::Floor($saved*100/$raw) }; echo "[zlog] Compressed $count files: $(zlogFmt $raw) -> $(zlogFmt $comp) (saved $(zlogFmt $saved), $pct% smaller)" }
```

### Deep Scan (On user request: "find new AI agents" / "scan disk")

```bash
prune=(-name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git)
pruned=$(find -L ~ -maxdepth 12 \( -type d \( "${prune[@]}" \) -prune \) -print 2>/dev/null | wc -l)
raw=0; saved=0; count=0
while IFS= read -r -d '' f; do
  size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null) || size=0
  (command -v fuser >/dev/null 2>&1 && fuser -s "$f" 2>/dev/null) || (command -v lsof >/dev/null 2>&1 && lsof "$f" >/dev/null 2>&1) || (command -v zstd >/dev/null 2>&1 && zstd -15 -q --rm "$f") || (command -v xz >/dev/null 2>&1 && xz -9 "$f") || gzip -f "$f"
  for c in zst xz gz; do
    [ -f "$f.$c" ] || continue
    newsize=$(stat -c%s "$f.$c" 2>/dev/null || stat -f%z "$f.$c" 2>/dev/null) || newsize=0
    raw=$((raw + size)); saved=$((saved + size - newsize)); count=$((count + 1))
    break
  done
done < <(find -L ~ -maxdepth 12 \( -type d \( "${prune[@]}" \) -prune \) -o \( -path "*/.gemini/*" -o -path "*/.config/Cursor/*" -o -path "*/Library/Application Support/Cursor/*" -o -path "*/AppData/Roaming/Cursor/*" -o -path "*/.cursor/*" -o -path "*/.claude/*" -o -path "*/.config/claude-code/*" -o -path "*/.ollama/*" -o -path "*/AppData/Local/Ollama/*" -o -path "*/.windsurf/*" -o -path "*/.config/Windsurf/*" -o -path "*/Library/Application Support/Windsurf/*" -o -path "*/AppData/Roaming/Windsurf/*" -o -path "*/.codex/*" -o -path "*/.cache/lm-studio/*" -o -path "*/.lm-studio/*" \) -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -print0 2>/dev/null)
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
